//
//  DownloadManagerTests.swift
//  RunnerTests
//
//  End to end tests for the download list: they drive the real DownloadManager against a local
//  HTTP server and check the invariant the app depends on, which is that a media stays visible
//  and restartable until it is either finished or explicitly cancelled, no matter what happens
//  in between (re-configuration, app relaunch, interrupted transfer).
//

import XCTest
import Network
@testable import dowplay

final class DownloadManagerTests: XCTestCase {

    private static let bodySize = 2 * 1024 * 1024

    private var server: LocalHTTPServer!
    private let expectedBody = Data((0..<DownloadManagerTests.bodySize).map { UInt8($0 % 251) })

    private let user = KeeUser(userID: "9001", profileID: "42", token: "")
    private let signature = "9001_42"
    private var settings: HostAppSettings {
        return HostAppSettings(KeeUser: user, lang: "en")
    }

    private var fastServer: LocalHTTPServer.Configuration {
        return LocalHTTPServer.Configuration(chunkSize: 256 * 1024, chunkDelay: 0, dropAfterBytes: nil)
    }

    private var slowServer: LocalHTTPServer.Configuration {
        return LocalHTTPServer.Configuration(chunkSize: 16 * 1024, chunkDelay: 0.05, dropAfterBytes: nil)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        server = try LocalHTTPServer(body: expectedBody)
        server.configuration = slowServer
        try server.start()
        resetDownloadState()
    }

    override func tearDownWithError() throws {
        resetDownloadState()
        server.stop()
        server = nil
        try super.tearDownWithError()
    }

    //MARK: - The reported regression

    func testRunningDownloadIsListedRightAfterItStarts() {
        configureManager()
        startMovieDownload(id: 700_001, name: "Movie A")

        XCTAssertTrue(listContains(mediaId: "700001"), "a started download must show up in the list")
        XCTAssertEqual(tasks(forMediaId: "700001").count, 1)
    }

    /// The host app calls config_downloader on every start and every resume. Re-configuring used
    /// to replace the in memory task list with the (empty) list of the background session, so the
    /// running download kept downloading but vanished from the app.
    func testRunningDownloadSurvivesReconfiguration() {
        configureManager()
        startMovieDownload(id: 700_002, name: "Movie B")

        configureManager()

        XCTAssertTrue(listContains(mediaId: "700002"), "the running download disappeared from the list")
        XCTAssertEqual(tasks(forMediaId: "700002").count, 1, "the download must not be duplicated")
        XCTAssertEqual(server.requests.filter({ $0.contains("/700002.mp4") }).count, 1,
                       "the media is being transferred twice")
    }

    func testRunningDownloadSurvivesAppRelaunch() {
        configureManager()
        startMovieDownload(id: 700_003, name: "Movie C")

        relaunchApp()

        XCTAssertTrue(listContains(mediaId: "700003"), "the download was lost when the app was relaunched")
        XCTAssertEqual(tasks(forMediaId: "700003").count, 1, "the download must not be duplicated")
    }

    /// Reproduces a force quit: the record on disk is the only thing left, and it has to bring
    /// the media back and restart the transfer.
    func testDownloadIsRestoredFromDiskWhenNoTaskSurvived() {
        configureManager()
        let taskId = startMovieDownload(id: 700_004, name: "Movie D")

        // Kill the live task behind the manager's back, the way a force quit does.
        DownloadManager.shared.tasks.forEach({ $0.cancel() })
        DownloadManager.shared.tasks.removeAll()
        XCTAssertTrue(FilesManager.shared.hasTempData(id: taskId, user: signature),
                      "an in flight download must have a record on disk")

        configureManager()

        XCTAssertTrue(listContains(mediaId: "700004"), "the download was not restored from its record")
        XCTAssertTrue(waitUntil("the restored download to run again") {
            DownloadManager.shared.isDownloadingMediaWithID("700004", ofType: .movie)
        })
    }

