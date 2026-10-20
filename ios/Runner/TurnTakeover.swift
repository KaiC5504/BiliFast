import Flutter
import UIKit

/// The video page's turns drawn by Flutter instead of the scene (lib/video/video_page.dart): Flutter gets the turned
/// size at once instead of halfway through, so the page can turn while the player grows past the upright page's
/// sides, as the official app's does.
///
/// iOS animates the window's rotation out of process unless UIView animations are already off when the rotation is
/// requested: then viewWillTransition comes unanimated with a zero duration and the window turns at once. So while
/// the takeover is on, every request holds animations off until its turn completes. The window turns under a still
/// picture of the screen, turned back so it stays physically where it was; Flutter is told (`onTurn`) and draws the
/// turn, and the picture goes on its first frame or after a timeout. TurnProbe logs each turn.
@MainActor
enum TurnTakeover {
  /// Set from Dart's 开发者 → 旋转动画 (DeviceHostApi.setTurnTakeover); the picture in force when a turn begins is
  /// that turn's.
  private(set) static var enabled = false
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

  private static let fallback = Duration.milliseconds(500)
  private static let requestHoldLimit = Duration.seconds(1)
  private static let fadeSeconds = 0.12
  private static let fadeKey = "fade"

  private enum HoldOwner: Equatable {
    case turn(Int)
    case request(Int)
  }

  static func configure(enabled: Bool, picture: NativeTurnPicture) {
    self.enabled = enabled
    self.picture = picture
  }

  /// Before DeviceChannel asks the scene to turn. Animations are off from here until the turn that follows completes
  /// (or for a second when none comes), so the request is made without animation.
  static func requesting(_ request: Int64, mask: NativeOrientationMask, from interface: UIInterfaceOrientation) {
    TurnProbe.log("request", tag(for: turn), [
      "request": Int(request), "mask": "\(mask)", "interface": TurnProbe.name(interface),
      "animationsEnabled": UIView.areAnimationsEnabled,
    ])
    guard enabled else { return }
    requestHolds += 1
    let hold = HoldOwner.request(requestHolds)
    holdAnimations(owner: hold)
    Task { @MainActor in
      try? await Task.sleep(for: requestHoldLimit)
      releaseAnimations(owner: hold)
    }
  }

