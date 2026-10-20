import Flutter
import UIKit

/// What every native turn line carries besides its own fields (docs/reference/turn-log.md).
struct TurnTag: Sendable {
  let turn: Int
  let method: NativeTurnMethod
  let picture: NativeTurnPicture
  /// A turn iOS animates itself (takeover off), logged as method `system`.
  var system = false
}

/// The native side of a drawn turn for the phone's log (docs/reference/turn-log.md): what UIKit did, every screen
/// frame's layer angles while the turn runs, sent to Dart as `turn native …` lines.
@MainActor
enum TurnProbe {
  fileprivate static var frames: TurnFrames?
  private static var lastBegin: CFTimeInterval = 0
  private static let quiet: CFTimeInterval = 0.3

  /// Sends to Dart that failed since the last line that got through, carried by the next line as `lost`.
  private static var lost = 0
  private static var failureLogged = false

  /// One line for the phone's log, sent from a task so it never runs inside a turn's setup. `fields` hold strings,
  /// ints, doubles and bools only; `wUs` is now unless given.
  static func log(_ kind: String, _ tag: TurnTag, _ fields: [String: any Sendable] = [:], at wUs: Int64? = nil) {
    var line = fields
    line["wUs"] = wUs ?? wallUs()
    line["turn"] = tag.turn
    line["method"] = tag.system ? "system" : "\(tag.method)"
    line["picture"] = tag.system ? "none" : "\(tag.picture)"
    Task { @MainActor [line] in
      guard let events = DeviceChannel.events else { return }
      var sent: [String: Any?] = [:]
      for (key, value) in line {
        sent.updateValue(value, forKey: key)
      }
      // Taken as the line goes, so a count rides on one line only; a line that fails hands it back.
      let carried = lost
      lost = 0
      if carried > 0 { sent.updateValue(carried, forKey: "lost") }
      do {
        try await events.onTurnLog(kind: kind, fields: sent)
      } catch {
        lost += carried
        failed("onTurnLog", error)
      }
    }
  }

  /// A turn event for Dart, sent from a task; a failure counts towards the next line's `lost`.
  static func send(_ name: String, _ call: @escaping @MainActor () async throws -> Void) {
    Task { @MainActor in
      do {
        try await call()
      } catch {
        failed(name, error)
      }
    }
  }

  private static func failed(_ name: String, _ error: any Error) {
    lost += 1
    guard !failureLogged else { return }
    failureLogged = true
    NSLog("TurnProbe: %@ failed: %@", name, String(describing: error))
  }

  static func wallUs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000_000)
  }

  /// Samples every screen frame for 1.2 s; a sampler still running from the last turn stops first.
  static func startFrames(_ sampler: TurnFrames) {
    endFrames()
    lastBegin = CACurrentMediaTime()
    frames = sampler
    sampler.run()
  }

  static func endFrames() {
    frames?.finish()
    frames = nil
  }

  /// Runs `write` once no turn has begun for 300 ms: formatting a sampler's line takes a few milliseconds of this
  /// thread, which Dart's UI shares, so it stays out of a turn's start.
  fileprivate static func whenQuiet(_ write: @escaping @MainActor () -> Void) {
    Task { @MainActor in
      var left = quiet - (CACurrentMediaTime() - lastBegin)
      while left > 0 {
        try? await Task.sleep(for: .seconds(left))
        left = quiet - (CACurrentMediaTime() - lastBegin)
      }
      write()
    }
  }

  /// Degrees, positive clockwise on screen.
  static func degrees(_ transform: CATransform3D) -> Double {
    atan2(Double(transform.m12), Double(transform.m11)) * 180 / .pi
  }

  /// `layer|keyPath|class|duration|timing|additive|beginOffsetMs` for each animation on `layer`. The offset is from
  /// now, negative for one already running; timing is the curve's control points, or a spring's mass, stiffness and
  /// damping.
  static func animations(on layer: CALayer, named name: String) -> [String] {
    let now = layer.convertTime(CACurrentMediaTime(), from: nil)
    var lines: [String] = []
    for key in layer.animationKeys() ?? [] {
      guard let animation = layer.animation(forKey: key) else { continue }
      let property = animation as? CAPropertyAnimation
      let offset = animation.beginTime == 0 ? 0 : (animation.beginTime - now) * 1000
      let parts: [String] = [
        name,
        packed(property?.keyPath ?? key),
        packed(String(describing: type(of: animation))),
        number(animation.duration, 3),
        timing(of: animation),
        (property?.isAdditive ?? false) ? "true" : "false",
        number(offset, 1),
      ]
      lines.append(parts.joined(separator: "|"))
    }
    return lines
  }

  static func name(_ orientation: UIInterfaceOrientation) -> String {
    switch orientation {
    case .portrait: return "portrait"
    case .portraitUpsideDown: return "portraitUpsideDown"
    case .landscapeLeft: return "landscapeLeft"
    case .landscapeRight: return "landscapeRight"
    default: return "unknown"
    }
  }

  static func number(_ value: Double, _ digits: Int) -> String {
    String(format: "%.\(digits)f", value)
  }

  private static func timing(of animation: CAAnimation) -> String {
    if let spring = animation as? CASpringAnimation {
      let parts = [spring.mass, spring.stiffness, spring.damping].map { number(Double($0), 2) }
      return "spring " + parts.joined(separator: " ")
    }
    guard let function = animation.timingFunction else { return "" }
    var first: [Float] = [0, 0]
    var second: [Float] = [0, 0]
    function.getControlPoint(at: 1, values: &first)
    function.getControlPoint(at: 2, values: &second)
    return [first[0], first[1], second[0], second[1]].map { number(Double($0), 3) }.joined(separator: " ")
  }

  /// Keeps the packed separators out of a name.
  private static func packed(_ text: String) -> String {
    String(text.map { "|;,".contains($0) ? "_" : $0 })
  }
}