    //MARK: - Completion

    func testDownloadCompletesAndIsStored() {
        server.configuration = fastServer
        configureManager()
        let taskId = startMovieDownload(id: 700_005, name: "Movie E")

        XCTAssertTrue(waitUntil("the movie to be stored") {
            DownloadManager.shared.movieIsDownloaded("700005")
        })

        let stored = DownloadManager.shared.getDownloadedMovie("700005")
        XCTAssertNotNil(stored)
        XCTAssertEqual(try? Data(contentsOf: stored!.path), expectedBody, "the stored file is not the file that was served")
        XCTAssertFalse(FilesManager.shared.hasTempData(id: taskId, user: signature),
                       "a finished download must not keep its in flight record")
        XCTAssertTrue(waitUntil("the finished task to leave the list") {
            !DownloadManager.shared.isDownloadingMediaWithID("700005", ofType: .movie)
        })
    }

    /// The transfer is cut in the middle, exactly like losing connectivity. The media must stay in
    /// the list the whole time, pick itself up once the network is back without the app being
    /// reopened, and end up complete and byte identical.
    func testInterruptedDownloadStaysListedAndFinishesIntact() {
        server.configuration = LocalHTTPServer.Configuration(chunkSize: 16 * 1024,
                                                             chunkDelay: 0.02,
                                                             dropAfterBytes: 512 * 1024)
        configureManager()
        startMovieDownload(id: 700_006, name: "Movie F")

        XCTAssertTrue(waitUntil("the transfer to be cut") { self.server.requests.count >= 1 })
        // Give the failure time to travel through the delegate before checking the list.
        spin(for: 3)
        XCTAssertTrue(listContains(mediaId: "700006"), "an interrupted download must stay in the list")

        // Connectivity is back, and nothing else happens: no relaunch, no re-configuration.
        server.configuration = fastServer

        XCTAssertTrue(waitUntil("the interrupted movie to be stored", timeout: 90) {
            DownloadManager.shared.movieIsDownloaded("700006")
        })
        let stored = DownloadManager.shared.getDownloadedMovie("700006")
        XCTAssertEqual(try? Data(contentsOf: stored!.path), expectedBody,
                       "the file recovered after the interruption is corrupted")
        XCTAssertFalse(server.rangeRequests.isEmpty, "the transfer restarted from zero instead of resuming")
    }

    /// iOS can leave a transfer waiting forever after the connection silently died, without ever
    /// reporting an error, which is what leaves a download stuck at the same percentage.
    func testStalledTransferIsRestartedOnItsOwn() {
        DownloadManager.stallCheckInterval = 2
        defer { DownloadManager.stallCheckInterval = 30 }

        server.configuration = LocalHTTPServer.Configuration(chunkSize: 16 * 1024,
                                                             chunkDelay: 0.02,
                                                             hangAfterBytes: 256 * 1024)
        configureManager()
        startMovieDownload(id: 700_013, name: "Movie M")

        XCTAssertTrue(waitUntil("the transfer to stall") { self.server.requests.count >= 1 })
        spin(for: 3)
        XCTAssertTrue(listContains(mediaId: "700013"), "a stalled download must stay in the list")

        // The connection is healthy again for the next attempt.
        server.configuration = fastServer

        XCTAssertTrue(waitUntil("the stalled movie to be stored", timeout: 90) {
            DownloadManager.shared.movieIsDownloaded("700013")
        })
        let stored = DownloadManager.shared.getDownloadedMovie("700013")
        XCTAssertEqual(try? Data(contentsOf: stored!.path), expectedBody,
                       "the file recovered after the stall is corrupted")
    }

