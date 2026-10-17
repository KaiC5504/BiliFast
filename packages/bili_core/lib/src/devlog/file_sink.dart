import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'log_event.dart';
import 'logger.dart';

/// JSON-lines files per app session, pruned oldest first to stay under `maxTotalBytes`.
/// The live file `<session>.jsonl` is sealed as `<session>.<n>.jsonl` once it reaches a quarter of the
/// cap, so the live session is bounded too.
///
/// Writes are asynchronous and strictly ordered; [flush] resolves once everything received before it is on disk.
final class FileSink implements LogSink {
  FileSink._(this.directory, this._session, this._maxTotalBytes)
    : file = File('${directory.path}${Platform.pathSeparator}$_session.jsonl');

  final Directory directory;

  /// The live file.
  final File file;
  final String _session;
  final int _maxTotalBytes;
  RandomAccessFile? _handle;
  int _liveBytes = 0;
  int _dropped = 0;
  final List<Uint8List> _pending = [];
  bool _drainQueued = false;
  Future<void> _tail = Future<void>.value();

  static const exportName = 'BiliNative-logs.jsonl';

  static Future<FileSink> open({
    required Directory directory,
    required String session,
    int maxTotalBytes = 20 << 20,
  }) async {
    await directory.create(recursive: true);
    final sink = FileSink._(directory, session, maxTotalBytes);
    final handle = await sink.file.open(mode: FileMode.append);
    sink._handle = handle;
    sink._liveBytes = await handle.length();
    await sink._prune();
    return sink;
  }

  @override
  void receive(LogEvent event) {
    final String line;
    try {
      line = event.encode();
    } catch (_) {
      return;
    }
    _pending.add(utf8.encode('$line\n'));
    if (!_drainQueued) {
      _drainQueued = true;
      _serial(_drain).ignore();
    }
  }

  Future<void> flush() => _serial(_flushNow);

  /// Oldest first.
  Future<List<File>> sessionFiles() async {
    final entries = <(File, DateTime, String)>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = _basename(entity.path);
        if (!name.endsWith('.jsonl')) continue;
        try {
          entries.add((entity, (await entity.stat()).modified, name));
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException {
      return [];
    }
    entries.sort((lhs, rhs) {
      final byDate = lhs.$2.compareTo(rhs.$2);
      return byDate != 0 ? byDate : _numericCompare(lhs.$3, rhs.$3);
    });
    return [for (final entry in entries) entry.$1];
  }

  /// Concatenates every session file into one file for the share sheet.
  Future<File> exportFile() => _serial(() async {
    await _flushNow();
    final builder = BytesBuilder(copy: false);
    for (final each in await sessionFiles()) {
      try {
        builder.add(await each.readAsBytes());
      } on FileSystemException {
        continue;
      }
    }
    final output = _exportFile;
    await output.writeAsBytes(builder.takeBytes(), flush: true);
    return output;
  });

  /// Deletes every session file, the live one included, and the export; logging carries on into a fresh live file.
  Future<void> removeAllFiles() => _serial(() async {
    await _closeHandle();
    for (final each in [...await sessionFiles(), _exportFile]) {
      await _delete(each);
    }
    await _openLive();
  });

  Future<void> close() => _serial(_closeHandle);

  static Future<List<LogEvent>> readEvents(File file) async {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return [];
    }
    final events = <LogEvent>[];
    var start = 0;
    for (var index = 0; index <= bytes.length; index++) {
      if (index < bytes.length && bytes[index] != 0x0A) continue;
      if (index > start) {
        try {
          final event = LogEvent.decode(utf8.decode(Uint8List.sublistView(bytes, start, index)));
          if (event != null) events.add(event);
        } on FormatException {
          // A torn or corrupt line is skipped, like a failed decode in Swift.
        }
      }
      start = index + 1;
    }
    return events;
  }

  int get droppedLines => _dropped;

  /// Closes the handle but keeps it, so the next write fails the way a broken disk would.
  Future<void> closeHandleForTesting() => _serial(() async {
    try {
      await _handle?.close();
    } on FileSystemException {
      return;
    }
  });

