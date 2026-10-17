import 'dart:async';

import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';
import 'support/loopback_server.dart';

void main() {
  late LoopbackServer server;
  final range = ByteRange(0, 99999);

  setUp(() async {
    server = await LoopbackServer.start({
      '/complete': const Complete(100000),
      '/trickle': const Trickle(50 << 20),
      '/hang': const Hang(),
      '/drop': const DropFirst(100000),
    });
  });

  tearDown(() => server.stop());

  Future<List<int>> collect(Stream<List<int>> body) async => [for (final chunk in await body.toList()) ...chunk];

  test('sends the Range and its headers and streams a 206 body', () async {
    final transport = IoRangeTransport(headers: {'User-Agent': 'Safari', 'Referer': 'https://www.bilibili.com/'});
    addTearDown(transport.close);
    final response = await transport.fetch(server.url('/complete'), range);
    expect(response.status, 206);
    expect(response.headers['content-range'], 'bytes 0-99999/100000');
    expect(await collect(response.body), LoopbackServer.pattern(0, 99999));
    final sent = server.headers('/complete').single;
    expect(sent['range'], 'bytes=0-99999');
    expect(sent['user-agent'], 'Safari');
    expect(sent['referer'], 'https://www.bilibili.com/');
    expect(sent.containsKey('accept-encoding'), isFalse);
    expect(transport.name, 'dart:io');
  });

  test('cancelling while waiting for the first byte throws at once and closes the socket', () async {
    final transport = IoRangeTransport();
    addTearDown(transport.close);
    final cancel = CancelToken();
    final fetch = transport.fetch(server.url('/hang'), range, cancel: cancel);
    expect(await eventually(() => server.requests('/hang') == 1), isTrue);
    final clock = Stopwatch()..start();
    cancel.cancel();
    await expectLater(fetch, throwsA(isA<CancelledException>()));
    expect(clock.elapsedMilliseconds, lessThan(500));
    expect(await eventually(() => server.closes('/hang') == 1), isTrue);
  });

  test('an already cancelled token throws without a request', () async {
    final transport = IoRangeTransport();
    addTearDown(transport.close);
    final cancel = CancelToken()..cancel();
    await expectLater(transport.fetch(server.url('/hang'), range, cancel: cancel), throwsA(isA<CancelledException>()));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.requests('/hang'), 0);
  });

  test('cancelling the body mid-way frees the connection at once', () async {
    // One connection per host: the second request can only start once the first gave its connection back.
    final transport = IoRangeTransport(connectionsPerHost: 1);
    addTearDown(transport.close);
    final response = await transport.fetch(server.url('/trickle'), ByteRange(0, (50 << 20) - 1));
    var received = 0;
    final subscription = response.body.listen((chunk) => received += chunk.length);
    expect(await eventually(() => received >= 4096), isTrue);
    final clock = Stopwatch()..start();
    await subscription.cancel();
    final next = await transport.fetch(server.url('/complete'), range).timeout(const Duration(seconds: 2));
    expect(await collect(next.body), hasLength(100000));
    expect(clock.elapsedMilliseconds, lessThan(1000));
    expect(await eventually(() => server.closes('/trickle') == 1), isTrue);
  });

  test('cancelling the token after the headers ends the body and frees the connection', () async {
    final transport = IoRangeTransport(connectionsPerHost: 1);
    addTearDown(transport.close);
    final cancel = CancelToken();
    final response = await transport.fetch(server.url('/trickle'), ByteRange(0, (50 << 20) - 1), cancel: cancel);
    final errors = <Object>[];
    final done = Completer<void>();
    response.body.listen((_) {}, onError: errors.add, onDone: done.complete);
    cancel.cancel();
    await done.future.timeout(const Duration(seconds: 1));
    expect(errors.single, isA<CancelledException>());
    final next = await transport.fetch(server.url('/complete'), range).timeout(const Duration(seconds: 2));
    expect(await collect(next.body), hasLength(100000));
  });

  test('a connection lost before the headers is retried on a fresh one', () async {
    final transport = IoRangeTransport();
    addTearDown(transport.close);
    final response = await transport.fetch(server.url('/drop'), range);
    expect(response.status, 206);
    expect(await collect(response.body), LoopbackServer.pattern(0, 99999));
    expect(server.requests('/drop'), 2);
  });
}