    /// An expired or refused link answers with an error page. Storing it would give the user a
    /// media that looks downloaded and does not play.
    func testErrorResponseIsNotStoredAsMedia() {
        server.configuration = LocalHTTPServer.Configuration(errorStatus: 403)
        configureManager()
        startMovieDownload(id: 700_012, name: "Movie L")

        XCTAssertTrue(waitUntil("the server to answer") { self.server.requests.count >= 1 })
        spin(for: 3)

        XCTAssertFalse(DownloadManager.shared.movieIsDownloaded("700012"), "an error page was stored as the media")
        XCTAssertTrue(listContains(mediaId: "700012"), "the failed media must stay in the list")
    }

    /// iOS can relaunch the app in the background to hand over a finished transfer, long before
    /// Flutter calls config_downloader. The file has to be filed under the right user anyway,
    /// otherwise it is downloaded but never shows up.
    func testTransferFinishedBeforeConfigurationIsStillStored() {
        server.configuration = slowServer
        configureManager()
        startMovieDownload(id: 700_007, name: "Movie G")

        // The session and its delegate are alive, the configuration is not there yet.
        DownloadManager.shared.forgetConfiguration()
        FilesManager.shared.setUser("")

        let storedFile = FilesManager.shared.cache
            .appendingPathComponent("movies")
            .appendingPathComponent(signature)
            .appendingPathComponent("700007.mp4")
        XCTAssertTrue(waitUntil("the file to be stored under its owner", timeout: 90) {
            FileManager.default.fileExists(atPath: storedFile.path)
        })

        configureManager()
        XCTAssertTrue(DownloadManager.shared.movieIsDownloaded("700007"))
        XCTAssertEqual(try? Data(contentsOf: storedFile), expectedBody)
    }

    //MARK: - Pause / cancel

    func testPausedDownloadStaysPausedAcrossRelaunch() {
        configureManager()
        startMovieDownload(id: 700_008, name: "Movie H")
        DownloadManager.shared.pauseDownload(forMediaId: "700008", ofType: .movie)
        XCTAssertTrue(DownloadManager.shared.isDownloadingMediaWithIDSuspended("700008", ofType: .movie))

        relaunchApp()

        XCTAssertTrue(listContains(mediaId: "700008"), "a paused download must stay in the list")
        XCTAssertTrue(DownloadManager.shared.isDownloadingMediaWithIDSuspended("700008", ofType: .movie),
                      "a paused download must not restart on its own")
    }

    func testCancelledDownloadDoesNotComeBack() {
        configureManager()
        let taskId = startMovieDownload(id: 700_009, name: "Movie I")

        DownloadManager.shared.cancelMedia(withMediaId: "700009", forType: .movie)

        XCTAssertFalse(listContains(mediaId: "700009"))
        XCTAssertFalse(FilesManager.shared.hasTempData(id: taskId, user: signature))

        relaunchApp()

        XCTAssertFalse(listContains(mediaId: "700009"), "a cancelled download came back after the relaunch")
        XCTAssertFalse(DownloadManager.shared.isDownloadingMediaWithID("700009", ofType: .movie))
    }

    //MARK: - Series

    func testEpisodeStaysGroupedUnderItsSeasonAfterRelaunch() {
        configureManager()
        let group = MediaGroup(showId: "500", seasonId: "600", episodeId: "700010",
                               seasonName: "Season 1", showName: "A Show", data: ["id": 500])
        DownloadManager.shared.startDownload(url: server.url(path: "/episode.mp4"),
                                             forMediaId: 700_010,
                                             mediaName: "Episode 1",
                                             type: .series,
                                             mediaGroup: group,
                                             object: ["id": 700_010, "title": "Episode 1"])

        relaunchApp()

        let shows = DownloadManager.shared.getAllMediaDecoded()
        XCTAssertTrue(shows.contains(where: { $0["mediaId"] as? String == "500" }),
                      "the downloading episode must appear under its show")

        let seasons = DownloadManager.shared.getAllSeasonsDecoded(forSeries: "500")
        XCTAssertTrue(seasons.contains(where: { $0["mediaId"] as? String == "600" }),
                      "the downloading episode must appear under its season")

        let episodes = DownloadManager.shared.getAllEpisodesDecoded(forSeason: "600", atSeriesID: "500")
        XCTAssertTrue(episodes.contains(where: { $0["mediaId"] as? String == "700010" }),
                      "the episode disappeared from its season")
    }

