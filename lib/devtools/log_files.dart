import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../playback/playback_setup.dart';

/// The log kept on the phone (BiliNative `DevLogSetup`'s FileSink, the last 20 MB), for 设置's 清除日志 and
/// 开发者's 导出日志.
abstract interface class LogFiles {
  /// Attaches the file sink to `Logger.shared` where there is a place to keep it.
  factory LogFiles.platform() {
    final path = logDirectoryPath();
    return path == null ? const NoLogFiles() : FileLogFiles.attach(Directory(path), logger: Logger.shared);
  }

  Future<void> clear();

  /// The file to share, or null when nothing is logged. Throws when the files can't be read or written.
  Future<String?> export();
}

/// iPhone: `Library/Caches/logs`, as the Swift app kept it. Windows: `logs` beside the support files.
String? logDirectoryPath() {
  if (Platform.isIOS) {
    final home = Platform.environment['HOME'];
    return home == null ? null : '$home/Library/Caches/logs';
  }
  if (Platform.isWindows) return supportFilePath('logs');
  return null;
}

/// Tests, and platforms without a support folder.
class NoLogFiles implements LogFiles {
  const NoLogFiles();

  @override
  Future<void> clear() async {}

  @override
  Future<String?> export() async => null;
}

/// bili_core's [FileSink] on a logger. Writes go out asynchronously and the export is put together on another
/// isolate, so neither holds up a frame; a disk that fails is logged once and logging carries on without it.
final class FileLogFiles implements LogFiles, LogSink {
  FileLogFiles._(this.directory, this._logger, this._maxTotalBytes);

  /// Starts at once: events logged while the files open are kept and written first.
  factory FileLogFiles.attach(Directory directory, {required Logger logger, int maxTotalBytes = maxBytes}) {
    final files = FileLogFiles._(directory, logger, maxTotalBytes);
    logger.add(files);
    files._opening = files._open();
    return files;
  }

  static const maxBytes = 20 << 20;
  static const exportName = 'BiliFast-logs.jsonl';

  /// Events held while the files open; opening takes milliseconds, so the cap only matters on a stuck disk.
  static const earlyLimit = 2000;

  final Directory directory;
  final Logger _logger;
  final int _maxTotalBytes;
  late final Future<FileSink?> _opening;
  final List<LogEvent> _early = [];
  FileSink? _sink;
  bool _unavailable = false;
  bool _reportedDrops = false;

  File get exportFile => File('${directory.parent.path}${Platform.pathSeparator}$exportName');

  /// Completes once the files are open, or have failed to.
  Future<void> get ready => _opening;

  @visibleForTesting
  FileSink? get sink => _sink;

  @override
  void receive(LogEvent event) {
    final sink = _sink;
    if (sink == null) {
      if (!_unavailable && _early.length < earlyLimit) _early.add(event);
      return;
    }
    sink.receive(event);
    if (!_reportedDrops && sink.droppedLines > 0) {
      _reportedDrops = true;
      // Not from inside the logger's delivery, which is still handing this event to the other sinks.
      scheduleMicrotask(() => _logger.warn(LogCategory.app, 'log file write failed, lines dropped',
          {'dropped': sink.droppedLines, 'directory': directory.path}));
    }
  }

  Future<FileSink?> _open() async {
    try {
      final sink = await FileSink.open(directory: directory, session: _logger.session, maxTotalBytes: _maxTotalBytes);
      for (final event in _early) {
        sink.receive(event);
      }
      _early.clear();
      _sink = sink;
      return sink;
    } catch (error) {
      _unavailable = true;
      _early.clear();
      _logger.remove(this);
      _logger.warn(LogCategory.app, 'log files unavailable', {'error': '$error', 'directory': directory.path});
      return null;
    }
  }

  @override
  Future<void> clear() async {
    final sink = await _opening;
    if (sink == null) return;
    await sink.removeAllFiles();
    try {
      await exportFile.delete();
    } on FileSystemException {
      return;
    }
  }

  @override
  Future<String?> export() async {
    final sink = await _opening;
    if (sink == null) return null;
    try {
      await sink.flush();
      // Each file is read only up to the length it had once flushed, so a write landing meanwhile can't tear it.
      final parts = <(String, int)>[];
      for (final file in await sink.sessionFiles()) {
        try {
          parts.add((file.path, await file.length()));
        } on FileSystemException {
          continue;
        }
      }
      final target = exportFile.path;
      final written = await _concatenate(parts, target);
      if (written > 0) return target;
      await _deleteQuietly(target);
      return null;
    } catch (error) {
      _logger.warn(LogCategory.app, 'log export failed', {'error': '$error'});
      rethrow;
    }
  }

  /// Detaches from the logger and closes the live file.
  Future<void> close() async {
    _logger.remove(this);
    await (await _opening)?.close();
  }

  // Static, so the closure sent to the other isolate carries only these two values.
  static Future<int> _concatenate(List<(String, int)> parts, String target) =>
      Isolate.run(() => concatenateLogFiles(parts, target));

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      return;
    }
  }
}

/// Writes each file's whole lines, up to its given length, into [target], oldest first; returns the bytes written.
/// A file that has gone since it was listed is skipped.
@visibleForTesting
int concatenateLogFiles(List<(String, int)> parts, String target) {
  final output = File(target).openSync(mode: FileMode.write);
  var written = 0;
  try {
    for (final (path, length) in parts) {
      final Uint8List bytes;
      try {
        final input = File(path).openSync();
        try {
          bytes = input.readSync(length);
        } finally {
          input.closeSync();
        }
      } on FileSystemException {
        continue;
      }
      final end = bytes.lastIndexOf(0x0A) + 1;
      if (end == 0) continue;
      output.writeFromSync(bytes, 0, end);
      written += end;
    }
  } finally {
    output.closeSync();
  }
  return written;
}