  int get _rollBytes => _maxTotalBytes ~/ 4 > 1 ? _maxTotalBytes ~/ 4 : 1;

  File get _exportFile => File('${directory.parent.path}${Platform.pathSeparator}$exportName');

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  // A logger must never take the app down: write errors drop the lines and the file is reopened next time.
  Future<void> _drain() async {
    _drainQueued = false;
    final lines = List.of(_pending);
    _pending.clear();
    final chunk = BytesBuilder(copy: false);
    var count = 0;
    for (final line in lines) {
      final live = _liveBytes + chunk.length;
      if (live > 0 && live + line.length > _rollBytes) {
        await _write(chunk.takeBytes(), count);
        count = 0;
        await _roll();
      }
      chunk.add(line);
      count++;
    }
    if (count > 0) await _write(chunk.takeBytes(), count);
  }

  Future<void> _write(Uint8List bytes, int lines) async {
    if (bytes.isEmpty) return;
    if (_handle == null) await _openLive();
    final handle = _handle;
    if (handle == null) {
      _dropped += lines;
      return;
    }
    try {
      await handle.writeFrom(bytes);
      _liveBytes += bytes.length;
    } catch (_) {
      _dropped += lines;
      await _closeHandle();
    }
  }

  Future<void> _flushNow() async {
    try {
      await _handle?.flush();
    } on FileSystemException {
      return;
    }
  }

  Future<void> _closeHandle() async {
    final handle = _handle;
    _handle = null;
    try {
      await handle?.close();
    } on FileSystemException {
      return;
    }
  }

  Future<void> _openLive() async {
    try {
      final handle = await file.open(mode: FileMode.append);
      _handle = handle;
      _liveBytes = await handle.length();
    } on FileSystemException {
      _handle = null;
      _liveBytes = 0;
    }
  }

  Future<void> _roll() async {
    await _closeHandle();
    var index = 1;
    File sealed() => File('${directory.path}${Platform.pathSeparator}$_session.$index.jsonl');
    while (await sealed().exists()) {
      index++;
    }
    try {
      await file.rename(sealed().path);
    } on FileSystemException {
      await _delete(file);
    }
    await _openLive();
    await _prune();
  }

  /// Leaves room for the live file to grow to `rollBytes`, so the total never exceeds the cap.
  Future<void> _prune() async {
    final files = await sessionFiles();
    Future<int> size(File each) async {
      try {
        return await each.length();
      } on FileSystemException {
        return 0;
      }
    }

    final sizes = [for (final each in files) await size(each)];
    var total = sizes.fold(0, (sum, each) => sum + each);
    final target = _maxTotalBytes - _rollBytes;
    final liveName = _basename(file.path);
    for (var index = 0; index < files.length && total > target; index++) {
      if (_basename(files[index].path) == liveName) break;
      total -= sizes[index];
      await _delete(files[index]);
    }
  }

  static Future<void> _delete(File each) async {
    try {
      await each.delete();
    } on FileSystemException {
      return;
    }
  }
}

String _basename(String path) {
  final cut = path.lastIndexOf(RegExp(r'[/\\]'));
  return cut < 0 ? path : path.substring(cut + 1);
}

/// Digit runs compare by value, like Foundation's `.numeric` option: `s.2.jsonl` sorts before `s.10.jsonl`.
int _numericCompare(String a, String b) {
  var i = 0;
  var j = 0;
  bool isDigit(int unit) => unit >= 0x30 && unit <= 0x39;
  while (i < a.length && j < b.length) {
    final x = a.codeUnitAt(i);
    final y = b.codeUnitAt(j);
    if (isDigit(x) && isDigit(y)) {
      final startI = i;
      final startJ = j;
      while (i < a.length && isDigit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && isDigit(b.codeUnitAt(j))) {
        j++;
      }
      final left = BigInt.parse(a.substring(startI, i));
      final right = BigInt.parse(b.substring(startJ, j));
      final byValue = left.compareTo(right);
      if (byValue != 0) return byValue;
      continue;
    }
    if (x != y) return x.compareTo(y);
    i++;
    j++;
  }
  return (a.length - i).compareTo(b.length - j);
}
