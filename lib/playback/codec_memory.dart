import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';

/// Codec kinds the player refused on this phone, so they are not tried first again (port of CodecMemory.swift, which
/// kept them in UserDefaults `playback.failedCodecs`), as a small JSON file in the support folder.
final class CodecMemory {
  /// Kept in memory only, for tests and for platforms without a support folder.
  CodecMemory({Logger? logger}) : this._(null, const {}, false, logger ?? Logger.shared);

  CodecMemory._(this._path, Set<String> failed, this._hev1LabelsHoldHEV1, this._logger) {
    _failed.addAll(failed);
  }

  /// [path] null keeps the memory in memory. A file that can't be read is set aside as `.bad` and nothing is
  /// remembered; entries of the wrong type are dropped.
  static Future<CodecMemory> load(String? path, {Logger? logger}) async {
    final log = logger ?? Logger.shared;
    if (path == null) return CodecMemory._(null, const {}, false, log);
    final file = File(path);
    if (!await file.exists()) return CodecMemory._(path, const {}, false, log);
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) throw const FormatException('not an object');
      final failed = json['failedCodecs'];
      return CodecMemory._(
        path,
        {if (failed is List) ...failed.whereType<String>()},
        json['hev1LabelsHoldHEV1'] == true,
        log,
      );
    } catch (error) {
      log.warn(LogCategory.app, 'codec memory unreadable, starting empty', {'error': _reason(error)});
    }
    try {
      await file.rename('$path.bad');
    } catch (error) {
      log.warn(LogCategory.app, 'codec memory not set aside', {'error': _reason(error)});
    }
    return CodecMemory._(path, const {}, false, log);
  }

  static const fallbackOrder = [VideoCodec.hevc, VideoCodec.av1, VideoCodec.avc];

  final String? _path;
  final Logger _logger;
  final Set<String> _failed = {};
  bool _hev1LabelsHoldHEV1;
  Future<void> _writing = Future.value();

  Set<String> get failedKinds => Set.unmodifiable(_failed);

  List<VideoCodec> order({required VideoCodec preferred}) => [
        preferred,
        ...fallbackOrder.where((codec) => codec != preferred),
      ].where((codec) => !_failed.contains(codec.name)).toList();

  void markFailed(String kind) {
    if (_failed.add(kind)) _save();
  }

  /// Set once a stream labelled hev1 held a real hev1 sample entry. Direct mode cannot rename one, so it then
  /// skips hev1 labels before fetching anything; until then it reads the bytes, which can be hvc1.
  bool get hev1LabelsHoldHEV1 => _hev1LabelsHoldHEV1;

  void noteHEV1Entry() {
    if (_hev1LabelsHoldHEV1) return;
    _hev1LabelsHoldHEV1 = true;
    _save();
  }

  void reset() {
    if (_failed.isEmpty && !_hev1LabelsHoldHEV1) return;
    _failed.clear();
    _hev1LabelsHoldHEV1 = false;
    _save();
  }

  Map<String, Object?> toJson() => {
    'failedCodecs': (_failed.toList()..sort()),
    if (_hev1LabelsHoldHEV1) 'hev1LabelsHoldHEV1': true,
  };

  void _save() {
    final path = _path;
    if (path == null) return;
    final text = jsonEncode(toJson());
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
      _logger.warn(LogCategory.app, 'codec memory not saved', {'error': _reason(error)});
    }
  }

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;

  /// The error without the text that failed: a FormatException's toString quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };
}