/// One turn's `frames` line: the presentation layers' angles and sizes at every display-link tick for 1.2 s from
/// `begin`, kept as numbers until the line is written.
@MainActor
final class TurnFrames: NSObject {
  private struct Sample {
    let tMs: Double
    let gapMs: Double
    let scene: Double
    let window: Double
    let windowW: Double
    let windowH: Double
    let container: Double?
    let root: Double?
    let picture: Double?
    let pictureOpacity: Double?
  }

  private static let span: CFTimeInterval = 1.2

  /// Runs on the first tick, before its sample is read.
  var firstTick: (@MainActor () -> Void)?

  private let tag: TurnTag
  private let start: CFTimeInterval
  private var last: CFTimeInterval
  private weak var window: UIWindow?
  private weak var root: UIView?
  private weak var container: UIView?
  private weak var picture: UIView?
  private var link: CADisplayLink?
  private var samples: [Sample] = []
  private var done = false

  /// `start` is begin's CACurrentMediaTime.
  init(tag: TurnTag, start: CFTimeInterval, window: UIWindow?, root: UIView?, container: UIView?, picture: UIView?) {
    self.tag = tag
    self.start = start
    last = start
    self.window = window
    self.root = root
    self.container = container
    self.picture = picture
    super.init()
  }

  func run() {
    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
    // Ticks stop while the app is off screen; the line still goes out.
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(1500))
      self?.finish()
    }
  }

  /// Stops sampling, once; the line goes out when the turns are quiet, stamped with the time sampling stopped.
  func finish() {
    guard !done else { return }
    done = true
    link?.invalidate()
    link = nil
    firstTick = nil
    if TurnProbe.frames === self { TurnProbe.frames = nil }
    let samples = self.samples
    self.samples = []
    let tag = self.tag
    let ended = TurnProbe.wallUs()
    TurnProbe.whenQuiet {
      TurnProbe.log("frames", tag, ["count": samples.count, "samples": TurnFrames.format(samples)], at: ended)
    }
  }

  @objc private func tick(_ link: CADisplayLink) {
    if let first = firstTick {
      firstTick = nil
      first()
    }
    let now = CACurrentMediaTime()
    samples.append(sample(at: now))
    last = now
    if now - start >= TurnFrames.span { finish() }
  }

  /// The first tick's gap is from begin.
  private func sample(at now: CFTimeInterval) -> Sample {
    var scene = 0.0
    var windowAngle = 0.0
    var windowSize = CGSize.zero
    if let window {
      let shown = TurnFrames.shown(window.layer)
      windowAngle = TurnProbe.degrees(shown.transform) + TurnProbe.degrees(shown.sublayerTransform)
      windowSize = shown.bounds.size
      var above = window.layer.superlayer
      while let layer = above {
        let shownAbove = TurnFrames.shown(layer)
        scene += TurnProbe.degrees(shownAbove.transform) + TurnProbe.degrees(shownAbove.sublayerTransform)
        above = layer.superlayer
      }
    }
    var containerAngle: Double?
    if let container, container.superview != nil {
      let shown = TurnFrames.shown(container.layer)
      containerAngle = TurnProbe.degrees(shown.transform) + TurnProbe.degrees(shown.sublayerTransform)
    }
    var rootAngle: Double?
    if let root {
      rootAngle = TurnProbe.degrees(TurnFrames.shown(root.layer).transform)
    }
    var pictureAngle: Double?
    var pictureOpacity: Double?
    if let picture, picture.superview != nil {
      let shown = TurnFrames.shown(picture.layer)
      pictureAngle = TurnProbe.degrees(shown.transform)
      pictureOpacity = Double(shown.opacity)
    }
    return Sample(
      tMs: (now - start) * 1000, gapMs: (now - last) * 1000, scene: scene, window: windowAngle,
      windowW: Double(windowSize.width), windowH: Double(windowSize.height), container: containerAngle,
      root: rootAngle, picture: pictureAngle, pictureOpacity: pictureOpacity)
  }

  private static func shown(_ layer: CALayer) -> CALayer {
    layer.presentation() ?? layer
  }

  /// `tMs,gapMs,scene,window,windowW,windowH,container,root,picture,pictureOpacity` per tick, `;`-separated.
  private static func format(_ samples: [Sample]) -> String {
    var ticks: [String] = []
    ticks.reserveCapacity(samples.count)
    for sample in samples {
      let parts: [String] = [
        TurnProbe.number(sample.tMs, 1),
        TurnProbe.number(sample.gapMs, 1),
        TurnProbe.number(sample.scene, 2),
        TurnProbe.number(sample.window, 2),
        TurnProbe.number(sample.windowW, 1),
        TurnProbe.number(sample.windowH, 1),
        optional(sample.container, 2),
        optional(sample.root, 2),
        optional(sample.picture, 2),
        optional(sample.pictureOpacity, 3),
      ]
      ticks.append(parts.joined(separator: ","))
    }
    return ticks.joined(separator: ";")
  }

  private static func optional(_ value: Double?, _ digits: Int) -> String {
    guard let value else { return "" }
    return TurnProbe.number(value, digits)
  }
}
