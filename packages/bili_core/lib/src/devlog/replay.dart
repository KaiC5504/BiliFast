import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'file_sink.dart';
import 'log_event.dart';

/// Highest sequence number per session that the PC confirmed, so a crashed session's tail can be resent.
final class AckStore {
  AckStore._(this.file, this._state);

  final File file;
  final Map<String, int> _state;
  Future<void> _writes = Future<void>.value();

  static Future<AckStore> load(File file) async {
    final state = <String, int>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        for (final MapEntry(:key, :value) in decoded.entries) {
          if (value is int) state[key] = value;
        }
      }
    } on FileSystemException {
      // Missing: start empty.
    } on FormatException {
      // Corrupt: start empty, like the Swift store.
    }
    return AckStore._(file, state);
  }

  int lastSeq(String session) => _state[session] ?? 0;

  /// Updates memory at once; the returned future completes when this snapshot is on disk.
  Future<void> record(String session, int seq) {
    if (seq <= lastSeq(session)) return _writes;
    _state[session] = seq;
    final snapshot = jsonEncode(_state);
    // Chained so a slower, older snapshot cannot land after a newer one.
    return _writes = _writes.then((_) => _writeAtomically(snapshot));
  }

  Future<void> _writeAtomically(String contents) async {
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsString(contents, flush: true);
      await temp.rename(file.path);
    } on FileSystemException {
      return;
    }
  }
}

abstract final class ReplayPlanner {
  /// Events the PC has not confirmed, oldest first, at most `limit` of them (the newest win). Files are read
  /// newest first and reading stops once `limit` is reached. The current session is skipped unless `current`
  /// gives the seq span to resend: after the PC's last confirmation, up to the new sink's cut.
  static Future<List<LogEvent>> unsent({
    required List<File> files,
    required String currentSession,
    required AckStore ack,
    ({int after, int through})? current,
    int? limit,
  }) async {
    final chunks = <List<LogEvent>>[];
    var count = 0;
    for (final file in files.reversed) {
      if (limit != null && count >= limit) break;
      final isCurrent = _sessionName(file) == currentSession;
      if (isCurrent && current == null) continue;
      final events = (await FileSink.readEvents(file)).where((event) {
        if (event.session == currentSession) {
          return current != null && event.seq > current.after && event.seq <= current.through;
        }
        return event.seq > ack.lastSeq(event.session);
      }).toList();
      chunks.add(events);
      count += events.length;
    }
    final all = [for (final chunk in chunks.reversed) ...chunk];
    return limit == null || all.length <= limit ? all : all.sublist(all.length - limit);
  }

  /// `<session>.jsonl` or a sealed segment `<session>.<n>.jsonl`.
  static String _sessionName(File file) {
    final path = file.path;
    var name = path.substring(path.lastIndexOf(RegExp(r'[/\\]')) + 1);
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    final first = name.indexOf('.');
    return first < 0 ? name : name.substring(0, first);
  }
}
