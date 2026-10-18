import 'device_controls.dart';
import 'orientation.dart';

/// The phone's side of full screen, one for the app: rotation, and brightness and volume.
final class PlayerDevice {
  PlayerDevice({required this.orientation, required this.controls});

  /// The phone's own rotation and levels on iOS; everywhere else full screen is a layout inside the window.
  factory PlayerDevice.platform() => PlayerDevice.inWindow();

  factory PlayerDevice.inWindow() {
    final controls = NoDeviceControls();
    return PlayerDevice(orientation: OrientationController(controls: controls), controls: controls);
  }

  final OrientationController orientation;
  final DeviceControls controls;
}
