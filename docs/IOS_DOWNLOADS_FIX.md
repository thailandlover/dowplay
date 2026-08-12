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
| 18 | `asListEntry(_:)` strips `mediaURL` and `retrivalStatus` from records before they leave the manager | A record carries restart information a live task does not. Without this, an entry rebuilt from disk reached Flutter with two keys the same media did not have while its task was alive. The host app must receive the same payload for a media wherever the entry came from | Follows from #4 |
| 19 | Internal test seams: `sessionIdentifierOverride`, `simulateAppRelaunch(completion:)`, `forgetConfiguration()`, `stallCheckInterval` | Needed to simulate a relaunch and a background hand-over in tests. All are `internal`, so they are not part of the framework's public API | Test support |

### Why row 3 was worth changing even though it was not the reported bug

Replacing the list was safe as long as the session being queried was also the session creating the
tasks, which was the case before `3577bfb`. It was not completely safe, because `getAllTasks` is
asynchronous: it answers with a snapshot taken when the question was asked, and replacing the list
with that snapshot throws away anything that started in between.

| Time | What happens (pre-`3577bfb` code, single background session) |
| --- | --- |
| `t = 0 ms` | The app starts and Flutter calls `config_downloader`. That first access creates `DownloadManager.shared`, whose `init()` calls `updateTasks()`, which asks the download daemon for its tasks |
| `t = 5 ms` | The user taps download on an episode. `startDownload` creates the task and appends it, and `getAllMediaDecoded()` returns a list containing it, so the app shows it |
| `t = 120 ms` | The answer to the question asked at `t = 0` arrives. It is a snapshot of a moment when the task did not exist yet, and `self.tasks` is replaced by it: the download is gone from memory |
| after | The transfer keeps running at system level, but nothing shows it. In the old code only `reCallRequest` called `updateTasks` again, and that path was dead, so the entry stayed missing for the rest of the session |

The window is narrow, so this stayed a rare bug rather than a reported one. It also becomes a
different kind of problem once downloads have records on disk: `config()` restores from the records
right after `updateTasks`, so a list emptied by a stale snapshot makes the restore believe nothing
is running and start a **second transfer of a download that is already live** — double the data,
two temp files, and an orphaned first transfer. The merge closes both, and
`testRunningDownloadSurvivesReconfiguration` asserts the server only ever receives one request per
media.

The same row also stops accepting tasks in `.canceling`. A cancelled task lingers in that state for
a moment, and `cancelTask` has already removed its payload, so it used to come back into the list
for a second or two as a row with no data. This was seen for real while running the suite.

## `ios/Classes/Managers/FilesManager.swift`

### Support for the record layer

| Change | Why | Origin |
| --- | --- | --- |
| Added `hasTempData(id:user:)` and `getTempData(id:user:)` | The delegate needs to know whether a media is still wanted (not cancelled) and what state it was in, without loading every record | Supports the record layer |
| Added `saveResumeData` / `getResumeData` / `clearResumeData` (`.keeresume` files next to the records) | Storage for the bytes iOS hands back when a transfer fails | **New safeguard** |
| `getTempData(user:)` now skips files that are not `.keetmp` and stamps the decoded media with its owner signature | The folder also holds resume data now, and a decoded record needs its signature to resolve its own paths | Supports the record layer |
| `checkFolderExistance(dir:)` is fed `url.path` instead of `url.absoluteString`, in `saveTempData` and `forUser` | `absoluteString` is a `file://` URL, so the check never matched and the directory was recreated on every call | **Pre-existing** (harmless, fixed while nearby) |
| Removed the `print` calls from `saveTempData` | It now runs on every download start, pause and failure | Housekeeping |

### How many downloads run at once

| Change | Why | Origin |
| --- | --- | --- |
| `maxActiveDownloads = 3`: `startDownload` only starts a transfer while fewer than three are running, and writes the record alone for the rest | Nothing capped the number of parallel transfers, in the plugin or on Android. The bandwidth is shared whatever the number is, so running everything at once only means the first media is ready later; three at a time lets the user start watching much sooner, and still keeps a spare slot if one transfer stalls | **Pre-existing** |
| `startNextInQueue()` runs whenever a slot frees: on completion, failure, cancel and pause | The waiting media has to take the slot by itself, without the app asking again | Follows from the cap |
| The queue is served oldest request first, using the record file's creation date | Survives a relaunch, unlike an in-memory order | Follows from the cap |
| A media that just failed, or that the stall watchdog restarted, is pushed back for the length of the current retry delay | Otherwise a link that always fails takes a slot, fails, takes it again, and starves the media that could actually transfer | Follows from the cap |
| `startDownload` refuses to build a task on an invalidated session, or from a manager instance that has been replaced | A cancelled transfer now starts the next one from a delegate callback. If the session was invalidated in between, `URLSession` throws an uncaught exception and the app goes down | **New safeguard** |

A waiting media reaches Flutter through the same record path as any other in-flight download, so
its payload carries the same keys and `status = 0`, exactly like the media iOS was queueing
internally before this change.

### Making the state files survive a kill

Every state file was written in place: the file is truncated first and the new content written
after, so a process killed in between leaves a truncated file. These files are written exactly when
the app is most likely to be killed, right after a download finishes in the background.

