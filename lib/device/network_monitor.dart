import 'dart:io' show Platform;

import 'ios/ios_device_events.dart';

/// The phone's network path changing (port of PlaybackController.swift's NWPathMonitor): one event per change to a
/// path that is up, true when its interfaces or gateways changed from the last path that was up.
abstract interface class NetworkMonitor {
  /// The monitor of the platform the app runs on.
  static NetworkMonitor platform() => Platform.isIOS ? const IosNetworkMonitor() : const NoNetworkMonitor();

  Stream<bool> get changes;
}

/// NetworkMonitor.swift's events.
final class IosNetworkMonitor implements NetworkMonitor {
  const IosNetworkMonitor();

  @override
  Stream<bool> get changes => IosDeviceEvents.shared.networkChanges;
}

/// The PC never reports a change.
final class NoNetworkMonitor implements NetworkMonitor {
  const NoNetworkMonitor();

  @override
  Stream<bool> get changes => const Stream.empty();
}
