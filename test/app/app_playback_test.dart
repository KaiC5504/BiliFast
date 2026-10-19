import 'dart:async';
import 'dart:io' show SocketException;

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/device/network_monitor.dart';
import 'package:bilifast/main.dart';
import 'package:bilifast/playback/codec_memory.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/playback/shared_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player.dart';
import 'fake_keychain.dart';

const bv = 'BV1GJ411x7h7';

final class FakeNetworkMonitor implements NetworkMonitor {
  final controller = StreamController<bool>.broadcast(sync: true);

  @override
  Stream<bool> get changes => controller.stream;
}

/// The app's players: a controller and player per page, one engine and one codec memory for all of them.
void main() {
  late CannedHttp http;
  late AppEnvironment environment;
  late List<FakeEngine> engines;
  late List<FakePlayer> players;
  late List<PlaybackController> made;
  late SharedEngine shared;
  late CodecMemory memory;
  late FakeNetworkMonitor network;
  late MemorySink logs;
  late Logger logger;
  Completer<void>? engineGate;

  setUp(() {
    http = Canned.http();
    engines = [];
    players = [];
    made = [];
    memory = CodecMemory();
    network = FakeNetworkMonitor();
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    engineGate = null;
    shared = SharedEngine(() async {
      await engineGate?.future;
      final engine = FakeEngine();
      engines.add(engine);
      return engine;
    }, logger: logger);
  });

  Future<void> loadEnvironment({bool checkAccount = true}) async {
    environment = await AppEnvironment.load(
        keychain: FakeKeychain(const StoredCookies(Canned.cookies)), http: http, logger: Logger(session: 'test'));
    if (checkAccount) await environment.refreshAccount();
  }

  /// startPlaybackController's wiring, with fakes: a new player on a lease of the shared engine.
  Future<PlaybackController> startController() async {
    final player = FakePlayer();
    players.add(player);
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final controller = PlaybackController(
      client: environment.client,
      engine: await shared.lease(),
      startEngine: shared.lease,
      player: player,
      codecMemory: memory,
      clock: ManualClock(10000).clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    made.add(controller);
    return controller;
  }

  AppPlayback appPlayback({bool muted = false, VoidCallback? onResumed}) {
    final playback = AppPlayback(
      startController,
      engine: shared,
      codecMemory: memory,
      network: network,
      muted: muted,
      onResumed: onResumed,
      logger: logger,
    );
    addTearDown(() {
      for (final controller in made) {
        playback.release(controller);
      }
      playback.dispose();
    });
    return playback;
  }

  void resume(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      // ignore: invalid_use_of_protected_member
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  int loads(FakePlayer player) => player.calls.where((call) => call.startsWith('load')).length;

  Iterable<LogEvent> logged(String msg) => logs.events.where((event) => event.msg == msg);

  testWidgets('the engine starts at launch; each page gets a player of its own on it', (tester) async {
    await loadEnvironment();
    final playback = appPlayback();
    await tester.pump();
    expect(engines, hasLength(1), reason: 'started before any page asks');
    expect(players, isEmpty);

    final a = await playback.create();
    final b = await playback.create();
    expect(playback.live, 2);
    expect(players, hasLength(2));
    expect(a.player, same(players[0]));
    expect(b.player, same(players[1]));
    expect(engines, hasLength(1), reason: 'both on the one engine');
    expect([for (final event in logged('player created')) event.f['live']], [const LogInt(1), const LogInt(2)]);
  });

  testWidgets('release frees the page\'s player and source, not the engine, and the count goes back to 0',
      (tester) async {
    await loadEnvironment();
    final playback = appPlayback();
    final a = await playback.create();
    final b = await playback.create();
    await a.open(bv);
    await b.open(bv);

    playback.release(a);
    await tester.pump();
    expect(players[0].disposed, isTrue);
    expect(players[1].disposed, isFalse);
    expect(engines.single.released, ['tok1']);
    expect(engines.single.disposed, isFalse);
    expect(playback.live, 1);

    playback
      ..release(b)
      ..release(b);
    await tester.pump();
    expect(playback.live, 0);
    expect(engines.single.disposed, isFalse, reason: 'the next page plays on it at once');
    expect([for (final event in logged('player released')) event.f['live']], [const LogInt(1), const LogInt(0)]);
  });

  testWidgets('a memory warning drops the engine\'s cache once, and every page marks it', (tester) async {
    await loadEnvironment();
    final playback = appPlayback();
    final a = await playback.create();
    final b = await playback.create();
    final marks = <PlaybackMark>[];
    a.marks.listen(marks.add);
    b.marks.listen(marks.add);
    tester.binding.handleMemoryPressure();
    await tester.pump();
    expect(engines.single.cacheDrops, 1);
    expect(marks.whereType<MemoryWarning>(), hasLength(2));
    expect(logged('memory warning, prefetch cache dropped'), hasLength(2));
  });

  testWidgets('coming back probes the server once; after a restart every page with a source prepares again',
      (tester) async {
    await loadEnvironment();
    final playback = appPlayback();
    final a = await playback.create();
    final b = await playback.create();
    final idle = await playback.create();
    await a.open(bv);
    await b.open(bv);
    final engine = engines.single;
    final probes = engine.ensureCalls;
    final prepared = engine.prepared.length;
    engine.restartOnEnsure = true;
    final gate = engine.ensureGate = Completer<void>();

    resume(tester);
    await tester.pump();
    expect(engine.ensureCalls, probes + 1, reason: 'one probe answers every page');
    engine.ensureGate = null;
    gate.complete();
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(engine.prepared, hasLength(prepared + 2));
    expect(loads(a.player as FakePlayer), 2);
    expect(loads(b.player as FakePlayer), 2);
    expect(loads(idle.player as FakePlayer), 0, reason: 'nothing was prepared on it');
  });

  testWidgets('coming back without a restart reloads nothing', (tester) async {
    await loadEnvironment();
    final playback = appPlayback();
    final a = await playback.create();
    await a.open(bv);
    final probes = engines.single.ensureCalls;
    resume(tester);
    await tester.pump();
    expect(engines.single.ensureCalls, probes + 1);
    expect(loads(a.player as FakePlayer), 1);
  });

  testWidgets('a network change reaches the engine once, however many pages are open', (tester) async {
    await loadEnvironment();
    final playback = appPlayback();
    await playback.create();
    await playback.create();
    network.controller.add(true);
    await tester.pump();
    network.controller.add(false);
    await tester.pump();
    expect(engines.single.networkChanges, [true, false]);
    expect([for (final event in logged('network changed')) event.f['interfaceChanged']],
        [const LogBool(true), const LogBool(false)]);
  });

  testWidgets('--mute mutes every player made', (tester) async {
    await loadEnvironment();
    final playback = appPlayback(muted: true);
    final a = await playback.create();
    final b = await playback.create();
    expect(a.player.muted, isTrue);
    expect(b.player.muted, isTrue);
    final obtained = await playback.obtain();
    addTearDown(obtained.dispose);
    expect(obtained.player.muted, isTrue);
  });

  testWidgets('设置\'s node and codec memory changes need no page open', (tester) async {
    await loadEnvironment();
    final gate = engineGate = Completer<void>();
    final playback = appPlayback();
    memory.markFailed('av1');
    playback
      ..resetCodecMemory()
      ..setNodeMode(NodeMode.mainland);
    expect(memory.failedKinds, isEmpty);
    expect(engines, isEmpty, reason: 'the engine is still starting');
    gate.complete();
    await tester.pump();
    expect(engines.single.nodeModes.single, isA<MainlandNodes>());
    playback.setNodeMode(NodeMode.overseas);
    expect(engines.single.nodeModes.last, isA<OverseasNodes>());
    expect(playback.live, 0);
  });

  testWidgets("after a failed start the next obtain starts the player again, as a page's 重试 does", (tester) async {
    await loadEnvironment();
    var failing = true;
    final playback = AppPlayback(() async {
      if (failing) throw StateError('no engine');
      return startController();
    });
    addTearDown(playback.dispose);
    await expectLater(playback.obtain(), throwsStateError);
    expect(playback.ready, isNull);
    failing = false;
    final controller = await playback.obtain();
    addTearDown(controller.dispose);
    expect(playback.ready, same(controller));
    expect(await playback.obtain(), same(controller));
    expect(players, hasLength(1), reason: 'a started player is not started again');
  });

  testWidgets('coming back re-checks an account the launch could not confirm, and only then', (tester) async {
    http.errors[Canned.navPath] = const SocketException('lost');
    await loadEnvironment();
    expect(environment.account, isA<AccountUnknown>());
    expect(environment.accountCheckFailed, isTrue);
    appPlayback(onResumed: () => recheckUnknownAccount(environment));
    final asked = http.to(Canned.navPath).length;

    http.errors.remove(Canned.navPath);
    resume(tester);
    await tester.pump();
    await tester.pump();
    expect(http.to(Canned.navPath), hasLength(asked + 1));
    expect(environment.account, isA<LoggedIn>());

    resume(tester);
    await tester.pump();
    expect(http.to(Canned.navPath), hasLength(asked + 1), reason: 'a known account is not asked for again');
  });
}
