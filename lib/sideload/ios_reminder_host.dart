import 'package:bili_core/devlog.dart';
import 'package:flutter/services.dart';

import '../device/ios/device_api.g.dart';
import 'sideload_model.dart';

/// The reminder through DeviceChannel.swift (UNUserNotificationCenter). The host's errors are logged and go no
/// further; a failed permission ask counts as a refusal, so the reminder stays off.
final class IosReminderHost implements ReminderHost {
  IosReminderHost({DeviceHostApi? host, Logger? logger})
    : _host = host ?? DeviceHostApi(),
      _logger = logger ?? Logger.shared;

  /// DeviceChannel.swift's code for UNUserNotificationCenter's errors, whose message is only `<domain> <code>`.
  static const notificationsError = 'notifications';

  /// UNErrorCodeNotificationsNotAllowed: the user turned the app's notifications off in iOS's settings.
  static const notAllowed = 'UNErrorDomain 1';

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
  Future<bool> schedule(DateTime at, String title, String body) async {
    try {
      await _host.scheduleReminder(at.millisecondsSinceEpoch, title, body);
      return true;
    } catch (error) {
      _failed('schedule', error);
      return error is! PlatformException || error.code != notificationsError || error.message != notAllowed;
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

  void _failed(String call, Object error) => _logger.warn(LogCategory.app, 'sideload reminder failed', {
    'call': call,
    'error': '${error.runtimeType}',
    // Only DeviceChannel.swift's own errors are known to carry nothing but the domain and code.
    if (error case PlatformException(code: notificationsError, :final message?)) ...{
      'code': notificationsError,
      'message': message,
    },
  });
}
