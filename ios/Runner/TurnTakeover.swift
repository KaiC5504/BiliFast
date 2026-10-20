import Flutter
import UIKit

/// The video page's turns drawn by Flutter instead of the scene (lib/video/video_page.dart): Flutter gets the turned
/// size at once instead of halfway through, so the page can turn while the player grows past the upright page's
/// sides, as the official app's does.
///
/// The window turns under a still picture of the screen, turned back so it stays physically where it was; Flutter is
/// told (`onTurn`) and draws the turn, and the picture goes on its first frame or after a timeout. iOS still animates
/// the window's own rotation, so `method` is how that is kept out of the turn (NativeTurnMethod in
/// pigeons/device_api.dart); the test build carries every one, and TurnProbe logs each turn.
@MainActor
enum TurnTakeover {
  /// Set from Dart's 开发者 → 旋转动画 (DeviceHostApi.setTurnTakeover); the method and picture in force when a turn
  /// begins are that turn's.
  private(set) static var enabled = false
  private(set) static var method: NativeTurnMethod = .legacy
  private(set) static var picture: NativeTurnPicture = .cut

  /// The last turn's id.
  private static var turn = 0
  /// The latest turn: what one turn left to run later acts only while it is still this one.
  private static var current: TurnState?
  /// For a turnDrawn that arrives after a newer turn began.
  private static var recent: [Int: TurnState] = [:]

  /// UIView.areAnimationsEnabled as found before the turns held it off, to put back; nil while not holding.
  private static var heldAnimations: Bool?
  /// Only the latest turn or request to hold them puts them back.
  private static var holdOwner: HoldOwner?
  private static var requestHolds = 0

  /// The counter method's view between the window and the Flutter view, from its first turn until the takeover is
  /// off or another method is chosen.
  private static var container: UIView?
  private static weak var containerRoot: UIView?
  private static var rootMask: UIView.AutoresizingMask = []

  private static let fallback = Duration.milliseconds(500)
  private static let requestHoldLimit = Duration.seconds(1)
  private static let fadeSeconds = 0.12
  private static let fadeKey = "fade"

  private enum HoldOwner: Equatable {
    case turn(Int)
    case request(Int)
  }

  static func configure(enabled: Bool, method: NativeTurnMethod, picture: NativeTurnPicture) {
    self.enabled = enabled
    self.method = method
    self.picture = picture
    guard !enabled || method != .counter else { return }
    // A counter turn still running takes its container down when it settles.
    if let state = current, state.tag.method == .counter, !state.settled { return }
    uninstallContainer()
  }

  /// Before DeviceChannel asks the scene to turn. For quietRequest, animations are off from here until the turn that
  /// follows completes (or for a second when none comes), so the request is made without animation.
  static func requesting(_ request: Int64, mask: NativeOrientationMask, from interface: UIInterfaceOrientation) {
    guard enabled else { return }
    TurnProbe.log("request", tag(for: turn), [
      "request": Int(request), "mask": "\(mask)", "interface": TurnProbe.name(interface),
      "animationsEnabled": UIView.areAnimationsEnabled,
    ])
    guard method == .quietRequest else { return }
    requestHolds += 1
    let hold = HoldOwner.request(requestHolds)
    holdAnimations(owner: hold)
    Task { @MainActor in
      try? await Task.sleep(for: requestHoldLimit)
      releaseAnimations(owner: hold)
    }
  }

  static func requestReturned(_ request: Int64, ms: Double) {
    guard enabled else { return }
    TurnProbe.log("request returned", tag(for: turn), ["request": Int(request), "ms": ms])
  }

  /// Flutter drew turn `id`'s first frame; its still picture goes, cut or faded as that turn's picture says.
  static func drawn(turn id: Int) {
    guard let state = current, state.tag.turn == id else {
      let earlier = recent[id]
      let earlierTag = earlier?.tag ?? tag(for: id)
      let pictured = earlier?.pictured ?? (earlierTag.picture != .none)
      TurnProbe.log("drawn", earlierTag, ["action": pictured ? "gone" : "none"])
      return
    }
    state.drawn = true
    guard let still = state.still else {
      TurnProbe.log("drawn", state.tag, ["action": state.pictured ? "gone" : "none"])
      return
    }
    state.still = nil
    TurnProbe.log("drawn", state.tag, ["action": state.tag.picture == .fade ? "fade" : "cut"])
    takeAway(still, state.tag, why: "drawn")
  }

