import Flutter
import Foundation

/// The one UserDefaults value the Swift BiliFast left behind that Dart reads: 最近打开 under `home.recents`
/// (BiliNative `Home/RecentStore.swift`), JSON Data handed over as a UTF-8 string, nil when there is none.
enum LegacyDefaults {
  private static let recentsKey = "home.recents"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "bilifast/legacy_defaults", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "recents":
        result(UserDefaults.standard.data(forKey: recentsKey).flatMap { String(data: $0, encoding: .utf8) })
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
