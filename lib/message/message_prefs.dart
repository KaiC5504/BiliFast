import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';

/// 消息设置's 消息提醒, kept on the phone as a small JSON file in the support folder (`message_prefs.json`).
class MessagePrefs {
  MessagePrefs._(this._path, this._badgeOn, this._logger);

  /// Kept in memory only, for tests and for platforms without a support folder.
  factory MessagePrefs.memory({bool badgeOn = true, Logger? logger}) =>
      MessagePrefs._(null, badgeOn, logger ?? Logger.shared);

  /// [path] null keeps it in memory. A file that can't be read is set aside as `.bad` and the defaults apply; a value
  /// of the wrong type falls back to its default, logged by its key.
  static Future<MessagePrefs> load(String? path, {Logger? logger}) async {
    final log = logger ?? Logger.shared;
    if (path == null) return MessagePrefs._(null, true, log);
    final file = File(path);
    if (!await file.exists()) return MessagePrefs._(path, true, log);
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) throw const FormatException('not an object');
      final badgeOn = json['badgeOn'];
      if (badgeOn != null && badgeOn is! bool) {
        log.warn(LogCategory.app, 'message prefs value ignored', {'key': 'badgeOn'});
      }
      return MessagePrefs._(path, badgeOn is bool ? badgeOn : true, log);
    } catch (error) {
      log.warn(LogCategory.app, 'message prefs unreadable, using defaults', {'error': _reason(error)});
    }
    try {
      await file.rename('$path.bad');
    } catch (error) {
      log.warn(LogCategory.app, 'message prefs not set aside', {'error': _reason(error)});
    }
    return MessagePrefs._(path, true, log);
  }

  final String? _path;
  final Logger _logger;
  bool _badgeOn;
  Future<void> _writing = Future.value();

  /// 消息提醒: the red badges show at all.
  bool get badgeOn => _badgeOn;

  set badgeOn(bool value) {
    if (value == _badgeOn) return;
    _badgeOn = value;
    final path = _path;
    if (path == null) return;
    final text = jsonEncode({'badgeOn': value});
    // One write after another, so an older state never lands last.
    _writing = _writing.then((_) => _write(path, text));
  }

  Future<void> _write(String path, String text) async {
    try {
      await File(path).parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'message prefs not saved', {'error': _reason(error)});
    }
  }

  /// The error without the text that failed: a FormatException's toString quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;
}
