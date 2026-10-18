import AVKit
import Flutter
import UIKit

/// The iPhone player for Dart's IosPlayer: Pigeon's PlayerHostApi and PlayerEventApi (PlayerApi.g.swift) and
/// the `bilifast/player` platform view, all over one PlayerRegistry.
enum PlayerChannel {
  static let viewType = "bilifast/player"

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let registry = MainActor.assumeIsolated { PlayerRegistry(events: PlayerEventApi(binaryMessenger: messenger)) }
    PlayerHostApiSetup.setUp(binaryMessenger: messenger, api: PlayerHostApiImpl(registry: registry))
    // The view takes no touches, so nothing needs blocking; this policy also leaves out the delaying
    // recognizer that the other two put on top of it.
    registrar.register(PlayerViewFactory(registry: registry), withId: viewType,
                       gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture)
  }
}

/// Pigeon calls in on the main thread, where AVPlayer and the views live.
final class PlayerHostApiImpl: PlayerHostApi {
  private let registry: PlayerRegistry

  init(registry: PlayerRegistry) {
    self.registry = registry
  }

  func create() throws -> Int64 {
    let registry = self.registry
    return MainActor.assumeIsolated { registry.create() }
  }

  func pictureInPictureSupported() throws -> Bool {
    MainActor.assumeIsolated { AVPictureInPictureController.isPictureInPictureSupported() }
  }

  func load(playerId: Int64, url: String, headers: [String: String], startSeconds: Double, autoplay: Bool) throws {
    guard let parsed = URL(string: url) else {
      throw PlayerApiError(code: "bad-url", message: "the master playlist URL does not parse", details: nil)
    }
    let registry = self.registry
    try MainActor.assumeIsolated {
      try registry.player(playerId).load(url: parsed, headers: headers, startSeconds: startSeconds, autoplay: autoplay)
    }
  }

  func play(playerId: Int64) throws {
    let registry = self.registry
    try MainActor.assumeIsolated { try registry.player(playerId).play() }
  }

  func pause(playerId: Int64) throws {
    let registry = self.registry
    try MainActor.assumeIsolated { try registry.player(playerId).pause() }
  }

  func seek(playerId: Int64, seconds: Double, precise: Bool) throws {
    let registry = self.registry
    try MainActor.assumeIsolated { try registry.player(playerId).seek(seconds: seconds, precise: precise) }
  }

  func setRate(playerId: Int64, rate: Double) throws {
    let registry = self.registry
    try MainActor.assumeIsolated { try registry.player(playerId).setRate(rate) }
  }

  func setMuted(playerId: Int64, muted: Bool) throws {
    let registry = self.registry
    try MainActor.assumeIsolated { try registry.player(playerId).setMuted(muted) }
  }

  func setKeepAwake(enabled: Bool) throws {
    MainActor.assumeIsolated { UIApplication.shared.isIdleTimerDisabled = enabled }
  }

  func setFit(playerId: Int64, fit: NativeFit) throws {
    let registry = self.registry
    try MainActor.assumeIsolated { try registry.player(playerId).setFit(fit) }
  }

  func setMirrored(playerId: Int64, mirrored: Bool) throws {
    let registry = self.registry
    try MainActor.assumeIsolated { try registry.player(playerId).setMirrored(mirrored) }
  }

  func startPiP(playerId: Int64) throws {
    let registry = self.registry
    try MainActor.assumeIsolated { try registry.player(playerId).startPiP() }
  }

  func stopPiP(playerId: Int64) throws {
    let registry = self.registry
    try MainActor.assumeIsolated { try registry.player(playerId).stopPiP() }
  }

  func setAutoPiP(playerId: Int64, enabled: Bool) throws {
    let registry = self.registry
    try MainActor.assumeIsolated { try registry.player(playerId).setAutoPiP(enabled) }
  }

  func captureFrame(playerId: Int64, completion: @escaping (Result<Bool, Error>) -> Void) {
    let registry = self.registry
    let reply = CaptureReply(call: completion)
    MainActor.assumeIsolated { registry.captureFrame(playerId, reply: reply) }
  }

  func dispose(playerId: Int64) throws {
    let registry = self.registry
    MainActor.assumeIsolated { registry.dispose(playerId) }
  }
}

/// Every `bilifast/player` platform view only shows an existing player's host view; the player itself belongs to
/// the registry.
final class PlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  private let registry: PlayerRegistry

  init(registry: PlayerRegistry) {
    self.registry = registry
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let id = ((args as? [String: Any])?["id"] as? NSNumber)?.int64Value
    let registry = self.registry
    let container: UIView = MainActor.assumeIsolated {
      let container = UIView(frame: frame)
      container.backgroundColor = .black
      container.isUserInteractionEnabled = false
      if let id { registry.hostView(id)?.attach(to: container) }
      return container
    }
    return PlayerPlatformView(container: container)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class PlayerPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(container: UIView) {
    self.container = container
    super.init()
  }

  func view() -> UIView {
    container
  }

  /// iOS platform views get no dispose call: the engine releases this object. The host view leaves with it,
  /// unless a newer platform view has already taken it, and the player keeps playing.
  deinit {
    let container = self.container
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        for case let host as PlayerHostView in container.subviews {
          host.detach(from: container)
        }
      }
    }
  }
}
