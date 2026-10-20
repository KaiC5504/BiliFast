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

enum NativeNetwork { wifi, cellular, none }

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

  /// While on, the video page's turns are drawn by Flutter (TurnTakeover.swift): rotations are requested with UIView
  /// animations off, so the scene turns the window at once, Flutter gets the turned size at once under a still
  /// picture until [turnDrawn], and each turn is reported through [DeviceEventApi.onTurn].
  void setTurnTakeover(bool enabled);

  /// Flutter has drawn the first frame of taken-over [turn]; the still picture covering the screen can go.
  void turnDrawn(int turn);

  /// Starts or stops battery and network reports to [DeviceEventApi.onStatus] for the status bar landscape full screen
  /// draws (04); one report comes at once on start. iOS's battery monitoring is on only while they are.
  void setStatusEvents(bool enabled);
}

@FlutterApi()
abstract class DeviceEventApi {
  void onDeviceOrientation(NativeDeviceOrientation orientation);

  void onOrientationRefused(int request, String error);

  /// A hardware button changed the volume while the volume view hides the system HUD.
  void onHardwareVolume(double volume);

  /// Taken-over [turn] (counted from 1 per launch) began: [angle] is the rotation in radians the scene would have
  /// animated (its coordinator's target transform), [seconds] how long it would have taken.
  void onTurn(int turn, double angle, double seconds);

  /// A line for the phone's log from the native side of a turn (docs/reference/turn-log.md); [fields] hold strings,
  /// ints, doubles and bools only.
  void onTurnLog(String kind, Map<String, Object?> fields);

  /// The phone's network path changed and is up (NWPathMonitor). [interfaceChanged] when its interfaces or gateways
  /// differ from the last path that was up, so the engine's speed measurements no longer hold.
  void onNetworkChanged(bool interfaceChanged);

  /// The battery's level (0 to 1, or -1 when iOS can't tell), whether it is charging or full on power, and the network
  /// the phone is on, after [DeviceHostApi.setStatusEvents] and whenever one of them changes.
  void onStatus(double battery, bool charging, NativeNetwork network);
}