  /// Before the turn moves anything; returns the turn's id. `angle` is the target transform's rotation in radians,
  /// positive clockwise on screen (UIKit's y-down space, the same sense as Flutter's Transform.rotate): once the
  /// window has turned, content drawn at -angle sits where it was, so Dart starts there and animates to 0.
  static func begin(root: UIView, from: CGSize, to size: CGSize, angle: Double,
                    coordinator: any UIViewControllerTransitionCoordinator) -> Int {
    let startUs = TurnProbe.wallUs()
    let startMedia = CACurrentMediaTime()
    let animationsWere = UIView.areAnimationsEnabled
    let window = root.window
    let method = self.method
    let shows: NativeTurnPicture = method == .noSpin ? .none : picture
    TurnProbe.endFrames()

    // Taken first, so a picture still up from the last turn is in it, as it is on screen.
    let snapping = CACurrentMediaTime()
    let still = shows == .none ? nil : window?.snapshotView(afterScreenUpdates: false)
    let snapshotMs = still == nil ? 0 : (CACurrentMediaTime() - snapping) * 1000
    var replaced: TurnTag?
    if let last = current, let shown = last.still {
      last.still = nil
      shown.removeFromSuperview()
      replaced = last.tag
    }

    turn += 1
    let id = turn
    let tag = TurnTag(turn: id, method: method, picture: shows)
    let state = TurnState(tag: tag, window: window, root: root, pictured: still != nil)
    current = state
    recent[id] = state
    recent = recent.filter { $0.key > id - 8 }

    var containerEvents: [String] = []
    if method == .counter {
      if let window { containerEvents = counterTurn(in: window, root: root, to: size, angle: angle) }
    } else {
      uninstallContainer()
    }
    let turning = method == .counter ? container : nil

    if let window, let still {
      still.isUserInteractionEnabled = false
      still.bounds = CGRect(origin: .zero, size: window.bounds.size)
      still.center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
      window.addSubview(still)
      state.still = still
    }

    switch method {
    case .counter, .noSpin:
      releaseAnimations(owner: nil)
    case .legacy, .remove, .noActions, .quietRequest:
      holdAnimations(owner: .turn(id))
    }

    // Turned back inside the transition, as the window takes its new bounds; should the system still animate, the
    // two turns cancel and the picture holds still all the same. The counter container takes the same path.
    let queued = coordinator.animate(alongsideTransition: { _ in
      if let still { turnBack(still, to: size, angle: angle) }
      if let turning { straighten(turning, to: size) }
      TurnProbe.log("alongside", tag)
    }, completion: { context in
      TurnProbe.log("completion", tag, ["cancelled": context.isCancelled])
      releaseAnimations(owner: .turn(id))
      settle(state)
    })
    if !queued {
      if let still { turnBack(still, to: size, angle: angle) }
      if let turning { straighten(turning, to: size) }
      releaseAnimations(owner: .turn(id))
    }

    // Ahead of the begin and container lines, so Dart starts drawing first.
    let seconds = coordinator.transitionDuration
    TurnProbe.send("onTurn") {
      try await DeviceChannel.events?.onTurn(turn: Int64(id), angle: angle, seconds: seconds)
    }

    let frames = TurnFrames(tag: tag, start: startMedia, window: window, root: root, container: turning,
                            picture: state.still)
    if method == .remove {
      frames.firstTick = { removeSystemAnimations(state, phase: "next tick") }
    }
    TurnProbe.startFrames(frames)

    Task { @MainActor in
      try? await Task.sleep(for: fallback)
      fellBack(state)
    }

    TurnProbe.log("begin", tag, [
      "angle": angle, "seconds": seconds, "animated": coordinator.isAnimated,
      "fromW": Double(from.width), "fromH": Double(from.height),
      "toW": Double(size.width), "toH": Double(size.height),
      "animationsEnabled": animationsWere, "snapshot": state.pictured, "snapshotMs": snapshotMs,
    ], at: startUs)
    for event in containerEvents {
      TurnProbe.log("container", tag, ["event": event])
    }
    if let replaced { pictureGone(replaced, why: "replaced") }
    if !state.pictured { sendPictureGone(id) }
    return id
  }

