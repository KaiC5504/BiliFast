import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

final class _Offline implements Exception {}

final class _Unencodable implements Exception {}

LogEvent _event(int seq) =>
    LogEvent(t: 0, seq: seq, session: 's', level: LogLevel.info, cat: LogCategory.app, msg: 'm$seq');

List<String> _lines(Uint8List body) => utf8.decode(body).split('\n').where((line) => line.isNotEmpty).toList();

void main() {
  test('retries until the poster succeeds and acknowledges', () async {
    var attempts = 0;
    final bodies = <Uint8List>[];
    final sink = NetworkSink(poster: (data) async {
      attempts += 1;
      if (attempts == 1) throw _Offline();
      bodies.add(data);
    });
    final acked = <String, int>{};
    sink.onAcknowledged = (session, seq) => acked[session] = seq;
    sink.enqueue([_event(1), _event(2)]);

    final first = await sink.flushOnce();
    expect(first, isFalse);
    expect(sink.pending, 2);
    expect(sink.state, isA<NetworkSinkFailing>());

    final second = await sink.flushOnce();
    expect(second, isTrue);
    expect(sink.pending, 0);
    expect(sink.state, const NetworkSinkConnected());
    expect(_lines(bodies[0]).length, 2);
    expect(acked['s'], 2);
  });

  test('non-finite field is delivered and acknowledged', () async {
    final bodies = <Uint8List>[];
    final sink = NetworkSink(poster: (data) async => bodies.add(data));
    final acked = <String, int>{};
    sink.onAcknowledged = (session, seq) => acked[session] = seq;
    sink.enqueue([
      const LogEvent(
        t: 0,
        seq: 7,
        session: 's',
        level: LogLevel.info,
        cat: LogCategory.engine,
        msg: 'inf',
        f: {'v': LogDouble(double.infinity)},
      ),
    ]);
    final ok = await sink.flushOnce();
    expect(ok, isTrue);
    expect(bodies.length, 1);
    expect(utf8.decode(bodies[0]), contains('"inf"'));
    expect(acked['s'], 7);
  });

  test('unencodable event is never acknowledged', () async {
    final bodies = <Uint8List>[];
    final sink = NetworkSink(poster: (data) async => bodies.add(data));
    sink.encodeOverride = (event) {
      if (event.seq == 2) throw _Unencodable();
      return utf8.encode(event.encode());
    };
    final acked = <String, int>{};
    sink.onAcknowledged = (session, seq) => acked[session] = seq;
    sink.enqueue([_event(1), _event(2), _event(3)]);
    final ok = await sink.flushOnce();
    expect(ok, isTrue);
    expect(_lines(bodies[0]).length, 2);
    expect(sink.pending, 0);
    expect(acked['s'], 1);
  });

  test('prepend goes ahead of live events and the cap drops the oldest', () {
    final sink = NetworkSink(poster: (_) async {}, maxBuffered: 4);
    sink.enqueue([_event(10), _event(11)]);
    sink.prepend([_event(1), _event(2), _event(3)]);
    expect(sink.pending, 4);
    expect(sink.bufferedForTesting.map((e) => e.seq), [2, 3, 10, 11]);
  });

  test('retry delay doubles to the cap and resets on success', () {
    var delay = 500.0;
    final seen = <double>[];
    for (var i = 0; i < 8; i++) {
      delay = NetworkSink.nextDelay(sent: false, current: delay, interval: 500, cap: 30000);
      seen.add(delay);
    }
    expect(seen, [1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000]);
    expect(NetworkSink.nextDelay(sent: true, current: delay, interval: 500, cap: 30000), 500);
  });

  test('buffer cap drops the oldest', () async {
    final bodies = <Uint8List>[];
    final sink = NetworkSink(poster: (data) async => bodies.add(data), maxBuffered: 3);
    sink.enqueue([for (var seq = 1; seq <= 5; seq++) _event(seq)]);
    expect(sink.pending, 3);
    await sink.flushOnce();
    final seqs = _lines(bodies[0]).map((line) => LogEvent.decode(line)?.seq).nonNulls;
    expect(seqs, [3, 4, 5]);
  });

  // Not in the Swift suite (its poster lives in the app): the dart:io poster against a loopback server.
  test('HTTP poster sends NDJSON to /logs and fails on a non-200 reply', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <(String, String, String?, String)>[];
    var status = 200;
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received.add((request.method, request.uri.path, request.headers.contentType?.mimeType, body));
      request.response.statusCode = status;
      request.response.write('ok');
      await request.response.close();
    });

    final poster = NetworkSink.httpPoster(host: InternetAddress.loopbackIPv4.address, port: server.port);
    final sink = NetworkSink(poster: poster);
    sink.enqueue([_event(1), _event(2)]);
    expect(await sink.flushOnce(), isTrue);
    expect(received.single.$1, 'POST');
    expect(received.single.$2, '/logs');
    expect(received.single.$3, 'application/x-ndjson');
    expect(received.single.$4.split('\n').where((l) => l.isNotEmpty).map((l) => LogEvent.decode(l)?.seq), [1, 2]);

    status = 500;
    sink.enqueue([_event(3)]);
    expect(await sink.flushOnce(), isFalse);
    expect(sink.pending, 1);
    expect(sink.state, isA<NetworkSinkFailing>());
  });

  test('start posts on its own and stop ends the loop', () async {
    final bodies = <Uint8List>[];
    final sink = NetworkSink(poster: (data) async => bodies.add(data), intervalMs: 10);
    sink.start();
    sink.receive(_event(1));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    sink.stop();
    expect(bodies, isNotEmpty);
    expect(sink.pending, 0);
    final posts = bodies.length;
    sink.receive(_event(2));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bodies.length, posts);
    expect(sink.pending, 1);
  });
}
