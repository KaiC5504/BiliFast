import Flutter
import UIKit
import UserNotifications

/// Dart's full-screen rotation and level controls, the drawn status bar's feed (lib/device/) and a sideloaded
/// install's 到期提醒: Pigeon's DeviceHostApi and DeviceEventApi (DeviceApi.g.swift). The app delegate's supported
/// orientations follow `mask`.
enum DeviceChannel {
  /// What the app delegate reports; portrait until Dart asks for full screen. The iPad turns freely on every screen,
  /// full screen included, so it is always all four there.
  @MainActor static var mask: UIInterfaceOrientationMask {
    get { isPad ? .all : phoneMask }
    set { phoneMask = newValue }
  }

  @MainActor private static var phoneMask: UIInterfaceOrientationMask = .portrait

  @MainActor static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

  /// Set once at registration; the callbacks that arrive off the main actor reach Dart through it.
  @MainActor static var events: DeviceEventApi?

  static func register(with messenger: FlutterBinaryMessenger) {
    MainActor.assumeIsolated {
      DeviceChannel.events = DeviceEventApi(binaryMessenger: messenger)
      DeviceControls.hardwareVolumeChanged = { volume in
        Task { @MainActor in try? await DeviceChannel.events?.onHardwareVolume(volume: volume) }
      }
    }
    DeviceHostApiSetup.setUp(binaryMessenger: messenger, api: DeviceHostApiImpl())
  }

  @MainActor static var scene: UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
  }

  /// Asks the scene to turn to `wanted`; returns how long requestGeometryUpdate took, in milliseconds.
  @MainActor static func ask(_ scene: UIWindowScene, for wanted: UIInterfaceOrientationMask, request: Int64) -> Double {
    // iOS intersects the root controller's orientations (SystemChrome's, all by default) with the app delegate's,
    // so the controllers must ask again after `mask` changes.
    for window in scene.windows {
      window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
    let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: wanted)
    let started = CACurrentMediaTime()
    scene.requestGeometryUpdate(preferences) { @Sendable error in
      let message = String(describing: error)
      Task { @MainActor in try? await DeviceChannel.events?.onOrientationRefused(request: request, error: message) }
    }
    return (CACurrentMediaTime() - started) * 1000
  }
}

/// Pigeon calls in on the main thread.
final class DeviceHostApiImpl: DeviceHostApi {
  private let orientation = MainActor.assumeIsolated { OrientationEvents() }
  private let status = MainActor.assumeIsolated { StatusEvents() }

  func idfv() throws -> String? {
    MainActor.assumeIsolated { UIDevice.current.identifierForVendor?.uuidString }
  }

  func isPad() throws -> Bool {
    MainActor.assumeIsolated { DeviceChannel.isPad }
  }

  func setOrientationEvents(enabled: Bool) throws {
    let orientation = self.orientation
    MainActor.assumeIsolated { enabled ? orientation.start() : orientation.stop() }
  }

  func deviceOrientation() throws -> NativeDeviceOrientation {
    MainActor.assumeIsolated { OrientationEvents.native(UIDevice.current.orientation) }
  }

  func interfaceOrientation() throws -> NativeInterfaceOrientation {
    MainActor.assumeIsolated {
      guard let current = DeviceChannel.scene?.effectiveGeometry.interfaceOrientation else { return .unknown }
      switch current {
      case .portrait: return .portrait
      case .landscapeLeft: return .landscapeLeft
      case .landscapeRight: return .landscapeRight
      default: return .unknown
      }
    }
  }

  func requestOrientations(request: Int64, mask: NativeOrientationMask) throws {
    MainActor.assumeIsolated {
      let wanted: UIInterfaceOrientationMask
      switch mask {
      case .portrait: wanted = .portrait
      case .landscape: wanted = .landscape
      case .landscapeLeft: wanted = .landscapeLeft
      case .landscapeRight: wanted = .landscapeRight
      }
      // Dart's rules never ask on the iPad; should a request come all the same, nothing turns and Dart reverts.
      guard !DeviceChannel.isPad else {
        Task { @MainActor in try? await DeviceChannel.events?.onOrientationRefused(request: request, error: "pad") }
        return
      }
      DeviceChannel.mask = wanted
      guard let scene = DeviceChannel.scene else {
        Task { @MainActor in
          try? await DeviceChannel.events?.onOrientationRefused(request: request, error: "no window scene")
        }
        return
      }
      TurnTakeover.requesting(request, mask: mask, from: scene.effectiveGeometry.interfaceOrientation)
      let ms = DeviceChannel.ask(scene, for: wanted, request: request)
      TurnTakeover.requestReturned(request, ms: ms)
    }
  }

  func brightness() throws -> Double {
    MainActor.assumeIsolated { DeviceControls.brightness }
  }

  func setBrightness(value: Double) throws {
    MainActor.assumeIsolated { DeviceControls.brightness = value }
  }

  func volume() throws -> Double {
    MainActor.assumeIsolated { DeviceControls.volume() }
  }