  /// After FlutterViewController's viewWillTransition: the remove method's first pass, queued because UIKit adds
  /// its rotation animations after viewWillTransition returns.
  static func afterSuper(_ id: Int) {
    guard let state = current, state.tag.turn == id, state.tag.method == .remove else { return }
    DispatchQueue.main.async {
      MainActor.assumeIsolated { removeSystemAnimations(state, phase: "after super") }
    }
  }

  private static func tag(for id: Int) -> TurnTag {
    TurnTag(turn: id, method: method, picture: method == .noSpin ? .none : picture)
  }

  private static func turnBack(_ still: UIView, to size: CGSize, angle: Double) {
    still.transform = CGAffineTransform(rotationAngle: CGFloat(-angle))
    still.center = CGPoint(x: size.width / 2, y: size.height / 2)
  }

  /// The remove method: the animations on the window, the layers above it and the Flutter view go, so the window
  /// stands turned at once; the picture then drops its turn-back too and sits at -angle, where it was.
  private static func removeSystemAnimations(_ state: TurnState, phase: String) {
    guard state === current, let window = state.window else { return }
    var layers: [(name: String, layer: CALayer)] = [("window", window.layer)]
    var above = window.layer.superlayer
    while let layer = above {
      layers.append(("window^\(layers.count)", layer))
      above = layer.superlayer
    }
    if let root = state.root { layers.append(("root", root.layer)) }
    var found: [String] = []
    var removed = 0
    for entry in layers {
      found += TurnProbe.animations(on: entry.layer, named: entry.name)
      removed += entry.layer.animationKeys()?.count ?? 0
      entry.layer.removeAllAnimations()
    }
    if let still = state.still {
      found += TurnProbe.animations(on: still.layer, named: "picture")
      if removed > 0 {
        for key in still.layer.animationKeys() ?? [] where key != fadeKey {
          still.layer.removeAnimation(forKey: key)
          removed += 1
        }
      }
    }
    TurnProbe.log("animations", state.tag, ["phase": phase, "found": found.joined(separator: ";"), "removed": removed])
  }

  /// The counter method: the Flutter view's container laid out at the new size and turned by +angle, around where
  /// the window's centre is now. The alongside block takes it to 0 at the new centre, the same path as the picture's
  /// turn-back, so it cancels the window's turn from -angle whatever iOS animates. A turn that reverses one under way
  /// adds the angle the container is shown at, which is the inverse of what is left of the window's last turn, so the
  /// content doesn't jump. Returns the container events.
  private static func counterTurn(in window: UIWindow, root: UIView, to size: CGSize, angle: Double) -> [String] {
    var events: [String] = []
    if let held = container, held.superview !== window { uninstallContainer() }
    if let held = container, root.superview !== held {
      events.append("lost")
      UIView.performWithoutAnimation { place(root, in: held) }
      events.append("restored")
    }
    if container == nil, root.superview === window {
      let made = TurnContainer(frame: window.bounds)
      made.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      rootMask = root.autoresizingMask
      UIView.performWithoutAnimation {
        window.insertSubview(made, belowSubview: root)
        place(root, in: made)
      }
      container = made
      containerRoot = root
      events.append("installed")
    }
    guard let container else { return events }
    // The container's own rather than the window's: iOS may turn a layer above the window, whose model may already
    // hold the new turn.
    let presented = container.layer.presentation() ?? container.layer
    let shown = presented.transform
    let left = atan2(Double(shown.m12), Double(shown.m11))
    // Mid-turn the model already holds the last turn's end; removing its animations would jump the centre there.
    let centre = presented.position
    if abs(left) > 0.001 { events.append("reversed") }
    UIView.performWithoutAnimation {
      container.layer.removeAllAnimations()
      // Sized by hand until the turn settles: the window's own resize would add its change on top.
      container.autoresizingMask = []
      container.bounds = CGRect(origin: .zero, size: size)
      container.center = centre
      container.transform = CGAffineTransform(rotationAngle: CGFloat(angle + left))
      root.frame = container.bounds
    }
    return events
  }

