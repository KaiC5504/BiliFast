import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import 'danmaku_settings.dart';

/// The 弹幕设置 values for every video, kept as `danmaku_settings.json` in the support folder.
class DanmakuSettingsStore extends ValueNotifier<DanmakuSettings> {
  DanmakuSettingsStore.memory([super.value = const DanmakuSettings()]) : _path = null, _logger = Logger.shared;

  DanmakuSettingsStore._(this._path, this._logger, super.value);

  final String? _path;
  final Logger _logger;
  Future<void> _writing = Future.value();
  bool _writeQueued = false;

  /// [path] null keeps the values in memory. An unreadable file is set aside as `.bad` and the defaults apply,
  /// logged.
  static Future<DanmakuSettingsStore> load(String? path, {Logger? logger}) async {
    final log = logger ?? Logger.shared;
    if (path == null) return DanmakuSettingsStore._(null, log, const DanmakuSettings());
    final file = File(path);
    if (!await file.exists()) return DanmakuSettingsStore._(path, log, const DanmakuSettings());
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) throw const FormatException('not an object');
      return DanmakuSettingsStore._(path, log, DanmakuSettings.fromJson(json));
    } catch (error) {
      log.warn(LogCategory.app, 'danmaku settings unreadable, using defaults', {'error': _reason(error)});
    }
    try {
      await file.rename('$path.bad');
    } catch (error) {
      log.warn(LogCategory.app, 'danmaku settings not set aside', {'error': _reason(error)});
    }
    return DanmakuSettingsStore._(path, log, const DanmakuSettings());
  }

  /// Shows at once and is saved.
  void update(DanmakuSettings next) {
    if (next == value) return;
    value = next;
    final path = _path;
    if (path == null || _writeQueued) return;
    // A slider drag updates every frame: the changes made before the queued write starts go out as one.
    _writeQueued = true;
    _writing = _writing.then((_) {
      _writeQueued = false;
      return _write(path, jsonEncode(value.toJson()));
    });
  }

  /// 重置弹幕设置.
  void reset() => update(const DanmakuSettings());

  /// Waits for the writes made so far; for tests.
  Future<void> settle() async {
    while (true) {
      final writing = _writing;
      await writing;
      if (identical(writing, _writing)) return;
    }
  }

  Future<void> _write(String path, String text) async {
    try {
      await File(path).parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'danmaku settings not saved', {'error': _reason(error)});
    }
  }

  /// The error without the text that failed: a FormatException's toString quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };
}
