import CoreImage
import Vision
import XCTest

/// Measures how far a horizontal drag on the player seeks: each drag's start and end position are read off the
/// player's own time text ("01:20/03:31") by text recognition, with the video paused.
final class Measure: XCTestCase {
    struct Time { let position: Double; let duration: Double }

    struct Drag {
        let startX: CGFloat
        let dx: CGFloat
        let velocity: CGFloat
        let hold: TimeInterval
    }

    /// Portrait: the player is 440 wide; landscape full screen 956. Starts stay clear of the edges.
    static let portraitDrags: [Drag] = [40, 80, 160, 320].flatMap { dx in
        [150, 1200].map { Drag(startX: 60, dx: dx, velocity: $0, hold: 0.3) }
    } + [Drag(startX: 200, dx: 160, velocity: 300, hold: 0.3), Drag(startX: 60, dx: 160, velocity: 1200, hold: 0)]

    static let landscapeDrags: [Drag] = [80, 160, 320, 640].flatMap { dx in
        [150, 1200].map { Drag(startX: 120, dx: dx, velocity: $0, hold: 0.3) }
    } + [Drag(startX: 400, dx: 320, velocity: 300, hold: 0.3), Drag(startX: 120, dx: 320, velocity: 1200, hold: 0)]

    /// The portrait page's player, from the official app's accessibility tree.
    static let portraitPlayer = CGRect(x: 0, y: 62, width: 440, height: 247.7)
    /// Its full-screen button, from a screenshot of the shown controls.
    static let fullScreenButton = CGPoint(x: 417, y: 287)

    /// DRIVE_APP=bilifast measures ours, opened through 搜索 (it has no URL scheme); otherwise the official app.
    let ours = Phone.env("DRIVE_APP") == "bilifast"
    var app: XCUIApplication!
    /// The first reading after opening sets it; any later reading of a different length is a misread.
    var expectedDuration: Double?
    var shotTaken = false
    var rows: [String] = []

    @MainActor
    func testDrags() throws {
        let videos = (Phone.env("DRIVE_VIDEOS") ?? "BV1bXsh6vE1m").split(separator: ",").map(String.init)
        let modes = (Phone.env("DRIVE_MODES") ?? "portrait,landscape").split(separator: ",").map(String.init)
        Phone.mute()
        defer {
            Phone.restoreVolume()
            Phone.text("rows", rows.joined(separator: "\n"), in: self)
        }
        for video in videos {
            for mode in modes {
                try measure(video: video, landscape: mode == "landscape")
            }
        }
    }

    @MainActor
    private func measure(video: String, landscape: Bool) throws {
        expectedDuration = nil
        app = ours ? try openOurs(video) : openOfficial(video)
        guard let first = try waitForTime(timeout: 25) else {
            print("drive: \(video) no time readable after opening")
            return
        }
        expectedDuration = first.duration
        print("drive: \(video) opened at \(first.position) of \(first.duration)")
        try pause()
        if landscape {
            _ = try readTime()
            tap(Self.fullScreenButton)
            Thread.sleep(forTimeInterval: 1.5)
            let frame = mainWindow.frame
            print("drive: full screen window \(frame.width)x\(frame.height)")
            guard frame.width > frame.height else {
                print("drive: \(video) did not turn to landscape; skipped")
                return
            }
        }
        let frame = mainWindow.frame
        let y = landscape ? frame.height / 2 : Self.portraitPlayer.midY
        let mode = landscape ? "landscape" : "portrait"
        let width = landscape ? frame.width : Self.portraitPlayer.width
        for drag in (landscape ? Self.landscapeDrags : Self.portraitDrags).prefix(Int(Phone.env("DRIVE_LIMIT") ?? "99") ?? 99) {
            for direction in [1.0, -1.0] as [CGFloat] {
                let from = direction > 0 ? drag.startX : drag.startX + drag.dx
                guard let before = try readTime() else {
                    print("drive: unreadable before drag")
                    if Phone.env("DRIVE_DEBUG") != nil, app.state == .runningForeground, !shotTaken {
                        shotTaken = true
                        Phone.shot("unreadable", in: self)
                    }
                    continue
                }
                coordinate(CGPoint(x: from, y: y)).press(
                    forDuration: 0.05,
                    thenDragTo: coordinate(CGPoint(x: from + direction * drag.dx, y: y)),
                    withVelocity: XCUIGestureVelocity(drag.velocity),
                    thenHoldForDuration: drag.hold
                )
                Thread.sleep(forTimeInterval: 0.8)
                guard let after = try readTime() else { print("drive: unreadable after drag"); continue }
                let row = [
                    ours ? "bilifast" : "official", video, fmt(expectedDuration ?? before.duration), mode, fmt(width),
                    fmt(from), fmt(direction * drag.dx), fmt(drag.velocity), fmt(drag.hold),
                    fmt(before.position), fmt(after.position), fmt(after.position - before.position),
                ].joined(separator: ",")
                rows.append(row)
                print("drive: row \(row)")
            }
        }
    }

    @MainActor
    private func openOfficial(_ video: String) -> XCUIApplication {
        XCUIApplication(bundleIdentifier: Phone.official).terminate()
        return Phone.open("bilibili://video/\(video)", in: Phone.official)
    }

    /// A bare BV id typed into 搜索 and submitted opens its video page.
    @MainActor
    private func openOurs(_ video: String) throws -> XCUIApplication {
        let ours = XCUIApplication(bundleIdentifier: "com.kaichuan.bilifast")
        ours.terminate()
        ours.activate()
        let search = ours.descendants(matching: .any).matching(identifier: "搜索").firstMatch
        guard search.waitForExistence(timeout: 15) else { throw XCTSkip("BiliFast's 搜索 not found") }
        search.tap()
        Thread.sleep(forTimeInterval: 1)
        ours.typeText(video + "\n")
        return ours
    }