  /// Only the container is ever turned, so the Flutter view's frame always means what UIKit expects.
  private static func place(_ root: UIView, in container: UIView) {
    container.addSubview(root)
    root.frame = container.bounds
    root.autoresizingMask = [.flexibleWidth, .flexibleHeight]
  }

  private static func straighten(_ container: UIView, to size: CGSize) {
    container.bounds = CGRect(origin: .zero, size: size)
    container.center = CGPoint(x: size.width / 2, y: size.height / 2)
    container.transform = .identity
  }

  /// The latest turn is over (completion or fallback): the counter container follows the window again, or goes if
  /// the takeover was switched off or another method chosen meanwhile.
  private static func settle(_ state: TurnState) {
    guard state === current, !state.settled else { return }
    state.settled = true
    guard let container else { return }
    guard enabled, method == .counter else {
      uninstallContainer()
      return
    }
    UIView.performWithoutAnimation {
      container.transform = .identity
      if let window = container.superview {
        container.bounds = CGRect(origin: .zero, size: window.bounds.size)
        container.center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
      }
      container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
  }

  /// The Flutter view back in the window, laid out as UIKit had it.
  private static func uninstallContainer() {
    guard let held = container else { return }
    container = nil
    UIView.performWithoutAnimation {
      if let root = containerRoot, root.superview === held, let window = held.superview {
        window.insertSubview(root, aboveSubview: held)
        root.frame = window.bounds
        root.autoresizingMask = rootMask
      }
      held.removeFromSuperview()
    }
    containerRoot = nil
  }

  private static func fellBack(_ state: TurnState) {
    guard state === current else { return }
    releaseAnimations(owner: .turn(state.tag.turn))
    settle(state)
    if !state.drawn { TurnProbe.log("fallback", state.tag) }
    guard let still = state.still else { return }
    state.still = nil
    takeAway(still, state.tag, why: "fallback")
  }

  /// Off already, they are someone else's to put back.
  private static func holdAnimations(owner: HoldOwner) {
    if heldAnimations == nil {
      guard UIView.areAnimationsEnabled else { return }
      heldAnimations = true
      UIView.setAnimationsEnabled(false)
    }
    holdOwner = owner
  }

  /// Only for the latest owner: an earlier turn's would put them back in the middle of the next. nil puts them back
  /// whoever holds them.
  private static func releaseAnimations(owner: HoldOwner?) {
    guard let saved = heldAnimations, owner == nil || owner == holdOwner else { return }
    heldAnimations = nil
    holdOwner = nil
    UIView.setAnimationsEnabled(saved)
  }

  private static func takeAway(_ still: UIView, _ tag: TurnTag, why: String) {
    guard tag.picture == .fade else {
      still.removeFromSuperview()
      pictureGone(tag, why: why)
      return
    }
    // Core Animation directly: UIView animations may still be off for the rest of the turn.
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1.0
    fade.toValue = 0.0
    fade.duration = fadeSeconds
    still.layer.opacity = 0
    still.layer.add(fade, forKey: fadeKey)
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(fadeSeconds))
      still.removeFromSuperview()
      pictureGone(tag, why: why)
    }
  }

  private static func pictureGone(_ tag: TurnTag, why: String) {
    TurnProbe.log("picture gone", tag, ["why": why])
    sendPictureGone(tag.turn)
  }

  private static func sendPictureGone(_ id: Int) {
    TurnProbe.send("onTurnPictureGone") { try await DeviceChannel.events?.onTurnPictureGone(turn: Int64(id)) }
  }
}

