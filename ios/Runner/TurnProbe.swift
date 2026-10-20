import Flutter
import UIKit

/// What every native turn line carries besides its own fields (docs/reference/turn-log.md).
struct TurnTag: Sendable {
  let turn: Int
  let method: NativeTurnMethod
  let picture: NativeTurnPicture
}

/// The native side of a drawn turn for the phone's log (docs/reference/turn-log.md): what UIKit did, every screen
/// frame's layer angles while the turn runs, sent to Dart as `turn native …` lines.
@MainActor
enum TurnProbe {
  fileprivate static var frames: TurnFrames?

  /// One line for the phone's log, sent from a task so it never runs inside a turn's setup. [fields] hold strings,
  /// ints, doubles and bools only; `wUs` is now unless given.
  static func log(_ kind: String, _ tag: TurnTag, _ fields: [String: any Sendable] = [:], at wUs: Int64? = nil) {
    var line = fields
    line["wUs"] = wUs ?? wallUs()
    line["turn"] = tag.turn
    line["method"] = "\(tag.method)"
    line["picture"] = "\(tag.picture)"
    Task { @MainActor [line] in
      var sent: [String: Any?] = [:]
      for (key, value) in line {
        sent.updateValue(value, forKey: key)
      }
      try? await DeviceChannel.events?.onTurnLog(kind: kind, fields: sent)
    }
  }

  static func wallUs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000_000)
  }

  /// Samples every screen frame for 1.2 s; a sampler still running from the last turn stops and logs first.
  static func startFrames(_ sampler: TurnFrames) {
    endFrames()
    frames = sampler
    sampler.run()
  }

  static func endFrames() {
    frames?.finish()
    frames = nil
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
/// `begin`, kept as numbers and formatted once at the end.
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

  /// Stops sampling and logs the samples, once.
  func finish() {
    guard !done else { return }
    done = true
    link?.invalidate()
    link = nil
    firstTick = nil
    if TurnProbe.frames === self { TurnProbe.frames = nil }
    let samples = self.samples
    let tag = self.tag
    Task { @MainActor in
      TurnProbe.log("frames", tag, ["count": samples.count, "samples": TurnFrames.format(samples)])
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
