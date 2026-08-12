//
//  VideoPlayerSeekTests.swift
//  RunnerTests
//
//  Drives the real player against a real video file and checks the one thing the user sees when
//  scrubbing: the slider must stay where it was dropped while the player is still on its way there.
//

import XCTest
import AVFoundation
@testable import dowplay

final class VideoPlayerSeekTests: XCTestCase {

    private var player: VideoPlayerViewController!
    private var videoURL: URL!
    private var window: UIWindow!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        videoURL = try makeVideoFile()
        player = VideoPlayerViewController(nibName: "VideoPlayerViewController", bundle: .packageBundle)

        let media = Media(title: "Seek sample", urlToPlay: videoURL.absoluteString)
        player.setMediaList(mediaList: [media], startingIndex: 0, playOnStart: true)

        // The player only loads its item once it is on screen, and a real window is also what
        // makes the snapshots below show what a user would see.
        window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = player
        window.makeKeyAndVisible()

        XCTAssertTrue(waitUntil("the video to be ready") { self.player.seekTimeSlider.isEnabled },
                      "the player never became ready, the rest of the test would be meaningless")
    }

    override func tearDownWithError() throws {
        window.isHidden = true
        window = nil
        player = nil
        try? FileManager.default.removeItem(at: videoURL)
        try super.tearDownWithError()
    }

    /// Releasing the slider used to hand the labels straight back to the periodic time observer,
    /// which paints `currentTime()` - still the position being left while the seek buffers - so the
    /// thumb jumped back and only reached the requested point once the data had arrived.
    func testSliderStaysWhereItWasDroppedWhileTheSeekIsRunning() {
        let target: Float = 0.75

        player.sliderDown(nil)
        player.seekTimeSlider.value = target
        player.seekActionUpIn(player.seekTimeSlider, forEvent: UIEvent())

        // Exactly what the periodic observer does, half a second after the finger is lifted, while
        // the player is still buffering the new position.
        player.playerDidUpdateTime(time: .zero)

        XCTAssertEqual(player.seekTimeSlider.value, target, accuracy: 0.01,
                       "the slider jumped away from the position the user asked for")
    }

    /// And once the player gets there, it owns the slider again.
    func testSliderFollowsThePlayerAgainOnceTheSeekLands() {
        let target: Float = 0.5

        player.sliderDown(nil)
        player.seekTimeSlider.value = target
        player.seekActionUpIn(player.seekTimeSlider, forEvent: UIEvent())

        XCTAssertTrue(waitUntil("the seek to land") {
            self.player.playerDidUpdateTime(time: .zero)
            return abs(self.player.seekTimeSlider.value - target) < 0.05
                && self.player.seekTimeSlider.value != target
        }, "the slider never picked the player's own position back up")
    }

    /// Plays over a throttled connection, the way a phone does, and photographs the screen every
    /// 300ms after the finger is lifted. The images land in the app container so they can be looked
    /// at afterwards: the thumb has to stay where it was dropped in every one of them.
    func testScreenshotsOfTheSeekOverASlowConnection() throws {
        let video = try Data(contentsOf: videoURL)
        let server = try LocalHTTPServer(body: video)
        server.configuration = LocalHTTPServer.Configuration(chunkSize: 16 * 1024, chunkDelay: 0.05)
        try server.start()
        defer { server.stop() }

        let streamed = VideoPlayerViewController(nibName: "VideoPlayerViewController", bundle: .packageBundle)
        streamed.setMediaList(mediaList: [Media(title: "Streamed sample", urlToPlay: server.url().absoluteString)],
                              startingIndex: 0, playOnStart: true)
        window.rootViewController = streamed
        XCTAssertTrue(waitUntil("the streamed video to be ready", timeout: 30) { streamed.seekTimeSlider.isEnabled })

        // Bring the controls up so the thumb itself is in the pictures.
        streamed.topOnPlayer(UITapGestureRecognizer())
        streamed.controllersStayTime = 60

        let target: Float = 0.8
        streamed.sliderDown(nil)
        streamed.seekTimeSlider.value = target
        streamed.seekActionUpIn(streamed.seekTimeSlider, forEvent: UIEvent())

        var shots: [String] = []
        for step in 0..<6 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            streamed.playerDidUpdateTime(time: .zero)   // the periodic observer, firing mid seek
            let name = "seek-\(step)-thumb-at-\(String(format: "%.3f", streamed.seekTimeSlider.value)).png"
            saveScreenshot(of: window, named: name)
            shots.append(name)
            // It may move forward once the player lands and playback carries on, but it must never
            // be seen before the point the user dropped it on.
            XCTAssertGreaterThanOrEqual(streamed.seekTimeSlider.value, target - 0.02,
                                        "the thumb jumped back, \(0.3 * Double(step + 1))s after the release")
        }
        print("SEEK-SHOTS| \(shots.joined(separator: " "))")
    }

    //MARK: - Helpers

    private func saveScreenshot(of window: UIWindow, named name: String) {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { return }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SeekShots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent(name))
    }

    /// A short video written to disk. A file keeps the test deterministic: the assertion above runs
    /// before the seek can complete, whatever the machine does.
    private func makeVideoFile() throws -> URL {
        let bundled = Bundle(for: VideoPlayerSeekTests.self).url(forResource: "seek-sample", withExtension: "mp4")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("seek-sample-\(UUID().uuidString).mp4")
        guard let bundled = bundled else {
            throw XCTSkip("seek-sample.mp4 is missing from the test bundle")
        }
        try FileManager.default.copyItem(at: bundled, to: destination)
        return destination
    }

    @discardableResult
    private func waitUntil(_ description: String, timeout: TimeInterval = 20, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("Timed out waiting for \(description)")
        return false
    }
}
