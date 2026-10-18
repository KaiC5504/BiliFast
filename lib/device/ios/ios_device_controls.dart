import 'package:bili_core/devlog.dart';
import 'package:flutter/services.dart';

import '../device_controls.dart';
import 'device_api.g.dart';
import 'ios_device_events.dart';

/// DeviceControls.swift over Pigeon (pigeons/device_api.dart).
final class IosDeviceControls implements DeviceControls {
  IosDeviceControls(this._host, this._events, {Logger? logger}) : _logger = logger ?? Logger.shared;

  /// What DeviceControls.swift throws when the MPVolumeView has no slider to move.
  static const missingSliderCode = 'no-volume-slider';

  final DeviceHostApi _host;
  final IosDeviceEvents _events;
  final Logger _logger;
  bool _reportedMissingSlider = false;

  @override
  Future<double> brightness() => _host.brightness();

  @override
  Future<void> setBrightness(double value) => _host.setBrightness(value.clamp(0, 1).toDouble());

  @override
  Future<double> volume() => _host.volume();

  @override
  Future<void> setVolume(double value) async {
    try {
      await _host.setVolume(value.clamp(0, 1).toDouble());
    } on PlatformException catch (error) {
      if (error.code != missingSliderCode) rethrow;
      if (_reportedMissingSlider) return;
      _reportedMissingSlider = true;
      _logger.warn(LogCategory.ui, 'volume slider not found; the volume gesture does nothing');
    }
  }

  @override
  Stream<double> get hardwareVolume => _events.hardwareVolume;

  // Both messages leave before either reply, so a leave right after an enter still reaches the native side after it.
  @override
  Future<void> enterFullScreen() => Future.wait([_host.saveBrightness(), _host.attachVolumeView()]);

  @override
  Future<void> leaveFullScreen() => Future.wait([_host.detachVolumeView(), _host.restoreBrightness()]);
}
