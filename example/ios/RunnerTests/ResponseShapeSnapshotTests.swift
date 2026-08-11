//
//  ResponseShapeSnapshotTests.swift
//  RunnerTests
//
//  Prints the exact shape of every payload the plugin hands back to Flutter: the keys, the type of
//  each value, and the values the app branches on. It only uses API that exists both before and
//  after the download fix, so the very same test can be run against either build of the library
//  and the two outputs compared line by line.
//
//  Run it and keep the `SHAPE|` lines:
//    xcodebuild test ... -only-testing:RunnerTests/ResponseShapeSnapshotTests | grep '^SHAPE|'
//

import XCTest
@testable import dowplay

final class ResponseShapeSnapshotTests: XCTestCase {

    private var server: LocalHTTPServer!
    private let user = KeeUser(userID: "9001", profileID: "42", token: "")
    private var settings: HostAppSettings { return HostAppSettings(KeeUser: user, lang: "en") }

    private let movieObject: [String: Any] = ["media_id": "800001", "title": "Snapshot Movie", "media_type": "movie"]
    private let episodeObject: [String: Any] = ["id": 800002, "title": "Snapshot Episode"]

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        server = try LocalHTTPServer(body: Data(repeating: 7, count: 512 * 1024))
        server.configuration = LocalHTTPServer.Configuration(chunkSize: 16 * 1024, chunkDelay: 0.05)
        try server.start()
        try? FileManager.default.removeItem(at: FilesManager.shared.cache)
        DownloadManager.shared.config(useSettings: settings)
        spin(for: 1.5)
    }

    override func tearDownWithError() throws {
        DownloadManager.shared.cancelMedia(withMediaId: "800001", forType: .movie)
        DownloadManager.shared.cancelMedia(withMediaId: "800002", seasonId: "900", showId: "800", forType: .series)
        DownloadManager.shared.tasks.forEach({ $0.cancel() })
        DownloadManager.shared.tasks.removeAll()
        try? FileManager.default.removeItem(at: FilesManager.shared.cache)
        server.stop()
        server = nil
        spin(for: 0.5)
        try super.tearDownWithError()
    }

    func testPrintEveryPayloadShape() {
        // --- a movie that is downloading -------------------------------------------------------
        DownloadManager.shared.startDownload(url: server.url(path: "/800001.mp4"),
                                             forMediaId: 800_001,
                                             mediaName: "Snapshot Movie",
                                             type: .movie,
                                             mediaGroup: nil,
                                             object: movieObject)
        spin(for: 0.5)
        report("get_downloads_list/movie.running", movieEntry())
        report("get_download_movie/running", DownloadManager.shared.getDownloadedMovie("800001")?.getObjectAsJSONDictionary())

        // --- the same movie, paused ------------------------------------------------------------
        DownloadManager.shared.pauseDownload(forMediaId: "800001", ofType: .movie)
        spin(for: 0.5)
        report("get_downloads_list/movie.paused", movieEntry())

        // --- and running again -----------------------------------------------------------------
        DownloadManager.shared.resumeDownload(forMediaId: "800001", ofType: .movie)
        spin(for: 0.5)
        report("get_downloads_list/movie.resumed", movieEntry())

        // --- an episode that is downloading ------------------------------------------------------
        let group = MediaGroup(showId: "800", seasonId: "900", episodeId: "800002",
                               seasonName: "Season 1", showName: "Snapshot Show", data: ["id": 800])
        DownloadManager.shared.startDownload(url: server.url(path: "/800002.mp4"),
                                             forMediaId: 800_002,
                                             mediaName: "Snapshot Episode",
                                             type: .series,
                                             mediaGroup: group,
                                             object: episodeObject)
        spin(for: 0.5)
        report("get_downloads_list/series.row", DownloadManager.shared.getAllMediaDecoded().first(where: { $0["mediaId"] as? String == "800" }))
        report("tvshow_seasons_downloads_list/row", DownloadManager.shared.getAllSeasonsDecoded(forSeries: "800").first)
        report("season_episodes_downloads_list/row", DownloadManager.shared.getAllEpisodesDecoded(forSeason: "900", atSeriesID: "800").first)

        // --- a movie that finished --------------------------------------------------------------
        server.configuration = LocalHTTPServer.Configuration(chunkSize: 512 * 1024, chunkDelay: 0)
        DownloadManager.shared.cancelMedia(withMediaId: "800001", forType: .movie)
        spin(for: 1)
        DownloadManager.shared.startDownload(url: server.url(path: "/800001-done.mp4"),
                                             forMediaId: 800_001,
                                             mediaName: "Snapshot Movie",
                                             type: .movie,
                                             mediaGroup: nil,
                                             object: movieObject)
        let finished = waitUntil(20) { DownloadManager.shared.movieIsDownloaded("800001") }
        print("SHAPE| get_downloads_list/movie.completed reached=\(finished)")
        report("get_downloads_list/movie.completed", movieEntry())
        report("get_download_movie/completed", DownloadManager.shared.getDownloadedMovie("800001")?.getObjectAsJSONDictionary())
    }

    //MARK: - Helpers

    private func movieEntry() -> [String: Any]? {
        return DownloadManager.shared.getAllMediaDecoded().first(where: { $0["mediaId"] as? String == "800001" })
    }

    /// Prints one payload as a stable, diffable line: every key with the type of its value, plus
    /// the values the Flutter side branches on.
    private func report(_ name: String, _ payload: [String: Any]?) {
        guard let payload = payload else {
            print("SHAPE| \(name) -> MISSING (no entry returned)")
            return
        }
        let described = payload.keys.sorted().map({ key in "\(key):\(typeName(of: payload[key]))" }).joined(separator: ", ")
        print("SHAPE| \(name) -> [\(described)]")

        let status = payload["status"].map({ "\($0)" }) ?? "-"
        let retrival = payload["retrivalStatus"].map({ "\($0)" }) ?? "-"
        let progress = payload["progress"].map({ "\($0)" }) ?? "-"
        let mediaType = payload["mediaType"].map({ "\($0)" }) ?? "-"
        let retrivalType = payload["mediaRetrivalType"].map({ "\($0)" }) ?? "-"
        print("SHAPE| \(name) -> status=\(status) retrivalStatus=\(retrival) progress=\(progress) mediaType=\(mediaType) mediaRetrivalType=\(retrivalType)")

        if let object = payload["object"] as? [String: Any] {
            print("SHAPE| \(name) -> object keys=\(object.keys.sorted())")
        }
        if let group = payload["group"] as? [String: Any] {
            print("SHAPE| \(name) -> group keys=\(group.keys.sorted())")
        }
    }

    private func typeName(of value: Any?) -> String {
        switch value {
        case is String: return "String"
        case is Bool: return "Bool"
        case is Int: return "Int"
        case is Double: return "Double"
        case is [String: Any]: return "Map"
        case is [Any]: return "List"
        case is NSNull, .none: return "Null"
        default: return "\(type(of: value!))"
        }
    }

    @discardableResult
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }

    private func spin(for seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