  func setVolume(value: Double) throws {
    let moved = MainActor.assumeIsolated { DeviceControls.setVolume(value) }
    if !moved {
      throw DeviceApiError(code: "no-volume-slider", message: "MPVolumeView has no slider", details: nil)
    }
  }

  func attachVolumeView() throws {
    MainActor.assumeIsolated { DeviceControls.attachVolumeView() }
  }

  func detachVolumeView() throws {
    MainActor.assumeIsolated { DeviceControls.detachVolumeView() }
  }

  func setTurnTakeover(enabled: Bool) throws {
    MainActor.assumeIsolated { TurnTakeover.configure(enabled: enabled) }
  }

  func turnDrawn(turn: Int64) throws {
    MainActor.assumeIsolated { TurnTakeover.drawn(turn: Int(turn)) }
  }

  func setStatusEvents(enabled: Bool) throws {
    let status = self.status
    MainActor.assumeIsolated { enabled ? status.start() : status.stop() }
  }

  func network() throws -> NativeNetwork {
    MainActor.assumeIsolated { NetworkMonitor.kind }
  }

  func requestReminderPermission() async throws -> Bool {
    do {
      return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    } catch {
      throw Self.notificationError(error)
    }
  }

  func scheduleReminder(epochMs: Int64, title: String, body: String) async throws {
    let center = UNUserNotificationCenter.current()
    let interval = Date(timeIntervalSince1970: Double(epochMs) / 1000).timeIntervalSinceNow
    // A time-interval trigger raises unless the interval is positive; the reminder it would replace is stale too.
    guard interval > 0 else {
      center.removePendingNotificationRequests(withIdentifiers: [Self.reminder])
      return
    }
    // Before iOS 27, add() succeeds silently once the user has turned the app's notifications off, so ask first and
    // answer as add() would, letting the reminder show as off.
    let allowed: [UNAuthorizationStatus] = [.authorized, .provisional, .ephemeral]
    guard allowed.contains(await center.notificationSettings().authorizationStatus) else {
      throw DeviceApiError(code: "notifications",
                           message: "\(UNErrorDomain) \(UNError.Code.notificationsNotAllowed.rawValue)", details: nil)
    }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    do {
      try await center.add(UNNotificationRequest(identifier: Self.reminder, content: content, trigger: trigger))
    } catch {
      throw Self.notificationError(error)
    }
  }

  func cancelReminder() throws {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminder])
  }

  /// The one signature reminder: a request added under an identifier already pending replaces it.
  private static let reminder = "com.kaichuan.bilifast.signature.reminder"

  /// Only the domain and code reach Dart, never the error's localized text.
  private static func notificationError(_ error: Error) -> DeviceApiError {
    let failure = error as NSError
    return DeviceApiError(code: "notifications", message: "\(failure.domain) \(failure.code)", details: nil)
  }
}

/// UIDevice's orientation notifications, on only while a page with a player is open.
@MainActor
final class OrientationEvents {
  private var observer: NSObjectProtocol?

  func start() {
    guard observer == nil else { return }
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    observer = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil,
                                                      queue: .main) { _ in
      MainActor.assumeIsolated {
        let orientation = OrientationEvents.native(UIDevice.current.orientation)
        Task { @MainActor in try? await DeviceChannel.events?.onDeviceOrientation(orientation: orientation) }
      }
    }
  }

  func stop() {
    guard let observer else { return }
    NotificationCenter.default.removeObserver(observer)
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
    self.observer = nil
  }

  static func native(_ orientation: UIDeviceOrientation) -> NativeDeviceOrientation {
    switch orientation {
    case .portrait: return .portrait
    case .portraitUpsideDown: return .portraitUpsideDown
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    case .faceUp: return .faceUp
    case .faceDown: return .faceDown
    default: return .unknown
    }
  }
}

/// The battery and the network for the status bar landscape full screen draws, on only while it is on screen.
@MainActor
final class StatusEvents {
  private var observers: [NSObjectProtocol] = []
  private var monitoringWasOn = false

  func start() {
    // Already on after a Dart restart: Dart still waits for the first report a start promises.
    guard observers.isEmpty else { return StatusEvents.report() }
    let device = UIDevice.current
    monitoringWasOn = device.isBatteryMonitoringEnabled
    device.isBatteryMonitoringEnabled = true
    // Becoming active too: a change made while the app was suspended isn't promised a notification.
    let names = [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification,
                 UIApplication.didBecomeActiveNotification]
    observers = names.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { StatusEvents.report() }
      }
    }
    NetworkMonitor.kindChanged = { StatusEvents.report() }
    StatusEvents.report()
  }

  func stop() {
    guard !observers.isEmpty else { return }
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
    NetworkMonitor.kindChanged = nil
    if !monitoringWasOn { UIDevice.current.isBatteryMonitoringEnabled = false }
  }

  private static func report() {
    let device = UIDevice.current
    let battery = Double(device.batteryLevel)
    let charging = device.batteryState == .charging || device.batteryState == .full
    let network = NetworkMonitor.kind
    Task { @MainActor in
      try? await DeviceChannel.events?.onStatus(battery: battery, charging: charging, network: network)
    }
  }
}
