import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';

import '../../playback/playback_setup.dart' show supportFilePath;

/// A room's 弹, kept between rooms as a small JSON file in the support folder (`live_player.json`); the video page's
/// own 弹 stays apart in [PlayerPrefs].
class LivePlayerPrefs {
  LivePlayerPrefs._(this._path, this._danmakuOn, this._logger);

  factory LivePlayerPrefs.memory({bool danmakuOn = true, Logger? logger}) =>
      LivePlayerPrefs._(null, danmakuOn, logger ?? Logger.shared);

  /// Read on first use rather than at launch: a missing or unreadable file gives the default (on). Under `flutter test`
  /// it stays in memory, since the PC's support folder is the real one.
  static LivePlayerPrefs get shared =>
      _shared ??= _load(Platform.environment.containsKey('FLUTTER_TEST') ? null : supportFilePath('live_player.json'));
  static set shared(LivePlayerPrefs prefs) => _shared = prefs;
  static LivePlayerPrefs? _shared;

  static LivePlayerPrefs _load(String? path, {Logger? logger}) {
    final log = logger ?? Logger.shared;
    if (path == null) return LivePlayerPrefs._(null, true, log);
    try {
      final file = File(path);
      if (!file.existsSync()) return LivePlayerPrefs._(path, true, log);
      final json = jsonDecode(file.readAsStringSync());
      final on = json is Map<String, Object?> ? json['danmakuOn'] : null;
      if (on is! bool) log.warn(LogCategory.app, 'live player prefs value ignored', {'key': 'danmakuOn'});
      return LivePlayerPrefs._(path, on is bool ? on : true, log);
    } catch (error) {
      log.warn(LogCategory.app, 'live player prefs unreadable, using defaults', {'error': '${error.runtimeType}'});
      return LivePlayerPrefs._(path, true, log);
    }
  }

  /// [path] null keeps it in memory.
  static LivePlayerPrefs loadFrom(String? path, {Logger? logger}) => _load(path, logger: logger);

  final String? _path;
  final Logger _logger;
  bool _danmakuOn;
  Future<void> _writing = Future.value();

  bool get danmakuOn => _danmakuOn;

  set danmakuOn(bool value) {
    if (value == _danmakuOn) return;
    _danmakuOn = value;
    final path = _path;
    if (path == null) return;
    final text = jsonEncode({'danmakuOn': value});
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
      _logger.warn(LogCategory.app, 'live player prefs not saved', {'error': '${error.runtimeType}'});
    }
  }

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;
}