    //MARK: - Response shape

    /// The host app only updates the library, so nothing it reads may disappear from the payload.
    /// An entry rebuilt from its record must carry every key the live task entry carried.
    func testRestoredEntryKeepsTheResponseShape() {
        configureManager()
        startMovieDownload(id: 700_014, name: "Movie N")

        guard let fromTask = entry(forMediaId: "700014") else {
            return XCTFail("the running download is missing from the list")
        }

        // Drop the live task the way a force quit does, so the entry can only come from the record.
        DownloadManager.shared.tasks.forEach({ $0.cancel() })
        DownloadManager.shared.tasks.removeAll()

        guard let fromRecord = entry(forMediaId: "700014") else {
            return XCTFail("the restored download is missing from the list")
        }

        print("keys from the live task : \(Set(fromTask.keys).sorted())")
        print("keys from the record    : \(Set(fromRecord.keys).sorted())")

        XCTAssertEqual(Set(fromRecord.keys), Set(fromTask.keys),
                       "the payload changed shape: \(Set(fromRecord.keys).symmetricDifference(Set(fromTask.keys)))")
        XCTAssertEqual(fromRecord["mediaId"] as? String, "700014")
        XCTAssertEqual(fromRecord["mediaType"] as? String, fromTask["mediaType"] as? String)
        XCTAssertEqual(fromRecord["name"] as? String, fromTask["name"] as? String)
        XCTAssertEqual(fromRecord["mediaRetrivalType"] as? String, fromTask["mediaRetrivalType"] as? String)
        XCTAssertNotNil(fromRecord["progress"] as? Double)
        XCTAssertNotNil(fromRecord["status"] as? Int)
        XCTAssertEqual((fromRecord["object"] as? [String: Any])?["title"] as? String, "Movie N",
                       "the media payload the app reads must survive the restore")
    }

    /// get_download_movie answers from the record too once the task is gone, and the app reads
    /// that payload the same way it reads a list entry.
    func testRestoredMovieLookupKeepsTheResponseShape() {
        configureManager()
        startMovieDownload(id: 700_016, name: "Movie O")

        guard let fromTask = DownloadManager.shared.getDownloadedMovie("700016")?.getObjectAsJSONDictionary() else {
            return XCTFail("the running download is not returned by get_download_movie")
        }

        DownloadManager.shared.tasks.forEach({ $0.cancel() })
        DownloadManager.shared.tasks.removeAll()

        guard let fromRecord = DownloadManager.shared.getDownloadedMovie("700016")?.getObjectAsJSONDictionary() else {
            return XCTFail("get_download_movie lost the download once its task was gone")
        }

        print("get_download_movie keys from the live task : \(Set(fromTask.keys).sorted())")
        print("get_download_movie keys from the record    : \(Set(fromRecord.keys).sorted())")

        XCTAssertEqual(Set(fromRecord.keys), Set(fromTask.keys),
                       "the payload changed shape: \(Set(fromRecord.keys).symmetricDifference(Set(fromTask.keys)))")
        XCTAssertEqual((fromRecord["object"] as? [String: Any])?["title"] as? String, "Movie O")
        XCTAssertNotNil(fromRecord["status"] as? Int)
    }