| Change | Why | Origin |
| --- | --- | --- |
| All six state files are written with `.atomic` (`dmList.keeImportant`, `serise.keeinfo`, `seasons.keeinfo`, the per-episode `.keeinfo`, `.keetmp`, `.keeresume`) | An atomic write lands in one step, so a kill leaves the previous version untouched instead of a half written file | **Pre-existing** |
| The three index files keep a copy of the last written content next to them (`.bak`), and `decodeStateFile` reads it when the main file cannot be decoded | A damaged `dmList.keeImportant` made `getDMList()` throw for good: every downloaded movie disappeared from the list **and** no new one could ever be registered again, permanently. A damaged `serise.keeinfo` was worse: `addSeries` falls back to an empty list and writes over it, silently erasing every other show the user had downloaded | **Pre-existing** |
| When neither copy can be read, the damaged file is moved aside as `.corrupt` and the library starts from an empty index | Otherwise a user damaged before this version shipped stays blocked forever. Nothing is deleted: the bytes are kept for inspection, and the media files stay on disk | **Pre-existing** |
| `moveDownloadedFile` uses `replaceItemAt` when something already sits at the destination, and the duplicated second move in `saveMovieInfo` is gone | A file left at the destination by an interrupted attempt made the move throw, and the media was then never registered: downloaded, taking space, invisible forever. The second move always failed and only printed an error | **Pre-existing** |
| The four `tempPath` force unwraps in `saveMovieInfo`, `moveEpisodeFile`, `deleteMovieBy` and `deleteEpisode` are guarded | A stored entry without a temporary file traps on delete and takes the app down. The library never writes such an entry, but a legacy or damaged one does exist in the wild, and a test reproduces the crash | **Pre-existing** |

## `ios/Classes/Data Models/DownloadedMedia.swift`

| Change | Why | Origin |
| --- | --- | --- |
| `reCallRequest()` no longer calls `DownloadManager.shared.updateTasks()` | `startDownload` already tracks the task synchronously. The extra asynchronous reload only added churn, and with the old replace-the-list behaviour it could drop the task it had just created | **Pre-existing** |

---

## Example app and test infrastructure

Nothing below ships in the plugin; it only exists so the fix can be proven and kept proven.

| File | Change | Why |
| --- | --- | --- |
| `example/ios/RunnerTests/DownloadManagerTests.swift` | New: 27 tests driving the real `DownloadManager` | Covers the reported regression, relaunch, force quit, interrupted transfer, stalled transfer, error responses, pause, cancel, series grouping, task identity and the response shape |
| `example/ios/RunnerTests/ResponseShapeSnapshotTests.swift` | New: prints every payload the plugin returns | Uses only API that exists before and after the fix, so the shapes can be captured from an older build of the library and compared |
| `example/ios/RunnerTests/LocalHTTPServer.swift` | New: a small HTTP/1.1 server inside the test process | Gives the tests full control of the network: throttling, range requests (needed to verify a resumed transfer), dropping a connection mid-body, and hanging without closing |
| `example/ios/Runner.xcodeproj/project.pbxproj` | Added the `RunnerTests` unit-test bundle hosted by `Runner`, linking `dowplay` | There was no test target in the repository at all |
| `example/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` | `RunnerTests` added to the scheme's test action | So `xcodebuild test -scheme Runner` runs the suite |
| `example/ios/Podfile` (+ `Podfile.lock`) | Added the `RunnerTests` pod target (`inherit! :search_paths`) and `ENABLE_TESTABILITY = YES` for Debug | Required by `@testable import dowplay` |
| `example/ios/Runner/Info.plist` | App Transport Security exception for `127.0.0.1` / `localhost` | The test server is plain HTTP on loopback. Example app only; the plugin and its host apps are unaffected |

---

## What the host app sees

The host app only updates the library; nothing on the Flutter side has to change.

**The response shape is unchanged.** Same methods, same arguments, same dictionaries, same keys.
An in-flight entry carries exactly these keys, whether it comes from a live task or was rebuilt
from its record after a relaunch:

```text
mediaId, mediaType, mediaRetrivalType, name, progress, status, object
                                                     (+ group for an episode)
```

Two tests lock this down and fail on any difference, in either direction:
`testRestoredEntryKeepsTheResponseShape` and `testRestoredEpisodeKeepsTheResponseShape` read the
same media through `getAllMediaDecoded()` while its task is alive, drop the task, read it again
from the record, and compare the two key sets for exact equality.

Behaviour differences, all within that same shape:

* A media now stays in the list until it finishes or is cancelled, including across app relaunches
  and outages. An entry rebuilt from disk carries the last known `progress` until the transfer
  reports again.
* A download that answered with an HTTP error is reported with `status = 1` (paused) instead of
  appearing as a completed media.
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

* 28/28 tests pass on an iPhone 16 simulator (iOS 18.0).
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

* **Android has no limit on concurrent downloads.** `DownloadService.kt` initialises PRDownloader
  with database and timeouts only, so it uses the library's default pool of
  `2 × availableProcessors` threads. Only iOS is capped, at three.
* **The list is not filtered by user.** `getAllMedia` returns every live task, so after a profile
  switch the previous profile's in-flight downloads are still listed. The records on disk are
  already per-user; only the live-task path leaks. Deliberately left for a later change.
* `getAllMedia` reads the records from disk on the calling (main) thread. Fine for the handful of
  downloads a user has, but it is file I/O on the UI thread.