/// One taken-over turn.
@MainActor
private final class TurnState {
  let tag: TurnTag
  weak var window: UIWindow?
  weak var root: UIView?
  /// A still picture went up; not with `none`, `noSpin` or a failed snapshot.
  let pictured: Bool
  /// The picture while it covers the screen, until it is cut or starts to fade.
  var still: UIView?
  var drawn = false
  var settled = false

  init(tag: TurnTag, window: UIWindow?, root: UIView, pictured: Bool) {
    self.tag = tag
    self.window = window
    self.root = root
    self.pictured = pictured
  }
}

/// Main.storyboard's root view controller.
class TurnViewController: FlutterViewController {
  override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
    let from = view.bounds.size
    let target = coordinator.targetTransform
    let angle = atan2(Double(target.b), Double(target.a))
    guard TurnTakeover.enabled, (from.width > from.height) != (size.width > size.height), abs(angle) > 0.01 else {
      super.viewWillTransition(to: size, with: coordinator)
      return
    }
    // noActions: UIKit's rotation block, which runs after this returns, inside a transaction with actions off.
    let noActions = TurnTakeover.method == .noActions
    if noActions {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
    }
    let turn = TurnTakeover.begin(root: view, from: from, to: size, angle: angle, coordinator: coordinator)
    // FlutterViewController holds the old viewport size for half the coordinator's duration, and not at all when it
    // is zero.
    super.viewWillTransition(to: size, with: InstantTurnCoordinator(coordinator))
    if noActions {
      DispatchQueue.main.async {
        MainActor.assumeIsolated { CATransaction.commit() }
      }
    }
    TurnTakeover.afterSuper(turn)
  }
}

/// The real coordinator with a zero duration; everything else reads through to it.
@MainActor
private final class InstantTurnCoordinator: NSObject, UIViewControllerTransitionCoordinator {
  // Unsafe so the Objective-C forwarding below, which has no isolation, can reach it; only UIKit on the main
  // thread calls in.
  private nonisolated(unsafe) let base: any UIViewControllerTransitionCoordinator

  init(_ base: any UIViewControllerTransitionCoordinator) {
    self.base = base
    super.init()
  }

  var transitionDuration: TimeInterval { 0 }
  var isAnimated: Bool { base.isAnimated }
  var presentationStyle: UIModalPresentationStyle { base.presentationStyle }
  var initiallyInteractive: Bool { base.initiallyInteractive }
  var isInterruptible: Bool { base.isInterruptible }
  var isInteractive: Bool { base.isInteractive }
  var isCancelled: Bool { base.isCancelled }
  var percentComplete: CGFloat { base.percentComplete }
  var completionVelocity: CGFloat { base.completionVelocity }
  var completionCurve: UIView.AnimationCurve { base.completionCurve }
  var containerView: UIView { base.containerView }
  var targetTransform: CGAffineTransform { base.targetTransform }

  func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
    base.viewController(forKey: key)
  }

  func view(forKey key: UITransitionContextViewKey) -> UIView? {
    base.view(forKey: key)
  }

  func animate(alongsideTransition animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
               completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)? = nil) -> Bool {
    base.animate(alongsideTransition: animation, completion: completion)
  }

  func animateAlongsideTransition(in view: UIView?,
                                  animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
                                  completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)? = nil)
    -> Bool {
    base.animateAlongsideTransition(in: view, animation: animation, completion: completion)
  }

  func notifyWhenInteractionChanges(_ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void) {
    base.notifyWhenInteractionChanges(handler)
  }

  // Deprecated since iOS 10 but still a requirement; through its replacement to keep the build free of warnings.
  func notifyWhenInteractionEnds(_ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void) {
    base.notifyWhenInteractionChanges { context in
      if !context.isInteractive { handler(context) }
    }
  }

  // UIKit may send the coordinator it handed out messages of its own private class.
  nonisolated override func responds(to aSelector: Selector!) -> Bool {
    super.responds(to: aSelector) || base.responds(to: aSelector)
  }

  nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
    base
  }
}

/// Touches go through it to the Flutter view, or past it should UIKit ever take the Flutter view back out.
private final class TurnContainer: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}
