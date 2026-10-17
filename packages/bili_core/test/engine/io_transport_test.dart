import 'dart:async';
import 'dart:io';

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
      '/keep': const Complete(100000, keepAlive: true),
      '/stale': const StaleReuse(100000),
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

  test('cancelling the token mid-body ends the read with CancelledException and closes the socket', () async {
    // One connection per host: the next request can only start once the first gave its connection back.
    final transport = IoRangeTransport(connectionsPerHost: 1);
    addTearDown(transport.close);
    final cancel = CancelToken();
    final response = await transport.fetch(server.url('/trickle'), ByteRange(0, (50 << 20) - 1), cancel: cancel);
    var received = 0;
    final errors = <Object>[];
    final done = Completer<void>();
    response.body.listen((chunk) => received += chunk.length, onError: errors.add, onDone: done.complete);
    expect(await eventually(() => received >= 4096), isTrue);
    final clock = Stopwatch()..start();
    cancel.cancel();
    await done.future.timeout(const Duration(seconds: 2));
    expect(clock.elapsedMilliseconds, lessThan(1000));
    expect(errors.single, isA<CancelledException>());
    expect(await eventually(() => server.closes('/trickle') == 1), isTrue);
    final next = await transport.fetch(server.url('/complete'), range).timeout(const Duration(seconds: 2));
    expect(await collect(next.body), hasLength(100000));
  });

  test('cancelling the body subscription mid-way frees the connection at once', () async {
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

  test('dropping the body unread cancels the request and closes the socket', () async {
    // What the engine does with a response that lost its race before the body was read.
    final transport = IoRangeTransport(connectionsPerHost: 1);
    addTearDown(transport.close);
    final response = await transport.fetch(server.url('/trickle'), ByteRange(0, (50 << 20) - 1));
    expect(response.status, 206);
    await response.body.listen(null).cancel();
    expect(await eventually(() => server.closes('/trickle') == 1), isTrue);
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

  test('requests one after another share a keep-alive connection', () async {
    final transport = IoRangeTransport();
    addTearDown(transport.close);
    for (var round = 0; round < 3; round++) {
      final response = await transport.fetch(server.url('/keep'), range);
      expect(await collect(response.body), LoopbackServer.pattern(0, 99999));
    }
    expect(server.requests('/keep'), 3);
    expect(server.connections, 1);
  });

  test('a request sent on a keep-alive socket the server closed is retried on a fresh connection', () async {
    final transport = IoRangeTransport();
    addTearDown(transport.close);
    final first = await transport.fetch(server.url('/stale'), range);
    expect(await collect(first.body), hasLength(100000));
    final second = await transport.fetch(server.url('/stale'), ByteRange(100, 199));
    expect(second.status, 206);
    expect(second.headers['content-range'], 'bytes 100-199/100000');
    expect(await collect(second.body), LoopbackServer.pattern(100, 199));
    expect(server.requests('/stale'), 3);
    expect(server.connections, 2);
  });

  test('an error status is an answer, not a lost connection', () async {
    final transport = IoRangeTransport();
    addTearDown(transport.close);
    final response = await transport.fetch(server.url('/missing'), range);
    expect(response.status, 404);
    await response.body.drain<void>();
    expect(server.requests('/missing'), 1);
  });

  test('a refused connection fails at once instead of being retried as a lost one', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final transport = IoRangeTransport();
    addTearDown(transport.close);
    // Windows takes about 2 s to report each refused connect to a loopback port, so three tries took 6.1 s, past
    // the engine's 5.5 s first-byte timeout.
    final clock = Stopwatch()..start();
    await expectLater(
        transport.fetch(Uri.parse('http://127.0.0.1:$port/x.m4s'), range), throwsA(isA<SocketException>()));
    expect(clock.elapsedMilliseconds, lessThan(4000));
  });
}
