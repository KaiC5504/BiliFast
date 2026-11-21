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

    static func mute() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        let steps = Int((session.outputVolume * 16).rounded())
        stepsBefore = steps
        print("drive: volume steps before \(steps)")
        for _ in 0..<max(steps, 1) + 1 { XCUIDevice.shared.press(.volumeDown) }
    }

    static func restoreVolume() {
        guard let steps = stepsBefore else { return }
        for _ in 0..<steps { XCUIDevice.shared.press(.volumeUp) }
        print("drive: volume steps after \(Int((AVAudioSession.sharedInstance().outputVolume * 16).rounded()))")
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
