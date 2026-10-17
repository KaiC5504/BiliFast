import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'byte_range.dart';
import 'cancel.dart';
import 'session.dart';

/// Serves each session's tracks to the player as plain files on 127.0.0.1, answering Range requests
/// from the session's segment jobs.
class LocalServer {
  HttpServer? _server;
  final _sessions = <String, RipperSession>{};
  int _next = 0;
  void Function(String message)? log;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    _server = server;
    server.listen(_handle);
  }

  String add(RipperSession session) {
    final id = 's${_next++}';
    _sessions[id] = session;
    return id;
  }

  void remove(String id) => _sessions.remove(id)?.close();

  String url(String id, Track t) => 'http://127.0.0.1:${_server!.port}/$id/${t.name}.m4s';

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final parts = req.uri.pathSegments;
    final session = parts.length == 2 ? _sessions[parts[0]] : null;
    final track = parts.length == 2 ? Track.values.where((t) => '${t.name}.m4s' == parts[1]).firstOrNull : null;
    if (session == null || track == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final reader = session.beginRead(track);
    unawaited(res.done.then((_) {}, onError: (_) => reader.cancel()));
    try {
      await reader.guard(session.ensureHeaders(track));
      final total = session.total(track);
      final requested = _parseRange(req.headers.value(HttpHeaders.rangeHeader), total);
      if (requested == null) {
        res
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await res.close();
        return;
      }
      final (range, partial) = requested;
      res.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
      res.headers
        ..contentType = ContentType('video', 'mp4')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = range.length;
      if (partial) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes ${range.start}-${range.end}/$total');
      log?.call('${track.name} ${range.start}-${range.end}');
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      await _stream(session, track, range, res, reader);
      await res.close();
    } catch (e) {
      if (e is! CancelledException) log?.call('${track.name} failed: $e');
      // Closing short of Content-Length breaks the connection, which mpv treats as a network error and retries.
      try {
        await res.close();
      } catch (_) {}
    } finally {
      reader.dispose();
    }
  }

  Future<void> _write(HttpResponse res, Uint8List bytes, CancelToken reader) async {
    res.add(bytes);
    await reader.guard(res.flush());
  }

  Future<void> _stream(RipperSession session, Track t, ByteRange range, HttpResponse res, CancelToken reader) async {
    var pos = range.start;
    final header = session.header(t);
    if (pos < header.length) {
      final end = range.end < header.length - 1 ? range.end : header.length - 1;
      await _write(res, Uint8List.sublistView(header, pos, end + 1), reader);
      pos = end + 1;
    }
    while (pos <= range.end) {
      reader.throwIfCancelled();
      final index = session.segmentAt(t, pos);
      if (index == null) {
        final bytes = await session.fetchLoose(t, ByteRange(pos, range.end), reader);
        await _write(res, bytes, reader);
        return;
      }
      final job = session.segmentForPlayer(t, index);
      job.readers++;
      try {
        var chunkIndex = 0;
        var chunkStart = job.segment.range.start;
        while (true) {
          while (chunkIndex < job.chunks.length) {
            final chunk = job.chunks[chunkIndex++];
            final chunkEnd = chunkStart + chunk.length - 1;
            if (chunkEnd >= pos && chunkStart <= range.end) {
              final from = pos - chunkStart;
              final to = (range.end < chunkEnd ? range.end : chunkEnd) - chunkStart + 1;
              await _write(res, Uint8List.sublistView(chunk, from, to), reader);
              pos = chunkStart + to;
            }
            chunkStart = chunkEnd + 1;
            if (pos > range.end) return;
          }
          if (job.done) {
            if (job.error != null) throw job.error!;
            break;
          }
          await reader.guard(job.changed);
        }
      } finally {
        job.readers--;
      }
      pos = job.segment.range.end + 1;
    }
  }

  /// `bytes=a-b`, `bytes=a-` or `bytes=-n`; null when unsatisfiable. No header is the whole file.
  static (ByteRange, bool)? _parseRange(String? header, int total) {
    if (header == null) return (ByteRange(0, total - 1), false);
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (m == null) return (ByteRange(0, total - 1), false);
    final a = m.group(1)!, b = m.group(2)!;
    int start, end;
    if (a.isEmpty) {
      final n = int.tryParse(b) ?? 0;
      if (n <= 0) return null;
      start = total - n < 0 ? 0 : total - n;
      end = total - 1;
    } else {
      start = int.parse(a);
      end = b.isEmpty ? total - 1 : int.parse(b);
      if (end >= total) end = total - 1;
    }
    if (start >= total || end < start) return null;
    return (ByteRange(start, end), true);
  }

  Future<void> stop() async {
    for (final s in _sessions.values) {
      s.close();
    }
    _sessions.clear();
    await _server?.close(force: true);
    _server = null;
  }
}
