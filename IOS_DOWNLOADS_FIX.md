# iOS downloads list fix

## The problem

On iOS the downloads list emptied itself. Users who put the app in the background, lost
connectivity for a moment, or came back to the app later found that a media they had started
downloading was gone from the list. In some cases the transfer kept running (or even finished)
while the app showed nothing at all.

The reports started after commit `3577bfb` ("Add foreground URLSession and tweak background"),
which moved new downloads onto a `URLSessionConfiguration.default` session. That commit exposed a
second family of problems that had been dormant in the download bookkeeping for a long time: the
list was rebuilt purely from the live `URLSession` tasks, so anything the session forgot was gone
for good, and the mapping between a task and its media was stored under a key that iOS reuses
across launches.

The fix puts every transfer back on the background session, and gives every in-flight download a
record on disk so the list no longer depends on what a session happens to remember.

## Origin legend

Used in the tables below:

| Label | Meaning |
| --- | --- |
| **Regression (3577bfb)** | Introduced by commit `3577bfb` |
| **Pre-existing** | Present well before `3577bfb` |
| **Pre-existing, exposed by 3577bfb** | Harmless until the foreground session was introduced |
| **New safeguard** | No equivalent existed before; added so the fix holds in production |

---

## `ios/Classes/Managers/DownloadManager.swift`

The bulk of the work. Public API and method-channel payloads are unchanged.

