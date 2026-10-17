import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

import 'support/loopback_server.dart';
import 'support/sim_cdn.dart';

void main() {
  late LoopbackServer server;

  setUp(() async {
    server = await LoopbackServer.start({
      '/keep': const Complete(100000, keepAlive: true),
      '/hang': const Hang(),
    });
  });

  tearDown(() => server.stop());

  test('a warm-up asks for one byte and leaves the connection open for the next request', () async {
    final transport = IoRangeTransport();
    addTearDown(transport.close);
    expect(await warmConnection(transport, server.url('/keep')), isTrue);
    expect(server.headers('/keep').single['range'], 'bytes=0-0');
    final response = await transport.fetch(server.url('/keep'), ByteRange(0, 99999));
    await response.body.drain<void>();
    expect(server.requests('/keep'), 2);
    expect(server.connections, 1, reason: 'the engine\'s first request found the warm connection');
  });

  test('a node that does not answer only costs the warm-up its time limit', () async {
    final transport = IoRangeTransport();
    addTearDown(transport.close);
    final clock = Stopwatch()..start();
    expect(await warmByFetch(transport, server.url('/hang'), timeout: const Duration(milliseconds: 200)), isFalse);
    expect(clock.elapsedMilliseconds, lessThan(2000));
  });

  test('a transport that cannot warm does nothing', () async {
    final cdn = SimCDN(size: 1024);
    expect(await warmConnection(cdn, Uri.parse(TestEngine.primary)), isFalse);
    expect(cdn.requestCount, 0);
  });
}