  static func requestReturned(_ request: Int64, ms: Double) {
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

  /// Before the turn moves anything. `angle` is the target transform's rotation in radians, positive clockwise on
  /// screen (UIKit's y-down space, the same sense as Flutter's Transform.rotate): once the window has turned, content
  /// drawn at -angle sits where it was, so Dart starts there and animates to 0.
  static func begin(root: UIView, from: CGSize, to size: CGSize, angle: Double,
                    coordinator: any UIViewControllerTransitionCoordinator) {
    let startUs = TurnProbe.wallUs()
    let startMedia = CACurrentMediaTime()
    let animationsWere = UIView.areAnimationsEnabled
    let window = root.window
    let picture = self.picture
    TurnProbe.endFrames()

    // Taken first, so a picture still up from the last turn is in it, as it is on screen.
    let snapping = CACurrentMediaTime()
    let still = picture == .none ? nil : window?.snapshotView(afterScreenUpdates: false)
    let snapshotMs = still == nil ? 0 : (CACurrentMediaTime() - snapping) * 1000
    var replaced: TurnTag?
    if let last = current, let shown = last.still {
      last.still = nil
      shown.removeFromSuperview()
      replaced = last.tag
    }

    turn += 1
    let id = turn
    let tag = TurnTag(turn: id, picture: picture)
    let state = TurnState(tag: tag, pictured: still != nil)
    current = state
    recent[id] = state
    recent = recent.filter { $0.key > id - 8 }

    if let window, let still {
      still.isUserInteractionEnabled = false
      still.bounds = CGRect(origin: .zero, size: window.bounds.size)
      still.center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
      window.addSubview(still)
      state.still = still
    }

    holdAnimations(owner: .turn(id))

    // Turned back inside the transition, as the window takes its new bounds; should the system still animate, the
    // two turns cancel and the picture holds still all the same.
    let queued = coordinator.animate(alongsideTransition: { _ in
      if let still { turnBack(still, to: size, angle: angle) }
      TurnProbe.log("alongside", tag)
    }, completion: { context in
      TurnProbe.log("completion", tag, ["cancelled": context.isCancelled])
      releaseAnimations(owner: .turn(id))
    })
    if !queued {
      if let still { turnBack(still, to: size, angle: angle) }
      releaseAnimations(owner: .turn(id))
    }

    // Ahead of the begin line, so Dart starts drawing first.
    let seconds = coordinator.transitionDuration
    TurnProbe.send("onTurn") {
      try await DeviceChannel.events?.onTurn(turn: Int64(id), angle: angle, seconds: seconds)
    }

    TurnProbe.startFrames(TurnFrames(tag: tag, start: startMedia, window: window, root: root, picture: state.still))

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
    if let replaced { pictureGone(replaced, why: "replaced") }
    if !state.pictured { sendPictureGone(id) }
  }

  private static func tag(for id: Int) -> TurnTag {
    guard enabled else { return TurnTag(turn: id, picture: .none, system: true) }
    return TurnTag(turn: id, picture: picture)
  }

  /// A turn to or from landscape that iOS animates itself (系统): only logged and sampled, with nothing taken over and
  /// nothing sent to Dart.
  static func observe(root: UIView, from: CGSize, to size: CGSize, angle: Double,
                      coordinator: any UIViewControllerTransitionCoordinator) {
    let startUs = TurnProbe.wallUs()
    let startMedia = CACurrentMediaTime()
    TurnProbe.endFrames()
    turn += 1
    let tag = tag(for: turn)
    _ = coordinator.animate(alongsideTransition: nil, completion: { context in
      TurnProbe.log("completion", tag, ["cancelled": context.isCancelled])
    })
    TurnProbe.startFrames(TurnFrames(tag: tag, start: startMedia, window: root.window, root: root, picture: nil))
    TurnProbe.log("begin", tag, [
      "angle": angle, "seconds": coordinator.transitionDuration, "animated": coordinator.isAnimated,
      "fromW": Double(from.width), "fromH": Double(from.height),
      "toW": Double(size.width), "toH": Double(size.height),
      "animationsEnabled": UIView.areAnimationsEnabled, "snapshot": false, "snapshotMs": 0.0,
    ], at: startUs)
  }

  private static func turnBack(_ still: UIView, to size: CGSize, angle: Double) {
    still.transform = CGAffineTransform(rotationAngle: CGFloat(-angle))
    still.center = CGPoint(x: size.width / 2, y: size.height / 2)
  }

  private static func fellBack(_ state: TurnState) {
    guard state === current else { return }
    releaseAnimations(owner: .turn(state.tag.turn))
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

  /// Only for the latest owner: an earlier turn's would put them back in the middle of the next.
  private static func releaseAnimations(owner: HoldOwner) {
    guard let saved = heldAnimations, owner == holdOwner else { return }
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
  /// A still picture went up; not with `none` or a failed snapshot.
  let pictured: Bool
  /// The picture while it covers the screen, until it is cut or starts to fade.
  var still: UIView?
  var drawn = false

  init(tag: TurnTag, pictured: Bool) {
    self.tag = tag
    self.pictured = pictured
  }
}

/// Main.storyboard's root view controller.
class TurnViewController: FlutterViewController {
  override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
    let from = view.bounds.size
    let target = coordinator.targetTransform
    let angle = atan2(Double(target.b), Double(target.a))
    let quarter = (from.width > from.height) != (size.width > size.height) && abs(angle) > 0.01
    guard TurnTakeover.enabled, quarter else {
      if quarter { TurnTakeover.observe(root: view, from: from, to: size, angle: angle, coordinator: coordinator) }
      super.viewWillTransition(to: size, with: coordinator)
      return
    }
    TurnTakeover.begin(root: view, from: from, to: size, angle: angle, coordinator: coordinator)
    // FlutterViewController holds the old viewport size for half the coordinator's duration, and not at all when it
    // is zero.
    super.viewWillTransition(to: size, with: InstantTurnCoordinator(coordinator))
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
