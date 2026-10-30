import Flutter
import UIKit

/// 离线缓存's host (lib/offline/ios/offline_api.g.dart): Pigeon's OfflineHostApi (OfflineApi.g.swift) and the
/// background URLSession that keeps a download going after the app leaves the foreground.
enum OfflineHost {
  static func register(with messenger: FlutterBinaryMessenger) {
    OfflineHostApiSetup.setUp(binaryMessenger: messenger, api: OfflineHostApiImpl(events: OfflineEventApi(binaryMessenger: messenger)))
  }
}

/// The background session lives as long as the app: iOS hands its events to a session of the same identifier, which
/// must exist by the time `handleEventsForBackgroundURLSession` arrives.
final class OfflineTransfers: NSObject {
  static let shared = OfflineTransfers()
  static let identifier = "com.kaichuan.bilifast.offline"

  /// Called from didFinishLaunching, so a relaunch in the background reattaches to its transfers.
  func resume() {}

  /// iOS woke or relaunched the app for the session's events; [completion] runs once they are all handled.
  func handleEvents(identifier: String, completion: @escaping () -> Void) {
    completion()
  }
}

final class OfflineHostApiImpl: OfflineHostApi {
  init(events: OfflineEventApi) {
    self.events = events
  }

  private let events: OfflineEventApi

  func freeBytes() throws -> Int64? { nil }

  func excludeFromBackup(path: String) throws {}

  func beginGrace() throws {}

  func endGrace() throws {}

  func handOff(ranges: [NativeBackgroundRange]) throws {}

  func takeBack() async throws -> [NativeBackgroundRangeResult] { [] }
}