    // MARK: - Reading the time

    @MainActor
    private func waitForTime(timeout: TimeInterval) throws -> Time? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let time = try readTime() { return time }
            Thread.sleep(forTimeInterval: 1)
        }
        return nil
    }

    /// Reads the time text, tapping the player to show its controls when they are hidden.
    @MainActor
    private func readTime() throws -> Time? {
        if let time = try recognise() { return time }
        for _ in 0..<4 {
            tap(center)
            Thread.sleep(forTimeInterval: 0.6)
            if let time = try recognise() { return time }
        }
        return nil
    }

    /// Paused when two readings 1.5 s apart agree; a double tap toggles play.
    @MainActor
    private func pause() throws {
        for _ in 0..<4 {
            guard let a = try readTime() else { continue }
            Thread.sleep(forTimeInterval: 1.5)
            guard let b = try readTime() else { continue }
            if a.position == b.position {
                print("drive: paused at \(b.position)")
                return
            }
            coordinate(center).doubleTap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        print("drive: could not confirm pause")
    }

    /// Each reading makes full-size images; without a pool per reading they pile up until iOS ends the runner.
    @MainActor
    private func recognise() throws -> Time? {
        try autoreleasepool { try recogniseOnce() }
    }

    @MainActor
    private func recogniseOnce() throws -> Time? {
        // Never look at the screen unless the official app is the one on it.
        guard app.state == .runningForeground else {
            throw XCTSkip("the official app left the screen (phone in use?); stopped")
        }
        guard let shot = XCUIScreen.main.screenshot().image.cgImage else { return nil }
        // The screenshot stays portrait-shaped while the app is in landscape, so its text reads sideways there.
        let sideways = mainWindow.frame.width > mainWindow.frame.height
        var seen: [String] = []
        for orientation in sideways ? [CGImagePropertyOrientation.right, .left] : [.up] {
            guard let image = Self.render(CIImage(cgImage: shot).oriented(orientation)) else { continue }
            for observation in Self.recognise(image) {
                let text = observation.topCandidates(1).first?.string ?? ""
                guard text.contains("/") else { continue }
                // Read the time again from just its box, enlarged: small text loses digits at screen size.
                var candidates = Self.recognise(Self.enlarge(observation.boundingBox, of: image))
                    .compactMap { $0.topCandidates(1).first?.string }
                candidates.append(text)
                for candidate in candidates {
                    if let time = Self.parse(candidate), accepts(time) { return time }
                    seen.append(candidate)
                }
            }
        }
        if Phone.env("DRIVE_DEBUG") != nil { print("drive: debug unparsed \(seen.prefix(8))") }
        return nil
    }

    private func accepts(_ time: Time) -> Bool {
        guard let expected = expectedDuration else { return true }
        // A dropped leading digit of the duration (03:31 read as 0:31) still leaves its seconds.
        let durationAgrees = abs(expected - time.duration) < 1.5 || Int(expected) % 60 == Int(time.duration) % 60
        return durationAgrees && time.position <= expected
    }

    private static let context = CIContext()

    static func render(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }

    static func recognise(_ image: CGImage?) -> [VNRecognizedTextObservation] {
        guard let image else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return request.results ?? []
    }

    /// The observation's box with some margin, cut from the image and scaled up three times.
    static func enlarge(_ box: CGRect, of image: CGImage) -> CGImage? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        var rect = CGRect(x: box.minX * width, y: (1 - box.maxY) * height, width: box.width * width, height: box.height * height)
        rect = rect.insetBy(dx: -rect.height, dy: -rect.height * 0.6).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard let crop = image.cropping(to: rect.integral) else { return nil }
        return render(CIImage(cgImage: crop).transformed(by: CGAffineTransform(scaleX: 3, y: 3)))
    }

    static func parse(_ text: String) -> Time? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let pattern = try! NSRegularExpression(pattern: #"(\d{1,2}(?::\d{2}){1,2})/(\d{1,2}(?::\d{2}){1,2})"#)
        let range = NSRange(compact.startIndex..., in: compact)
        guard let match = pattern.firstMatch(in: compact, range: range),
              let a = Range(match.range(at: 1), in: compact), let b = Range(match.range(at: 2), in: compact)
        else { return nil }
        guard let position = seconds(String(compact[a])), let duration = seconds(String(compact[b])), duration > 0 else {
            return nil
        }
        return Time(position: position, duration: duration)
    }

    static func seconds(_ clock: String) -> Double? {
        let parts = clock.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    // MARK: - Touches

    /// The app itself, not one of its windows: the official app keeps an empty one first, and windows come and go
    /// (the keyboard's), which fails a lookup made while listing them.
    @MainActor
    private var mainWindow: XCUIElement { app }

    @MainActor
    private var center: CGPoint {
        let frame = mainWindow.frame
        return frame.width > frame.height
            ? CGPoint(x: frame.width / 2, y: frame.height / 2)
            : CGPoint(x: Self.portraitPlayer.midX, y: Self.portraitPlayer.midY)
    }

    @MainActor
    private func coordinate(_ point: CGPoint) -> XCUICoordinate {
        mainWindow.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    @MainActor
    private func tap(_ point: CGPoint) {
        coordinate(point).tap()
    }

    private func fmt(_ value: Double) -> String { String(format: "%g", value) }
    private func fmt(_ value: CGFloat) -> String { String(format: "%g", Double(value)) }
}
