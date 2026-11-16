import BackgroundTasks
import Flutter
import UserNotifications

/// 推送设置's notifications without a server: iOS's app refresh wakes the app now and then, the check asks Bilibili's
/// unread counts with the keychain's login, and anything new is posted as a local notification. It runs natively
/// because a background launch may bring up no Flutter engine at all. Ids, names and comment text never reach a log.
final class NotifyHost: NSObject, NotifyHostApi, UNUserNotificationCenterDelegate {
  static let shared = NotifyHost()
  static let refreshIdentifier = "com.kaichuan.bilifast.notify.refresh"

  private var events: NotifyEventApi?

  static func register(with messenger: FlutterBinaryMessenger) {
    shared.events = NotifyEventApi(binaryMessenger: messenger)
    NotifyHostApiSetup.setUp(binaryMessenger: messenger, api: shared)
  }

  /// From didFinishLaunching: BGTaskScheduler takes handlers only before launch ends, and a tap that launched the
  /// app reaches the delegate set here.
  func launch() {
    UNUserNotificationCenter.current().delegate = self
  }

  func kinds() throws -> NativeNotifyKinds {
    NativeNotifyKinds(replies: false, mentions: false, likes: false, messages: false, uploads: false)
  }

  func setKinds(kinds: NativeNotifyKinds) throws {}

  func permission() async throws -> NativeNotifyPermission {
    .notDetermined
  }

  func requestPermission() async throws -> Bool {
    false
  }

  func takeLaunchRoute() throws -> NativeNotifyRoute? {
    nil
  }

  func takeTrips() throws -> [NativeNotifyTrip] {
    []
  }
}
