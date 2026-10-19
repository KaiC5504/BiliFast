import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import 'danmaku_settings.dart';

/// The 弹幕设置 values for every video, kept as `danmaku_settings.json` in the support folder.
// Contracts stub: slice 5's feed agent writes the file side.
class DanmakuSettingsStore extends ValueNotifier<DanmakuSettings> {
  DanmakuSettingsStore.memory([super.value = const DanmakuSettings()]) : _path = null;

  // ignore: unused_field
  final String? _path;

  /// [path] null keeps the values in memory. An unreadable file falls back to the defaults, logged.
  static Future<DanmakuSettingsStore> load(String? path, {Logger? logger}) async => DanmakuSettingsStore.memory();

  /// Shows at once and is saved.
  void update(DanmakuSettings next) => value = next;

  /// 重置弹幕设置.
  void reset() => update(const DanmakuSettings());
}