| # | Change | Why | Origin |
| --- | --- | --- | --- |
| 1 | Removed `foregroundUrlSession`; `startDownload` creates its task on the background session again | A `.default` session dies with the app: it stops when the process is suspended, its tasks cannot be listed after a relaunch, and it does not retry when the connection drops. The background session survives suspension, is handed back on relaunch, and keeps transferring while the app is closed | **Regression (3577bfb)** |
| 2 | Kept `isDiscretionary = false`, `allowsCellularAccess = true` and no `countOfBytesClientExpectsToReceive` | These were the real fix for the slow downloads in `3577bfb`, and they work fine on a background session. Only the session swap was wrong | Kept from `3577bfb` |
| 3 | `updateTasks` merges the session's tasks with the ones this launch created instead of replacing the whole list, and ignores tasks in `.canceling` | Replacing the list wiped every running download from memory on each call, and `config()` calls it on every app start/resume. Cancelled-but-not-yet-finished tasks used to reappear in the list for a moment | **Pre-existing, exposed by 3577bfb** |
| 4 | Every in-flight download is persisted as a `.keetmp` record when it starts, kept updated on pause/failure, and deleted when it completes or is cancelled | This record is what makes a media survive a force quit or a session that lost its task. The restore path (`getTempData` → `reCallRequest`) already existed in `config()`, but the only writer was `saveDownloadStatus()`, which nothing ever called, so no record was ever written | **Pre-existing** (dead restore path) |
| 5 | `config()` now restores pending downloads only after `getAllTasks` has answered | Restoring before knowing what the session is still running starts a second transfer for the same media | **Pre-existing** race, newly reachable now that records exist |
| 6 | Media identity moved into `taskDescription` (`<mediaId>\u{1F}<name>`), with a fallback to the old `task_id_<taskIdentifier>` UserDefaults key. Added `mediaName`, `mediaSignature` and `mediaType` helpers | `taskIdentifier` is only unique inside one session and is reused across launches, so identities could be read, overwritten or erased for the wrong media. `taskDescription` is restored by URLSession together with the task. The fallback keeps downloads started by older builds working after the update | **Pre-existing** |
| 7 | `didCompleteWithError` no longer clears the media id. It keeps the record, stores the resume data, and never turns a download the user paused back on | Clearing the id detached the task from its media, after which the entry was filtered out of `getAllMedia` and disappeared. Without the pause check, a cancellation delivered by the system would silently resume a download the user had paused | **Pre-existing** |
| 8 | `didFinishDownloadingTo` reads the owner from the task itself (`mediaSignature`) instead of the (possibly missing) configuration | iOS relaunches the app in the background to hand over a finished transfer, long before Flutter calls `config_downloader`. The old code read `settings.userSignature` on an implicitly unwrapped `nil`, and `FilesManager` still had an empty user, so a completed download was either a crash or a file filed under an empty signature: downloaded, but invisible forever | **Pre-existing** |
| 9 | A response outside `200...299` is no longer stored as the media; the download stays pending instead | URLSession treats a 403/404 body as a successful download. With signed URLs that carry an `expires` parameter, an expired link produced a few-kilobyte "movie" that looked downloaded and never played | **Pre-existing** |
| 10 | Resume data is saved on failure and used on the next attempt (`downloadTask(withResumeData:)`) | Interrupted transfers used to start again from zero, on connections and file sizes where that is expensive | **New safeguard** |
| 11 | A failed transfer is retried automatically with a growing delay (10s, doubling, capped at 5 min) | Recovery used to require the user to reopen the app | **New safeguard** |
| 12 | Stall watchdog: a running task that receives no bytes for two checks in a row (30s each) is cancelled with resume data and restarted | Verified on the simulator: after the connection dies, iOS can leave a background task waiting indefinitely without ever reporting an error, so nothing else would ever fire. This is the case that matches "the network came back but the download stayed frozen" | **New safeguard** |
| 13 | `NWPathMonitor` triggers a restore pass when connectivity comes back | Picks up anything the session gave up on while the device was offline | **New safeguard** |
| 14 | `getAllMedia`, `getDownloadingEpisodes`, `getDownloadingSeasons`, `getDownloadedMovie` and `getDownloadedEpisode` go through one `downloadingMedia()` helper that merges live tasks with records that have no live task | Without it a restored record would not show up in the list, and the series/season screens read the task list directly | Follows from #4 |
| 15 | `cancelTask` deletes the record, the resume data and the stored media payload before cancelling | The payload key in UserDefaults used to leak forever, and without deleting the record first the cancellation callback would bring the download back | **Pre-existing** |
| 16 | `resumeDownload` falls back to restarting from the record when no live task exists | Resuming a media whose transfer died while the app was closed used to do nothing | **Pre-existing** |
| 17 | `saveDownloadStatus()` only persists records now; it no longer cancels every task | Cancelling transfers is exactly what must not happen when the app goes to the background with a background session. The method had no caller, so this changes nothing for existing users | **Pre-existing** |
| 18 | Internal test seams: `sessionIdentifierOverride`, `simulateAppRelaunch(completion:)`, `forgetConfiguration()`, `stallCheckInterval` | Needed to simulate a relaunch and a background hand-over in tests. All are `internal`, so they are not part of the framework's public API | Test support |

## `ios/Classes/Managers/FilesManager.swift`

| Change | Why | Origin |
| --- | --- | --- |
| Added `hasTempData(id:user:)` and `getTempData(id:user:)` | The delegate needs to know whether a media is still wanted (not cancelled) and what state it was in, without loading every record | Supports the record layer |
| Added `saveResumeData` / `getResumeData` / `clearResumeData` (`.keeresume` files next to the records) | Storage for the bytes iOS hands back when a transfer fails | **New safeguard** |
| `getTempData(user:)` now skips files that are not `.keetmp` and stamps the decoded media with its owner signature | The folder also holds resume data now, and a decoded record needs its signature to resolve its own paths | Supports the record layer |
| `checkFolderExistance(dir:)` is fed `url.path` instead of `url.absoluteString`, in `saveTempData` and `forUser` | `absoluteString` is a `file://` URL, so the check never matched and the directory was recreated on every call | **Pre-existing** (harmless, fixed while nearby) |
| Removed the `print` calls from `saveTempData` | It now runs on every download start, pause and failure | Housekeeping |

## `ios/Classes/Data Models/DownloadedMedia.swift`

