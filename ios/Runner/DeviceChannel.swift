import Flutter
import UIKit

/// Dart's full-screen rotation and level controls (lib/device/): Pigeon's DeviceHostApi and DeviceEventApi
/// (DeviceApi.g.swift). The app delegate's supported orientations follow `mask`.
enum DeviceChannel {
  /// What the app delegate reports; portrait until Dart asks for full screen.
  @MainActor static var mask: UIInterfaceOrientationMask = .portrait

  static func register(with messenger: FlutterBinaryMessenger) {
    DeviceHostApiSetup.setUp(binaryMessenger: messenger, api: DeviceHostApiImpl(events: DeviceEventApi(binaryMessenger: messenger)))
  }
}

/// Pigeon calls in on the main thread.
final class DeviceHostApiImpl: DeviceHostApi {
  private let events: DeviceEventApi

  init(events: DeviceEventApi) {
    self.events = events
  }

  func setOrientationEvents(enabled: Bool) throws {}

  func deviceOrientation() throws -> NativeDeviceOrientation { .unknown }

  func interfaceOrientation() throws -> NativeInterfaceOrientation { .unknown }

  func requestOrientations(request: Int64, mask: NativeOrientationMask) throws {}

  func brightness() throws -> Double { 0.5 }

  func setBrightness(value: Double) throws {}

  func saveBrightness() throws {}

  func restoreBrightness() throws {}

  func volume() throws -> Double { 0.5 }

  func setVolume(value: Double) throws {}

  func attachVolumeView() throws {}

  func detachVolumeView() throws {}
}
