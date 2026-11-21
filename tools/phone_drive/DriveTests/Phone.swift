import AVFoundation
import XCTest

/// What the runner shares with every test: the plan from the environment, the phone's volume, opening a video.
@MainActor
enum Phone {
    static let official = "tv.danmaku.bilianime"
    static let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    nonisolated static func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// iOS has 16 volume steps; the level is read before muting so it can be put back.
    private static var stepsBefore: Int?

    /// The session's outputVolume only updates while the main run loop turns; Thread.sleep reads a stale level.
    static func volumeSteps(settling seconds: TimeInterval = 0.6) -> Int {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        return Int((AVAudioSession.sharedInstance().outputVolume * 16).rounded())
    }

    static func press(_ button: XCUIDevice.Button, times: Int) {
        for _ in 0..<times {
            XCUIDevice.shared.press(button)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    static func mute() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        let steps = volumeSteps()
        stepsBefore = steps
        print("drive: volume steps before \(steps)")
        press(.volumeDown, times: steps + 1)
    }

    static func restoreVolume() {
        guard let steps = stepsBefore else { return }
        press(.volumeUp, times: steps)
        print("drive: volume steps after \(volumeSteps())")
        stepsBefore = nil
    }

    static func open(_ url: String, in bundle: String) -> XCUIApplication {
        XCUIDevice.shared.system.open(URL(string: url)!)
        for label in ["打开", "Open"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) { button.tap(); break }
        }
        let app = XCUIApplication(bundleIdentifier: bundle)
        _ = app.wait(for: .runningForeground, timeout: 15)
        return app
    }

    static func shot(_ name: String, in test: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    static func text(_ name: String, _ body: String, in test: XCTestCase) {
        let attachment = XCTAttachment(string: body)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
