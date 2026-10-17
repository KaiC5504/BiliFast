import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/ban_list.dart';
import 'package:bili_core/src/engine/resolver.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

// Port of NetworkChangeTests.swift.

const primary = 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv';

Resolver resolverAt(ManualClock manual) =>
    Resolver(primary: primary, backups: const [], mode: NodeMode.overseas, bans: BanList(), clock: manual.clock);

void main() {
  test('reset health lifts backoffs and keeps speeds on the same interface', () {
    final resolver = resolverAt(ManualClock(100000));
    final slow = resolver.urls()[0];
    final fast = resolver.urls()[1];
    resolver.failure(slow, status: 503, receivedBytes: 0);
    resolver.success(fast, bps: 2000000);
    expect(resolver.ordered(), isNot(contains(slow)));

    resolver.resetHealth(clearMeasurements: false);
    expect(resolver.ordered(), contains(slow));
    expect(resolver.speed(fast), 2000000);
  });

  test('reset health on a new interface forgets speeds and measures wide again', () {
    final resolver = resolverAt(ManualClock(100000));
    final fast = resolver.urls()[2];
    resolver.success(fast, bps: 9000000);
    for (var round = 0; round < 4; round++) {
      resolver.rangeCandidates();
    }
    expect(resolver.rangeCandidates().first, fast);

    resolver.resetHealth(clearMeasurements: true);
    expect(resolver.speed(fast), 0);
    expect(resolver.rangeCandidates(), hasLength(4), reason: 'the first range after the change goes wide again');
    expect(resolver.status().where((status) => status.node == NodeCatalog.nodeKey(fast)).firstOrNull?.state, 'healthy');
  });

  // A drop on the old path cuts every running copy and would otherwise count as damage at each of their offsets.
  test('reset health forgets damage', () {
    final resolver = resolverAt(ManualClock(100000));
    final a = resolver.urls()[0];
    resolver.success(a, bps: 0);
    for (var block = 0; block < 2; block++) {
      resolver.failure(a, receivedBytes: 0, range: ByteRange((block << 20) + 1000, (block << 20) + 9999));
    }
    expect(resolver.avoids(a, ByteRange(1000, 9999)), isTrue);

    resolver.resetHealth(clearMeasurements: false);
    expect(resolver.avoids(a, ByteRange(1000, 9999)), isFalse);
    resolver.failure(a, receivedBytes: 0, range: ByteRange(2 << 20, (2 << 20) + 9999));
    resolver.failure(a, receivedBytes: 0, range: ByteRange((2 << 20) + 5000, (2 << 20) + 9999));
    expect(resolver.allows(a), isTrue, reason: 'damage after the change is judged afresh');
  });

  test('a session\'s network change clears bans and backoffs', () async {
    final session = RipperSession(
      sources: {TrackKind.video: (primary: TestEngine.primary, backups: const [])},
      mode: NodeMode.overseas,
      config: TestEngine.config.copyWith(pieceRounds: 1),
      transport: SimCDN(
        size: 1000000,
        behaviors: {for (final node in NodeCatalog.overseas) node: const NodeBehavior(status: 503)},
      ),
      logger: Logger(session: 'test'),
    );
    addTearDown(session.close);
    await expectLater(session.read(TrackKind.video, ByteRange(2000, 50000)).drain<void>(), throwsA(anything));
    expect(session.stats().nodeStates.any((status) => status.state == 'banned' || status.state == 'blocked'), isTrue);

    session.networkChanged(interfaceChanged: false);
    expect(session.stats().nodeStates.map((status) => status.state).toSet(), {'untested'});
  });
}
