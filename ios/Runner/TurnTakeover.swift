import Flutter
import UIKit

/// The video page's turns drawn by Flutter instead of the scene (lib/video/video_page.dart): with the system's
/// rotation animation off, Flutter gets the turned size at once instead of halfway through, so the page can turn
/// while the player grows past the upright page's sides, as the official app's does.
///
/// The window turns in one frame under a still picture of the screen, turned back so it stays physically where it
/// was; Flutter is told (`onTurn`) and draws the turn, and the picture goes on its first frame or after a timeout.
@MainActor
enum TurnTakeover {
  /// Set from Dart's 开发者 switch 旋转动画 (DeviceHostApi.setTurnTakeover).
  static var enabled = false
  static var method: NativeTurnMethod = .legacy
  static var picture: NativeTurnPicture = .cut

  private static var picture: UIView?

  /// Counts the turns: what one turn left to run later acts only while it is still the latest.
  private static var turn = 0

  /// UIView.areAnimationsEnabled as found before the turns held it off, to put back; nil while not holding.
  private static var heldAnimations: Bool?
  private static let fallback = Duration.milliseconds(500)
  private static let fadeSeconds = 0.12

  /// Flutter drew `turn`'s first frame; the still picture goes.
  static func drawn(turn: Int) {
    fadeAway()
  }

  /// Before the turn moves anything. `angle` is the target transform's rotation in radians, positive clockwise on
  /// screen (UIKit's y-down space, the same sense as Flutter's Transform.rotate): once the window has turned,
  /// content drawn at -angle sits where it was, so Dart starts there and animates to 0.
  static func begin(in window: UIWindow?, to size: CGSize, angle: Double,
                    coordinator: any UIViewControllerTransitionCoordinator) {
    // Taken first, so a picture still up from the last turn is in it, as it is on screen.
    let still = window?.snapshotView(afterScreenUpdates: false)
    picture?.removeFromSuperview()
    picture = nil
    if let window, let still {
      still.isUserInteractionEnabled = false
      still.bounds = CGRect(origin: .zero, size: window.bounds.size)
      still.center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
      window.addSubview(still)
      picture = still
    }

    turn += 1
    let id = turn
    holdAnimations()
    // Turned back inside the transition, as the window takes its new bounds; should the system still animate, the
    // two turns cancel and the picture holds still all the same.
    let queued = coordinator.animate(alongsideTransition: { _ in
      if let still { turnBack(still, to: size, angle: angle) }
    }, completion: { _ in
      releaseAnimations(for: id)
    })
    if !queued {
      if let still { turnBack(still, to: size, angle: angle) }
      releaseAnimations(for: id)
    }

    let seconds = coordinator.transitionDuration
    Task { @MainActor in try? await DeviceChannel.events?.onTurn(turn: Int64(id), angle: angle, seconds: seconds) }

    Task { @MainActor in
      try? await Task.sleep(for: fallback)
      guard id == turn else { return }
      releaseAnimations(for: id)
      fadeAway()
    }
  }

  private static func turnBack(_ still: UIView, to size: CGSize, angle: Double) {
    still.transform = CGAffineTransform(rotationAngle: CGFloat(-angle))
    still.center = CGPoint(x: size.width / 2, y: size.height / 2)
  }

  /// Off already, they are someone else's to put back.
  private static func holdAnimations() {
    let enabled = UIView.areAnimationsEnabled
    guard heldAnimations == nil, enabled else { return }
    heldAnimations = enabled
    UIView.setAnimationsEnabled(false)
  }

  /// Only for the latest turn: an earlier one's would put them back in the middle of the next.
  private static func releaseAnimations(for id: Int) {
    guard id == turn, let saved = heldAnimations else { return }
    heldAnimations = nil
    UIView.setAnimationsEnabled(saved)
  }

  private static func fadeAway() {
    guard let still = picture else { return }
    picture = nil
    // Core Animation directly: UIView animations may still be off for the rest of the turn.
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1.0
    fade.toValue = 0.0
    fade.duration = fadeSeconds
    still.layer.opacity = 0
    still.layer.add(fade, forKey: "fade")
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(fadeSeconds))
      still.removeFromSuperview()
    }
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
    TurnTakeover.begin(in: view.window, to: size, angle: angle, coordinator: coordinator)
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
