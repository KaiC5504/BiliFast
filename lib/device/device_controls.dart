import 'dart:async';

/// Screen brightness and the system volume for the full-screen level gestures (BiliNative `DeviceControls.swift`).
/// Levels run from 0 to 1.
abstract interface class DeviceControls {
  Future<double> brightness();

  Future<void> setBrightness(double value);

  Future<double> volume();

  Future<void> setVolume(double value);

  /// Volume changes from the hardware buttons while full screen keeps the system HUD away.
  Stream<double> get hardwareVolume;

  /// Remembers the brightness and puts up the hidden volume view; [leaveFullScreen] undoes both.
  Future<void> enterFullScreen();

  Future<void> leaveFullScreen();
}

/// Windows and tests: levels kept in memory, nothing reaches the system.
final class NoDeviceControls implements DeviceControls {
  NoDeviceControls();

  double _brightness = 0.5;
  double _volume = 0.5;

  @override
  Future<double> brightness() async => _brightness;

  @override
  Future<void> setBrightness(double value) async => _brightness = value.clamp(0, 1);

  @override
  Future<double> volume() async => _volume;

  @override
  Future<void> setVolume(double value) async => _volume = value.clamp(0, 1);

  @override
  Stream<double> get hardwareVolume => const Stream.empty();

  @override
  Future<void> enterFullScreen() async {}

  @override
  Future<void> leaveFullScreen() async {}
}
