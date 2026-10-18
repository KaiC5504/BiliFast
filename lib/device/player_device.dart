import 'package:flutter/foundation.dart';

import 'device_controls.dart';
import 'ios/device_api.g.dart';
import 'ios/ios_device_controls.dart';
import 'ios/ios_device_events.dart';
import 'ios/ios_orientation_host.dart';
import 'orientation.dart';

/// The phone's side of full screen, one for the app: rotation, and brightness and volume.
final class PlayerDevice {
  PlayerDevice({required this.orientation, required this.controls});

  /// The phone's own rotation and levels on iOS; everywhere else full screen is a layout inside the window.
  factory PlayerDevice.platform() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? PlayerDevice.ios() : PlayerDevice.inWindow();

  factory PlayerDevice.inWindow() {
    final controls = NoDeviceControls();
    return PlayerDevice(orientation: OrientationController(controls: controls), controls: controls);
  }

  /// DeviceChannel.swift and DeviceControls.swift; tests pass their own Pigeon ends.
  factory PlayerDevice.ios({DeviceHostApi? host, IosDeviceEvents? events}) {
    final api = host ?? DeviceHostApi();
    final hub = events ?? IosDeviceEvents.shared;
    final controls = IosDeviceControls(api, hub);
    return PlayerDevice(
      orientation: OrientationController(controls: controls, host: IosOrientationHost(api, hub)),
      controls: controls,
    );
  }

  final OrientationController orientation;
  final DeviceControls controls;
}