    /// Same guarantee for an episode, whose entry also carries the group the app groups by.
    func testRestoredEpisodeKeepsTheResponseShape() {
        configureManager()
        let group = MediaGroup(showId: "800", seasonId: "900", episodeId: "700015",
                               seasonName: "Season 2", showName: "Another Show", data: ["id": 800])
        DownloadManager.shared.startDownload(url: server.url(path: "/700015.mp4"),
                                             forMediaId: 700_015,
                                             mediaName: "Episode 5",
                                             type: .series,
                                             mediaGroup: group,
                                             object: ["id": 700_015, "title": "Episode 5"])

        let fromTask = DownloadManager.shared.getAllEpisodesDecoded(forSeason: "900", atSeriesID: "800")
            .first(where: { $0["mediaId"] as? String == "700015" })
        XCTAssertNotNil(fromTask)

        DownloadManager.shared.tasks.forEach({ $0.cancel() })
        DownloadManager.shared.tasks.removeAll()

        let fromRecord = DownloadManager.shared.getAllEpisodesDecoded(forSeason: "900", atSeriesID: "800")
            .first(where: { $0["mediaId"] as? String == "700015" })
        guard let fromTask = fromTask, let fromRecord = fromRecord else {
            return XCTFail("the restored episode is missing from its season")
        }

        print("episode keys from the live task : \(Set(fromTask.keys).sorted())")
        print("episode keys from the record    : \(Set(fromRecord.keys).sorted())")

        XCTAssertEqual(Set(fromRecord.keys), Set(fromTask.keys),
                       "the payload changed shape: \(Set(fromRecord.keys).symmetricDifference(Set(fromTask.keys)))")
        XCTAssertEqual((fromRecord["group"] as? [String: Any])?["seasonId"] as? String, "900")
        XCTAssertEqual((fromRecord["object"] as? [String: Any])?["title"] as? String, "Episode 5")
    }

    //MARK: - How many run at once

    /// The bandwidth is shared whatever the number is, so only a few transfer at a time and the
    /// rest wait their turn. Everything the user asked for stays in the list from the first tap.
    func testOnlyThreeDownloadsTransferAtOnce() {
        configureManager()
        let requested = (700_030...700_035).map({ id -> String in
            startMovieDownload(id: id, name: "Movie \(id)")
            return "\(id)"
        })
        spin(for: 2)

        XCTAssertEqual(DownloadManager.shared.tasks.filter({ $0.state == .running }).count,
                       DownloadManager.maxActiveDownloads,
                       "more transfers are running than the limit allows")
        XCTAssertEqual(server.requests.count, DownloadManager.maxActiveDownloads,
                       "the server was asked for more media than the limit allows")

        for mediaId in requested {
            XCTAssertTrue(listContains(mediaId: mediaId), "\(mediaId) is missing from the list")
        }
    }

    /// A media that is waiting reaches Flutter exactly like a media that is transferring.
    func testWaitingDownloadKeepsTheResponseShape() {
        configureManager()
        (700_036...700_039).forEach({ startMovieDownload(id: $0, name: "Movie \($0)") })
        spin(for: 1)

        guard let running = entry(forMediaId: "700036"), let waiting = entry(forMediaId: "700039") else {
            return XCTFail("the list is missing one of the downloads")
        }
        XCTAssertEqual(Set(waiting.keys), Set(running.keys),
                       "the payload changed shape: \(Set(waiting.keys).symmetricDifference(Set(running.keys)))")
        XCTAssertEqual(waiting["status"] as? Int, 0, "a media waiting its turn is still a download in progress")
        XCTAssertEqual((waiting["object"] as? [String: Any])?["title"] as? String, "Movie 700039")
    }

    func testWaitingDownloadStartsWhenARunningOneFinishes() {
        server.configuration = fastServer
        configureManager()
        (700_040...700_043).forEach({ startMovieDownload(id: $0, name: "Movie \($0)") })

        XCTAssertTrue(waitUntil("every requested movie to be stored", timeout: 60) {
            (700_040...700_043).allSatisfy({ DownloadManager.shared.movieIsDownloaded("\($0)") })
        })
    }

