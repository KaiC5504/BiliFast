import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';

/// A sideloaded install's answers, kept in the support folder's `sideload.json`: `{"reminderAnswered": bool,
/// "reminderOn": bool, "announced": "1.3.0-8", "warnedOn": "2026-11-04"}`. [load] reads the file once, before the
/// model reads any of it; until then, and in memory, everything starts unanswered.
class SideloadStore {
  SideloadStore.memory({Logger? logger}) : this.file(null, logger: logger);

  /// [path] null keeps the answers in memory only.
  SideloadStore.file(this._path, {Logger? logger}) : _logger = logger ?? Logger.shared;

  final String? _path;
  final Logger _logger;
  Future<void>? _loading;
  Future<void> _writing = Future.value();

  bool _reminderAnswered = false;
  bool _reminderOn = false;
  String? _announced;
  String? _warnedOn;

  /// Whether the launch question about the reminder has had its answer (or 设置's switch was used).
  bool get reminderAnswered => _reminderAnswered;
  set reminderAnswered(bool value) {
    if (value == _reminderAnswered) return;
    _reminderAnswered = value;
    _save();
  }

  bool get reminderOn => _reminderOn;
  set reminderOn(bool value) {
    if (value == _reminderOn) return;
    _reminderOn = value;
    _save();
  }

  /// The release whose alert was last shown, as `<version>-<build>`.
  String? get announced => _announced;
  set announced(String? value) {
    if (value == _announced) return;
    _announced = value;
    _save();
  }

  /// The local calendar day of the last expiry alert, as `yyyy-mm-dd`.
  String? get warnedOn => _warnedOn;
  set warnedOn(String? value) {
    if (value == _warnedOn) return;
    _warnedOn = value;
    _save();
  }

  /// Reads the file the first time it's called; later calls wait for that read. An unreadable file starts
  /// unanswered, logged, and is replaced by the next answer.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final path = _path;
    if (path == null) return;
    final file = File(path);
    try {
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) throw const FormatException('not an object');
      _reminderAnswered = json['reminderAnswered'] == true;
      _reminderOn = json['reminderOn'] == true;
      _announced = json['announced'] is String ? json['announced']! as String : null;
      _warnedOn = json['warnedOn'] is String ? json['warnedOn']! as String : null;
    } catch (error) {
      _logger.warn(LogCategory.app, 'sideload answers unreadable, starting unanswered', {'error': _reason(error)});
    }
  }

  Map<String, Object?> toJson() => {
    'reminderAnswered': _reminderAnswered,
    'reminderOn': _reminderOn,
    'announced': ?_announced,
    'warnedOn': ?_warnedOn,
  };

  void _save() {
    final path = _path;
    if (path == null) return;
    final text = jsonEncode(toJson());
    // One write after another, so an older answer never lands last.
    _writing = _writing.then((_) => _write(path, text));
  }

  Future<void> _write(String path, String text) async {
    try {
      await File(path).parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'sideload answers not saved', {'error': _reason(error)});
    }
  }

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;

  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };
}
