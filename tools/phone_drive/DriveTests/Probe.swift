import AVFoundation
import XCTest

final class Probe: XCTestCase {
    @MainActor
    func testReach() {
        let device = XCUIDevice.shared
        let size = XCUIScreen.main.screenshot().image.size
        print("drive: reached \(UIDevice.current.model) \(UIDevice.current.systemVersion), screen \(Int(size.width))x\(Int(size.height)), orientation \(device.orientation.rawValue)")
    }

    /// Puts the volume back to DRIVE_VOLUME steps (of 16) after a run that died while muted.
    @MainActor
    func testSetVolume() {
        let target = Int(Phone.env("DRIVE_VOLUME") ?? "") ?? 6
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        // The buttons move the media volume only while media is playing or just paused; otherwise the ringer.
        let app = Phone.open("bilibili://video/BV1bXsh6vE1m", in: Phone.official)
        Thread.sleep(forTimeInterval: 5)
        let window = app.windows.allElementsBoundByIndex.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        window?.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 220, dy: 186)).doubleTap()
        Thread.sleep(forTimeInterval: 1)
        let now = Phone.volumeSteps()
        Phone.press(target > now ? .volumeUp : .volumeDown, times: abs(target - now))
        print("drive: volume steps \(now) -> \(Phone.volumeSteps())")
    }
}
