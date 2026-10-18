// Regenerate after any change, from the repo root:
//   fvm dart run pigeon --input pigeons/device_api.dart
// and commit both outputs (lib/device/ios/device_api.g.dart, ios/Runner/DeviceApi.g.swift).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/device/ios/device_api.g.dart',
    swiftOut: 'ios/Runner/DeviceApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'DeviceApiError'),
  ),
)
enum NativeOrientationMask { portrait, landscape, landscapeLeft, landscapeRight }

enum NativeDeviceOrientation { portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown, unknown }

enum NativeInterfaceOrientation { portrait, landscapeLeft, landscapeRight, unknown }

/// Rotation, brightness and volume for full screen (DeviceChannel.swift, DeviceControls.swift). The rules about
/// when to rotate live in Dart (lib/device/orientation.dart); the host only applies masks and reports.
@HostApi()
abstract class DeviceHostApi {
  /// Starts or stops device orientation events (UIDevice notifications) to [DeviceEventApi.onDeviceOrientation].
  void setOrientationEvents(bool enabled);

  NativeDeviceOrientation deviceOrientation();

  NativeInterfaceOrientation interfaceOrientation();

  /// Makes [mask] the app delegate's supported orientations and asks the scene to rotate to it. iOS answers only
  /// when it refuses, through [DeviceEventApi.onOrientationRefused] with this [request].
  void requestOrientations(int request, NativeOrientationMask mask);

  double brightness();

  void setBrightness(double value);

  /// Remembers the brightness from before full screen, once, until [restoreBrightness] puts it back.
  void saveBrightness();

  void restoreBrightness();

  double volume();

  /// Through the hidden MPVolumeView's slider; does nothing while that view is detached, and throws
  /// `no-volume-slider` when it is attached but has no slider.
  void setVolume(double value);

  /// The hidden MPVolumeView, there only in full screen, which also keeps the system volume HUD away.
  void attachVolumeView();

  void detachVolumeView();
}

@FlutterApi()
abstract class DeviceEventApi {
  void onDeviceOrientation(NativeDeviceOrientation orientation);

  void onOrientationRefused(int request, String error);

  /// A hardware button changed the volume while the volume view hides the system HUD.
  void onHardwareVolume(double volume);
}