    func testCancellingARunningDownloadStartsTheNextInLine() {
        configureManager()
        (700_044...700_047).forEach({ startMovieDownload(id: $0, name: "Movie \($0)") })
        spin(for: 1)
        XCTAssertFalse(DownloadManager.shared.isDownloadingMediaWithID("700047", ofType: .movie),
                       "the fourth media should be waiting, not running")

        DownloadManager.shared.cancelMedia(withMediaId: "700044", forType: .movie)

        XCTAssertTrue(waitUntil("the waiting media to take the free slot") {
            DownloadManager.shared.isDownloadingMediaWithID("700047", ofType: .movie)
        })
        XCTAssertEqual(DownloadManager.shared.tasks.filter({ $0.state == .running }).count,
                       DownloadManager.maxActiveDownloads)
    }

    func testTheLimitStillHoldsAfterARelaunch() {
        configureManager()
        (700_048...700_053).forEach({ startMovieDownload(id: $0, name: "Movie \($0)") })
        spin(for: 1)

        relaunchApp()

        XCTAssertLessThanOrEqual(DownloadManager.shared.tasks.filter({ $0.state == .running }).count,
                                 DownloadManager.maxActiveDownloads,
                                 "the relaunch started more transfers than the limit allows")
        for id in 700_048...700_053 {
            XCTAssertTrue(listContains(mediaId: "\(id)"), "\(id) was lost across the relaunch")
        }
    }

    //MARK: - Damaged state files

    /// The state files used to be written in place, so a process killed halfway through left a
    /// truncated file behind. A damaged movie index used to block every future registration for
    /// good; it must now be read from the copy kept next to it.
    func testDamagedMovieIndexIsReadFromItsBackup() {
        server.configuration = fastServer
        configureManager()
        startMovieDownload(id: 700_017, name: "Movie P")
        XCTAssertTrue(waitUntil("the first movie to be stored") {
            DownloadManager.shared.movieIsDownloaded("700017")
        })

        let index = FilesManager.shared.cache
            .appendingPathComponent("movies").appendingPathComponent(signature)
            .appendingPathComponent("dmList.keeImportant")
        XCTAssertTrue(FileManager.default.fileExists(atPath: index.appendingPathExtension("bak").path),
                      "a backup of the index must be kept")

        // The app was killed while the index was being rewritten.
        try? Data("{\"700017\": {\"mediaId\": ".utf8).write(to: index)

        startMovieDownload(id: 700_018, name: "Movie Q")
        XCTAssertTrue(waitUntil("the second movie to be stored") {
            DownloadManager.shared.movieIsDownloaded("700018")
        })
        XCTAssertTrue(DownloadManager.shared.movieIsDownloaded("700017"),
                      "the movie downloaded before the damage was lost")
    }

    /// When neither the index nor its backup can be read, the user must not stay blocked: the
    /// damaged file is kept aside and the library starts from an empty index.
    func testUnreadableMovieIndexStartsFreshAndKeepsTheDamagedFile() {
        server.configuration = fastServer
        configureManager()
        startMovieDownload(id: 700_023, name: "Movie T")
        XCTAssertTrue(waitUntil("the first movie to be stored") {
            DownloadManager.shared.movieIsDownloaded("700023")
        })

        // Both copies are damaged, which is the state of a user hit before this version shipped.
        let index = FilesManager.shared.cache
            .appendingPathComponent("movies").appendingPathComponent(signature)
            .appendingPathComponent("dmList.keeImportant")
        let damaged = Data("{\"700023\": {\"medi".utf8)
        try? damaged.write(to: index)
        try? damaged.write(to: index.appendingPathExtension("bak"))

        startMovieDownload(id: 700_024, name: "Movie U")
        XCTAssertTrue(waitUntil("downloads to work again") {
            DownloadManager.shared.movieIsDownloaded("700024")
        })

        let kept = index.appendingPathExtension("corrupt")
        XCTAssertEqual(try? Data(contentsOf: kept), damaged,
                       "the damaged index must be kept instead of being overwritten")
    }

