import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/playback/shared_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player.dart';
import 'fakes.dart';

const bv = 'BV1GJ411x7h7';

/// Every page's controller on one engine isolate, each through a lease of its own.
void main() {
  late CannedHttp http;
  late List<FakeEngine> engines;
  late MemorySink logs;
  late Logger logger;
  late SharedEngine shared;
  late DateTime now;
  late List<PlaybackController> made;
  Completer<void>? startGate;
  Object? startError;

  setUp(() {
    http = Canned.http();
    engines = [];
    made = [];
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    startGate = null;
    startError = null;
    now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    shared = SharedEngine(() async {
      await startGate?.future;
      if (startError case final error?) {
        startError = null;
        throw error;
      }
      final engine = FakeEngine();
      engines.add(engine);
      return engine;
    }, logger: logger);
  });

  tearDown(() {
    for (final controller in made) {
      controller.dispose();
    }
  });

  Future<PlaybackController> make() async {
    final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
    final controller = PlaybackController(
      client: client,
      engine: await shared.lease(),
      startEngine: shared.lease,
      player: FakePlayer(),
      clock: ManualClock(10000).clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    made.add(controller);
    return controller;
  }

  PlaybackEngine engineOf(PlaybackController controller) => (controller.engine as EngineLease).engine;

  /// As the isolate exiting: every call fails as closed and the fatal reports end.
  Future<void> kill(FakeEngine engine) async {
    engine.closed = true;
    await engine.fatalController.close();
  }

  test('two controllers play on one engine, each through a lease of its own', () async {
    final a = await make();
    final b = await make();
    expect(engines, hasLength(1), reason: 'one isolate for every page');
    await a.open(bv);
    await b.open(bv);
    final engine = engines.single;
    expect(engine.prepared, hasLength(2));
    expect(engineOf(a), same(engine));
    expect(engineOf(b), same(engine));
    expect(a.engine, isNot(same(b.engine)));
    expect((a.engine as EngineLease).tokens, {'tok1'});
    expect((b.engine as EngineLease).tokens, {'tok2'});
  });

  test('a controller that goes releases only its own source; the engine runs on for the other', () async {
    final a = await make();
    final b = await make();
    await a.open(bv);
    await b.open(bv);
    made.remove(a);
    a.dispose();
    await settle();
    final engine = engines.single;
    expect(engine.released, ['tok1']);
    expect(engine.disposed, isFalse);
    expect(shared.running, same(engine));
    await b.open(bv);
    expect(engine.prepared, hasLength(3), reason: 'the other page still plays on it');
  });

  test('an engine that is gone is replaced once for every controller, and each moves onto it', () async {
    final a = await make();
    final b = await make();
    await a.open(bv);
    await b.open(bv);
    await kill(engines.single);
    expect(shared.running, isNull);

    await a.open(bv);
    await b.open(bv);
    expect(a.phase, PlaybackPhase.failed);
    expect(b.phase, PlaybackPhase.failed);
    expect(engines, hasLength(1), reason: 'nothing starts until a page plays again');

    final gate = startGate = Completer<void>();
    final reopening = [a.open(bv), b.open(bv)];
    await settle();
    gate.complete();
    await Future.wait(reopening);
    expect(engines, hasLength(2), reason: 'both waited on the one replacement');
    final replacement = engines.last;
    expect(engineOf(a), same(replacement));
    expect(engineOf(b), same(replacement));
    expect(replacement.prepared, hasLength(2));
    expect(a.phase, isNot(PlaybackPhase.failed));
    expect(b.phase, isNot(PlaybackPhase.failed));
    expect(logs.events.where((event) => event.msg == 'shared engine replaced'), hasLength(1));
  });

  test('a page that finds its engine gone only after another page moved onto the replacement leaves that one running, '
      'and moves onto it too', () async {
    final a = await make();
    final b = await make();
    await a.open(bv);
    await b.open(bv);
    await kill(engines.single);
    await b.open(bv);
    await b.open(bv);
    final replacement = engines.last;
    expect(engines, hasLength(2));
    expect(engineOf(b), same(replacement));

    // The covered page comes back to the foreground still on the dead engine.
    await a.appResumed();
    expect(a.phase, PlaybackPhase.failed);
    expect(shared.running, same(replacement), reason: 'the stale lease\'s closed error is not the replacement\'s');
    expect(replacement.disposed, isFalse);
    expect(b.phase, isNot(PlaybackPhase.failed));

    await a.open(bv);
    expect(engines, hasLength(2), reason: 'no third engine');
    expect(engineOf(a), same(replacement));
    expect(a.phase, isNot(PlaybackPhase.failed));
  });

  test('a network change that finds the engine gone is logged, not thrown', () async {
    await shared.lease();
    engines.single.closed = true;
    await shared.networkChanged(interfaceChanged: true);
    expect(logs.events.where((event) => event.msg == 'network change not taken'), hasLength(1));
    expect(engines.single.networkChanges, isEmpty);
  });

  test('a call that finds the engine closed is enough to start a new one for the next lease', () async {
    final a = await make();
    await a.open(bv);
    engines.single.closed = true;
    await a.open(bv);
    expect(a.phase, PlaybackPhase.failed);
    expect(shared.running, isNull);
    await a.open(bv);
    expect(engines, hasLength(2));
    expect(engineOf(a), same(engines.last));
  });

  test('a lease that has let go fails as closed and leaves the engine to the others', () async {
    final lease = await shared.lease();
    await lease.dispose();
    await expectLater(lease.ensureServing(), throwsA(const RipperError(RipperErrorKind.closed)));
    expect(shared.running, same(engines.single));
  });

  test('a page closed while its source was preparing releases it once, and logs no failure', () async {
    final a = await make();
    final engine = engines.single;
    final gate = engine.prepareGate = Completer<void>();
    final opening = a.open(bv);
    await settle();
    made.remove(a);
    a.dispose();
    await settle();
    gate.complete();
    await opening;
    await settle();
    expect(engine.released, ['tok1']);
    expect(logs.events.where((event) => event.msg == 'release failed'), isEmpty);
  });

  test('a lease that has let go takes a release as done, without asking the engine', () async {
    final lease = await shared.lease();
    await lease.dispose();
    await lease.release('tok1');
    expect(engines.single.released, isEmpty);
    expect(shared.running, same(engines.single));
  });

  test('a release that fails for another reason while letting go is logged', () async {
    final a = await make();
    await a.open(bv);
    final engine = engines.single;
    engine.releaseError = StateError('busy');
    await (a.engine as EngineLease).dispose();
    expect(logs.events.where((event) => event.msg == 'release failed'), hasLength(1));
  });

  test('a start that fails is tried again by the next lease', () async {
    startError = StateError('no isolate');
    await expectLater(shared.lease(), throwsStateError);
    final lease = await shared.lease();
    expect(lease.engine, same(engines.single));
  });

  test('the CDN 节点 reaches the engine running and every replacement, from any lease too', () async {
    shared.setNodeMode(NodeMode.mainland);
    final lease = await shared.lease();
    expect(engines.single.nodeModes.single, isA<MainlandNodes>(), reason: 'chosen before the engine started');
    lease.setNodeMode(NodeMode.overseas);
    expect(engines.single.nodeModes.last, isA<OverseasNodes>());
    await kill(engines.single);
    await shared.lease();
    expect(engines.last.nodeModes.single, isA<OverseasNodes>());
  });

  test('pages that probe the server together share one probe', () async {
    final first = await shared.lease();
    final second = await shared.lease();
    engines.single.restartOnEnsure = true;
    final answers = await Future.wait([first.ensureServing(), second.ensureServing()]);
    expect(answers, [true, true]);
    expect(engines.single.ensureCalls, 1);
    await settle();
    expect(await first.ensureServing(), isFalse, reason: 'a later probe asks again');
    expect(engines.single.ensureCalls, 2);
  });

  test('a covered page drops only its own playback\'s prefetch', () async {
    final a = await make();
    final b = await make();
    await a.open(bv);
    await b.open(bv);
    a.dropPrefetch();
    expect(engines.single.prefetchDrops, ['tok1']);
    b.dropPrefetch();
    expect(engines.single.prefetchDrops, ['tok1', 'tok2']);
  });

  test('a memory warning leaves the drop to the shared engine, once', () async {
    final a = await make();
    final b = await make();
    a.memoryPressure();
    b.memoryPressure();
    expect(engines.single.cacheDrops, 0, reason: 'AppPlayback drops the shared engine\'s cache');
    shared.dropCache();
    expect(engines.single.cacheDrops, 1);
  });

  test('each controller takes only its own playback\'s stats and fatal reports', () async {
    final a = await make();
    final b = await make();
    await a.open(bv);
    await b.open(bv);
    final engine = engines.single;
    engine.statsController.add(const EngineSnapshot(deliveredBytes: 2, token: 'tok2'));
    expect(a.stats.value.engine, isNull);
    expect(b.stats.value.engine?.deliveredBytes, 2);

    final asked = http.to(Canned.playUrlPath).length;
    engine.fatalController.add(const FatalReport(token: 'tok2', message: 'all nodes failed'));
    await settle();
    expect(http.to(Canned.playUrlPath), hasLength(asked + 1), reason: 'only b refreshes its URLs');
    expect(logs.events.where((event) => event.msg == 'btr range failed, refreshing urls'), hasLength(1));
  });

  test('the speed test\'s engines stay on its own controller; the pages keep the shared engine', () async {
    final page = await make();
    final developer = await make();
    await page.open(bv);
    final variant = FakeEngine();
    await developer.useEngine(() async => variant);
    expect(developer.engine, same(variant));
    expect(engineOf(page), same(engines.single));
    expect(engines.single.disposed, isFalse);

    await developer.useEngine(shared.lease);
    expect(variant.disposed, isTrue);
    expect(engineOf(developer), same(engines.single), reason: 'a run ends back on the shared engine');
    expect(engines, hasLength(1));
    expect(page.phase, isNot(PlaybackPhase.failed));
  });
}
