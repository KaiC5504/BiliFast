import Flutter
import Network

/// The phone's network path for the engine (port of PlaybackController.swift's NWPathMonitor), reported through
/// DeviceEventApi.onNetworkChanged.
@MainActor
enum NetworkMonitor {
  static func start() {}
}
