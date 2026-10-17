import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'log_event.dart';
import 'logger.dart';

/// Sends one NDJSON body; throws when the PC did not accept it.
typedef LogPoster = Future<void> Function(Uint8List body);

sealed class NetworkSinkState {
  const NetworkSinkState();
}

final class NetworkSinkIdle extends NetworkSinkState {
  const NetworkSinkIdle();

  @override
  bool operator ==(Object other) => other is NetworkSinkIdle;

  @override
  int get hashCode => 0;
}

final class NetworkSinkConnected extends NetworkSinkState {
  const NetworkSinkConnected();

  @override
  bool operator ==(Object other) => other is NetworkSinkConnected;

  @override
  int get hashCode => 1;
}

final class NetworkSinkFailing extends NetworkSinkState {
  const NetworkSinkFailing(this.reason);

  final String reason;

  @override
  bool operator ==(Object other) => other is NetworkSinkFailing && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'NetworkSinkFailing($reason)';
}

/// Batches events and hands them to `poster` (the app's HTTP POST to the PC) every `intervalMs`.
/// Events stay buffered until a post succeeds.
final class NetworkSink implements LogSink {
  NetworkSink({
    required this._poster,
    this.intervalMs = 500,
    this.maxBuffered = 10000,
    this.batchLimit = 2000,
    this.maxBackoffMs = 30000,
  });

  final LogPoster _poster;
  final double intervalMs;
  final int maxBuffered;
  final int batchLimit;
  final double maxBackoffMs;
  final List<LogEvent> _buffer = [];
  NetworkSinkState _state = const NetworkSinkIdle();
  Timer? _timer;
  int _generation = 0;
  bool _running = false;

  /// Test hook replacing the JSON encoding of one event.
  List<int> Function(LogEvent event)? encodeOverride;

  void Function(String session, int seq)? onAcknowledged;

  NetworkSinkState get state => _state;
  int get pending => _buffer.length;
  List<LogEvent> get bufferedForTesting => List.unmodifiable(_buffer);

  /// POSTs to `http://host:port/logs` like the Swift app's LogPoster: 3 s to connect, 10 s for the whole
  /// exchange, and only a 200 counts as delivered.
  static LogPoster httpPoster({
    required String host,
    required int port,
    Duration connectTimeout = const Duration(seconds: 3),
    Duration timeout = const Duration(seconds: 10),
  }) {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    return (body) async {
      Future<void> exchange() async {
        final request = await client.post(host, port, '/logs');
        request.persistentConnection = false;
        request.headers.contentType = ContentType('application', 'x-ndjson');
        request.contentLength = body.length;
        request.add(body);
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'log server replied ${response.statusCode}',
            uri: Uri(scheme: 'http', host: host, port: port, path: '/logs'),
          );
        }
      }

      await exchange().timeout(timeout);
    };
  }

  @override
  void receive(LogEvent event) => enqueue([event]);

  void enqueue(List<LogEvent> events) {
    _buffer.addAll(events);
    _trim();
  }

  /// Puts replayed events ahead of everything buffered, so the cap still drops the oldest first.
  void prepend(List<LogEvent> events) {
    _buffer.insertAll(0, events);
    _trim();
  }

  void _trim() {
    if (_buffer.length > maxBuffered) _buffer.removeRange(0, _buffer.length - maxBuffered);
  }

  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_generation;
    var delay = intervalMs;
    Future<void> tick() async {
      _timer = null;
      final sent = await flushOnce();
      // A stop() (and maybe a new start()) while the post was in flight retires this loop.
      if (generation != _generation) return;
      delay = nextDelay(sent: sent, current: delay, interval: intervalMs, cap: maxBackoffMs);
      _timer = Timer(Duration(microseconds: (delay * 1000).round()), tick);
    }

    _timer = Timer(Duration.zero, tick);
  }

  /// While the PC is unreachable, each failed post waits twice as long as the last, up to `cap`.
  static double nextDelay({
    required bool sent,
    required double current,
    required double interval,
    required double cap,
  }) {
    if (sent) return interval;
    final doubled = (current > interval ? current : interval) * 2;
    return doubled < cap ? doubled : cap;
  }

  void stop() {
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> flushOnce() async {
    final batch = _buffer.take(batchLimit).toList();
    if (batch.isEmpty) return true;
    final body = BytesBuilder(copy: false);
    final encoded = <LogEvent>[];
    final firstUnencodable = <String, int>{};
    for (final event in batch) {
      final List<int> line;
      try {
        line = encodeOverride?.call(event) ?? utf8.encode(event.encode());
      } catch (_) {
        final known = firstUnencodable[event.session];
        firstUnencodable[event.session] = known == null || event.seq < known ? event.seq : known;
        continue;
      }
      body.add(line);
      body.addByte(0x0A);
      encoded.add(event);
    }
    if (encoded.isNotEmpty) {
      try {
        await _poster(body.takeBytes());
      } catch (error) {
        _state = NetworkSinkFailing(error.toString());
        return false;
      }
      _state = const NetworkSinkConnected();
    }
    // Remove by identity: the buffer may have dropped or gained events while posting.
    final done = {for (final event in batch) '${event.session}#${event.seq}'};
    _buffer.removeWhere((event) => done.contains('${event.session}#${event.seq}'));
    // The watermark stops before an event that could not be sent, so a replay would still cover it.
    final latest = <String, int>{};
    for (final event in encoded) {
      final limit = firstUnencodable[event.session];
      if (limit != null && event.seq >= limit) continue;
      final known = latest[event.session];
      if (known == null || event.seq > known) latest[event.session] = event.seq;
    }
    final callback = onAcknowledged;
    if (callback != null) {
      for (final MapEntry(:key, :value) in latest.entries) {
        callback(key, value);
      }
    }
    return true;
  }
}