    /// A damaged series index used to be silently replaced by a list holding only the newest show,
    /// which erased every other show the user had downloaded.
    func testDamagedSeriesIndexDoesNotEraseTheOtherShows() {
        server.configuration = fastServer
        configureManager()
        downloadEpisode(id: 700_019, showId: "810", seasonId: "910", name: "Episode of show A")
        // Wait for the episode to be on disk, not merely in flight: the assertions below read the
        // persisted index, which is what the damage hits.
        XCTAssertTrue(waitUntil("the first episode to be stored") {
            DownloadManager.shared.episodeIsDownloaded("700019", season: "910", serise: "810")
        })
        XCTAssertFalse(FilesManager.shared.getSeasons(forSeriseID: "810").isEmpty)

        let index = FilesManager.shared.cache
            .appendingPathComponent("series").appendingPathComponent(signature)
            .appendingPathComponent("serise.keeinfo")
        try? Data("[{\"id\": \"810\", \"na".utf8).write(to: index)

        downloadEpisode(id: 700_020, showId: "820", seasonId: "920", name: "Episode of show B")
        XCTAssertTrue(waitUntil("the second episode to be stored") {
            DownloadManager.shared.episodeIsDownloaded("700020", season: "920", serise: "820")
        })

        XCTAssertFalse(FilesManager.shared.getSeasons(forSeriseID: "810").isEmpty,
                       "the show downloaded before the damage was erased from the index")
    }

    /// A file left at the destination by an interrupted attempt used to make the move fail, and
    /// the media was then never registered: on disk but invisible, for good.
    func testDownloadReplacesAnOrphanFileLeftAtItsDestination() {
        server.configuration = fastServer
        configureManager()

        let destination = FilesManager.shared.cache
            .appendingPathComponent("movies").appendingPathComponent(signature)
            .appendingPathComponent("700021.mp4")
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data("leftover from an interrupted attempt".utf8).write(to: destination)

        startMovieDownload(id: 700_021, name: "Movie R")

        XCTAssertTrue(waitUntil("the movie to be stored over the orphan file") {
            DownloadManager.shared.movieIsDownloaded("700021")
        })
        XCTAssertEqual(try? Data(contentsOf: destination), expectedBody,
                       "the orphan file was kept instead of the download")
    }

    /// Deleting a media whose stored record has no temporary file used to trap on a force unwrap.
    func testDeletingAMediaWithoutATemporaryFileDoesNotCrash() {
        configureManager()
        let index = FilesManager.shared.cache
            .appendingPathComponent("movies").appendingPathComponent(signature)
            .appendingPathComponent("dmList.keeImportant")
        try? FileManager.default.createDirectory(at: index.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // tempPath is absent, the way an entry written by an older build could be.
        let entry = """
        {"700022": {"mediaId": "700022", "name": "Movie S", "mediaType": "movie", \
        "mediaRetrivalType": "MovieInfo", "progress": 1}}
        """
        try? Data(entry.utf8).write(to: index)

        DownloadManager.shared.cancelMedia(withMediaId: "700022", forType: .movie)

        XCTAssertFalse(DownloadManager.shared.movieIsDownloaded("700022"))
    }

    //MARK: - Task identity

    /// Task identifiers are only unique inside one session and are reused across launches, so the
    /// identity must come from the task itself and never from a leftover UserDefaults entry.
    func testMediaIdentityIsReadFromTheTaskAndNotFromAStaleEntry() {
        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: server.url())
        let staleKey = "task_id_\(task.taskIdentifier)"
        UserDefaults.standard.set("111_movies_1_1", forKey: staleKey)

        task.setMediaIdentity(mediaId: "700011_movies_9001_42", mediaName: "Movie K")

        XCTAssertEqual(task.mediaId, "700011_movies_9001_42")
        XCTAssertEqual(task.mediaName, "Movie K")
        XCTAssertEqual(task.mediaSignature, "9001_42")
        XCTAssertEqual(task.mediaType, .movie)

        UserDefaults.standard.removeObject(forKey: staleKey)
        task.cancel()
        session.invalidateAndCancel()
    }

