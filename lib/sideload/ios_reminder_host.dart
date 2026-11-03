import 'package:bili_core/devlog.dart';

import '../device/ios/device_api.g.dart';
import 'sideload_model.dart';

/// The reminder through DeviceChannel.swift (UNUserNotificationCenter). The host's errors are logged by type and go no
/// further; a failed permission ask counts as a refusal, so the reminder stays off.
final class IosReminderHost implements ReminderHost {
  IosReminderHost({DeviceHostApi? host, Logger? logger})
    : _host = host ?? DeviceHostApi(),
      _logger = logger ?? Logger.shared;

  final DeviceHostApi _host;
  final Logger _logger;

  @override
  Future<bool> requestPermission() async {
    try {
      return await _host.requestReminderPermission();
    } catch (error) {
      _failed('permission', error);
      return false;
    }
  }

  @override
  Future<void> schedule(DateTime at, String title, String body) async {
    try {
      await _host.scheduleReminder(at.millisecondsSinceEpoch, title, body);
    } catch (error) {
      _failed('schedule', error);
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _host.cancelReminder();
    } catch (error) {
      _failed('cancel', error);
    }
  }

  void _failed(String call, Object error) =>
      _logger.warn(LogCategory.app, 'sideload reminder failed', {'call': call, 'error': '${error.runtimeType}'});
}