| Change | Why | Origin |
| --- | --- | --- |
| `reCallRequest()` no longer calls `DownloadManager.shared.updateTasks()` | `startDownload` already tracks the task synchronously. The extra asynchronous reload only added churn, and with the old replace-the-list behaviour it could drop the task it had just created | **Pre-existing** |

---

## Example app and test infrastructure

Nothing below ships in the plugin; it only exists so the fix can be proven and kept proven.

| File | Change | Why |
| --- | --- | --- |
| `example/ios/RunnerTests/DownloadManagerTests.swift` | New: 14 tests driving the real `DownloadManager` | Covers the reported regression, relaunch, force quit, interrupted transfer, stalled transfer, error responses, pause, cancel, series grouping and task identity |
| `example/ios/RunnerTests/LocalHTTPServer.swift` | New: a small HTTP/1.1 server inside the test process | Gives the tests full control of the network: throttling, range requests (needed to verify a resumed transfer), dropping a connection mid-body, and hanging without closing |
| `example/ios/Runner.xcodeproj/project.pbxproj` | Added the `RunnerTests` unit-test bundle hosted by `Runner`, linking `dowplay` | There was no test target in the repository at all |
| `example/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` | `RunnerTests` added to the scheme's test action | So `xcodebuild test -scheme Runner` runs the suite |
| `example/ios/Podfile` (+ `Podfile.lock`) | Added the `RunnerTests` pod target (`inherit! :search_paths`) and `ENABLE_TESTABILITY = YES` for Debug | Required by `@testable import dowplay` |
| `example/ios/Runner/Info.plist` | App Transport Security exception for `127.0.0.1` / `localhost` | The test server is plain HTTP on loopback. Example app only; the plugin and its host apps are unaffected |

---

## What the host app sees

* No change to the method channel: same methods, same arguments, same dictionaries.
* A media now stays in the list until it finishes or is cancelled, including across app relaunches
  and outages. Entries restored from disk carry the last known `progress` until the transfer
  reports again.
* A download that answered with an HTTP error is reported as paused (`retrivalStatus = 1`) instead
  of appearing as a completed media.
* `saveDownloadStatus()` no longer cancels the running transfers.

## Running the tests

```sh
cd example/ios
xcodebuild test -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'id=<simulator-udid>' -only-testing:RunnerTests
```

`xcrun simctl list devices available` lists the simulator identifiers. The suite takes about 90
seconds; the stall test alone accounts for roughly 30 of them.

## Verification performed

* 14/14 tests pass on an iPhone 16 simulator (iOS 18.0).
* Mutation checks: restoring the pre-fix behaviour (foreground session, list replacement, no
  records) makes the suite fail with `the running download disappeared from the list`; removing the
  owner recovery in `didFinishDownloadingTo` makes the completed file never reach its user folder.
  The tests fail for the reported symptom, so they are not vacuous.
* Manual runs of the example app against a throttled local server with a 200 MB file:
  app sent to background for 25s (list kept, transfer continued, no duplicate); app killed and
  relaunched (media restored, file completed and byte-identical to the source); server killed for
  20s (media stayed in the list) and brought back (the app resumed on its own from
  `Range: bytes=18612224-` and finished byte-identical, without being reopened).

## Known issues left untouched

* **No limit on concurrent downloads.** `startDownload` resumes every task immediately; the only
  implicit limit is `httpMaximumConnectionsPerHost` (never configured, so 4 per host on iOS), and
  queued tasks still report as running to the app. Android has no cap either: `DownloadService.kt`
  initialises PRDownloader with database and timeouts only, so it uses the library's default pool
  of `2 × availableProcessors` threads.
* `FilesManager.saveMovieInfo` moves the downloaded file twice; the second move always fails and is
  swallowed.
* `deleteMovieBy` and `deleteEpisode` force-unwrap `tempPath`, which can crash for a media that has
  no temp path.
* `getAllMedia` reads the records from disk on the calling (main) thread. Fine for the handful of
  downloads a user has, but it is file I/O on the UI thread.