    func testMediaIdentityFallsBackToTheLegacyEntryForOldTasks() {
        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: server.url())
        let legacyKey = "task_id_\(task.taskIdentifier)"
        UserDefaults.standard.set("700012_series_9001_42", forKey: legacyKey)

        XCTAssertEqual(task.mediaId, "700012_series_9001_42", "downloads started by an older build must still be recognised")
        XCTAssertEqual(task.mediaType, .series)

        UserDefaults.standard.removeObject(forKey: legacyKey)
        task.cancel()
        session.invalidateAndCancel()
    }

    //MARK: - Helpers

    @discardableResult
    private func startMovieDownload(id: Int, name: String) -> String {
        DownloadManager.shared.startDownload(url: server.url(path: "/\(id).mp4"),
                                             forMediaId: id,
                                             mediaName: name,
                                             type: .movie,
                                             mediaGroup: nil,
                                             object: ["media_id": "\(id)", "title": name])
        return "\(id)_movies_\(signature)"
    }

    /// Configures the manager and waits for the reload + restore pass it triggers. A relaunched
    /// manager reloads its tasks on its own too, so the pending pass is drained first and only a
    /// reload that starts after `config` is waited on.
    @discardableResult
    private func downloadEpisode(id: Int, showId: String, seasonId: String, name: String) -> String {
        let group = MediaGroup(showId: showId, seasonId: seasonId, episodeId: "\(id)",
                               seasonName: "Season of \(showId)", showName: "Show \(showId)",
                               data: ["id": showId])
        DownloadManager.shared.startDownload(url: server.url(path: "/\(id).mp4"),
                                             forMediaId: id,
                                             mediaName: name,
                                             type: .series,
                                             mediaGroup: group,
                                             object: ["id": id, "title": name])
        return "\(id)_series_\(signature)"
    }

    private func configureManager() {
        var reloads = 0
        DownloadManager.shared.didLoadPreListedTasks = { reloads += 1 }
        spin(for: 0.3)
        let baseline = reloads

        DownloadManager.shared.config(useSettings: settings)
        waitUntil("the manager to reload its tasks") { reloads > baseline }

        DownloadManager.shared.didLoadPreListedTasks = nil
        spin(for: 0.3)
    }

    private func relaunchApp() {
        relaunchAppWithoutConfiguring()
        configureManager()
    }

    private func relaunchAppWithoutConfiguring() {
        var relaunched = false
        DownloadManager.simulateAppRelaunch { relaunched = true }
        waitUntil("the app to relaunch") { relaunched }
        // A freshly launched process has no user yet either.
        FilesManager.shared.setUser("")
        spin(for: 0.5)
    }

    private func tasks(forMediaId mediaId: String) -> [URLSessionTask] {
        return DownloadManager.shared.tasks.filter({ $0.mediaId?.hasPrefix("\(mediaId)_") == true })
    }

    private func entry(forMediaId mediaId: String) -> [String: Any]? {
        return DownloadManager.shared.getAllMediaDecoded().first(where: { $0["mediaId"] as? String == mediaId })
    }

    private func listContains(mediaId: String) -> Bool {
        return DownloadManager.shared.getAllMediaDecoded().contains(where: { $0["mediaId"] as? String == mediaId })
    }

    @discardableResult
    private func waitUntil(_ description: String, timeout: TimeInterval = 30, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("Timed out waiting for \(description)")
        return false
    }

    private func spin(for seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func resetDownloadState() {
        configureManager()
        DownloadManager.shared.cancelAll()
        try? FileManager.default.removeItem(at: FilesManager.shared.cache)
        spin(for: 0.2)
    }
}
