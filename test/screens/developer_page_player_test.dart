import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/devtools/log_forwarder.dart';
import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/playback/shared_engine.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/screens/player_test_page.dart';
import 'package:bilifast/speedtest/speed_test_plan.dart';
import 'package:bilifast/speedtest/speed_test_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../speedtest/fake_target.dart';
import '../support/fake_player.dart';

const bv = 'BV1GJ411x7h7';

/// 开发者 as 设置 opens it: a player of its own from AppPlayback.create on the pages' shared engine, released when
/// the page leaves; the speed test's variants run on engines of their own.
void main() {
  late CannedHttp http;
  late ManualClock time;
  late AppEnvironment environment;
  late GlobalKey<NavigatorState> nav;
  late List<FakeEngine> engines;
  late List<FakePlayer> players;
  late List<PlaybackController> controllers;
  late SharedEngine shared;
  late AppPlayback playback;
  late Logger logger;
  Completer<void>? startGate;

  setUp(() {
    http = Canned.http();
    time = ManualClock(10000);
    nav = GlobalKey<NavigatorState>();
    engines = [];
    players = [];
    controllers = [];
    logger = Logger(session: 'test');
    startGate = null;
    shared = SharedEngine(() async {
      final engine = FakeEngine();
      engines.add(engine);
      return engine;
    }, logger: logger);
  });

  /// The app's start, with fakes: a new player on a lease of the shared engine.
  Future<PlaybackController> start() async {
    await startGate?.future;
    final player = FakePlayer();
    players.add(player);
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final controller = PlaybackController(
      client: environment.client,
      engine: await shared.lease(),
      startEngine: shared.lease,
      player: player,
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    controllers.add(controller);
    return controller;
  }

  Future<void> host(WidgetTester tester, {double height = 900}) async {
    tester.view.physicalSize = Size(440, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    environment = await AppEnvironment.load(
        keychain: FakeKeychain(const StoredCookies(Canned.cookies)), http: http, logger: logger);
    await environment.refreshAccount();
    playback = AppPlayback(start, engine: shared, logger: logger);
    addTearDown(() {
      for (final controller in controllers) {
        playback.release(controller);
      }
      playback.dispose();
    });
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
    );
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      builder: (context, child) => AppScope(services: services, child: child!),
      home: const SizedBox(),
    ));
  }

  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void pushDeveloper({LogForwarder? logs, SpeedTestHooks? hooks}) =>
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => PlayerTestPage(
          environment: environment,
          startPlayback: playback.create,
          releasePlayback: playback.release,
          logs: logs,
          speedTestHooks: hooks ?? appSpeedTestHooksOn(shared),
        ),
      )));

  Future<void> play(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('link-field')), text);
    await tester.tap(find.byKey(const ValueKey('play-button')));
    await frames(tester, 5);
  }

  LogForwarder devLogs() {
    final logs = LogForwarder(
      logger: Logger(session: 'test'),
      discovery: const NoLogServerDiscovery(),
      poster: (endpoint) => (body) async {},
      initialTarget: '',
    );
    addTearDown(logs.dispose);
    return logs;
  }

  PlanChoice quickPlan() => PlanChoice(
        plan: planWith({'order': 'AB', 'seeks': 0, 'hints': 0, 'backJumps': 0, 'dwellSeconds': 0, 'fastSeconds': 0}),
        source: PlanSource.builtin,
        note: '',
      );

  Future<void> startSpeedTest(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('speedtest-links')), bv);
    await tester.tap(find.byKey(const ValueKey('speedtest-start')));
    await frames(tester, 20);
  }

  testWidgets('开发者 plays on a player of its own; leaving releases it and the engine runs on', (tester) async {
    await host(tester);
    pushDeveloper();
    await frames(tester);
    expect(playback.live, 1);
    await play(tester, bv);
    expect(controllers.single.video?.bvid, bv);
    expect(engines.single.prepared, hasLength(1));

    nav.currentState!.pop();
    await frames(tester, 20);
    expect(tester.takeException(), isNull);
    expect(playback.live, 0);
    expect(players.single.disposed, isTrue);
    expect(engines.single.released, ['tok1']);
    expect(engines.single.disposed, isFalse);
  });

  testWidgets('leaving 开发者 before its player is ready releases the player once it arrives', (tester) async {
    await host(tester);
    final gate = startGate = Completer<void>();
    pushDeveloper();
    await frames(tester);
    nav.currentState!.pop();
    await frames(tester, 20);
    gate.complete();
    await frames(tester);
    expect(players.single.disposed, isTrue);
    expect(playback.live, 0);
    expect(engines.single.disposed, isFalse);
  });

  testWidgets('‹ in the bar leaves 开发者, pressed or through VoiceOver', (tester) async {
    final semantics = tester.ensureSemantics();
    await host(tester);
    pushDeveloper();
    await frames(tester);
    expect(find.text('开发者'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('developer-back')));
    await frames(tester, 20);
    expect(find.byType(PlayerTestPage), findsNothing);
    expect(playback.live, 0);

    pushDeveloper();
    await frames(tester);
    final back = find.semantics.byLabel('返回');
    expect(back.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(back);
    await frames(tester, 20);
    expect(find.byType(PlayerTestPage), findsNothing);
    expect(playback.live, 0);
    semantics.dispose();
  });

  testWidgets('a new video reads 0 s on the bar from the start, not the last one\'s time', (tester) async {
    await host(tester);
    pushDeveloper();
    await frames(tester);
    await play(tester, bv);
    final player = players.single;
    final controller = controllers.single;
    player.emit(const StatusChanged(PlayerStatus.playing));
    time.advance(PlaybackClock.jumpSettleMs);
    player.emit(PositionChanged(seconds: 45, hostMs: time.clock.nowMs(), rate: 1));
    player.emit(const DurationChanged(712));
    await frames(tester, 2);
    expect(tester.widget<Text>(find.byKey(const ValueKey('player-time'))).data, startsWith('00:45'));

    final gate = http.gates[Canned.playUrlPath] = Completer<void>();
    await play(tester, '$bv?p=2');
    expect(controller.page?.page, 2, reason: 'the stage shows while the playurl call runs');
    expect(tester.widget<Text>(find.byKey(const ValueKey('player-time'))).data, '00:00/00:00');
    gate.complete();
    await frames(tester);
  });

  testWidgets('a speed test swaps only 开发者\'s engine; leaving mid run releases it and its variant, and a video '
      'page\'s player stays on the shared engine', (tester) async {
    final variants = <FakeEngine>[];
    var putBacks = 0;
    final hooks = SpeedTestHooks(
      choosePlan: (server) async => quickPlan(),
      startEngine: (variant) async {
        final started = FakeEngine();
        variants.add(started);
        return started;
      },
      appEngine: () {
        putBacks += 1;
        return shared.lease();
      },
    );
    await host(tester, height: 1600);
    final page = await playback.create();
    await page.open(bv);
    pushDeveloper(logs: devLogs(), hooks: hooks);
    await frames(tester);
    await startSpeedTest(tester);
    final developer = controllers.last;
    expect(variants, isNotEmpty);
    expect(developer.engine, same(variants.last));
    expect((page.engine as EngineLease).engine, same(engines.single));

    nav.currentState!.pop();
    await frames(tester, 30);
    expect(playback.live, 1, reason: 'the video page\'s');
    expect(players.last.disposed, isTrue);
    expect(variants.every((variant) => variant.disposed), isTrue);
    expect(putBacks, 0, reason: 'nothing to put back on a player that went with the page');
    expect(engines, hasLength(1));
    expect(engines.single.disposed, isFalse);
    expect((page.engine as EngineLease).engine, same(engines.single));
    expect(page.phase, isNot(PlaybackPhase.failed));
  });

  testWidgets('an engine swap still starting when 开发者 goes is dropped with its player', (tester) async {
    final gate = Completer<void>();
    final variants = <FakeEngine>[];
    final hooks = SpeedTestHooks(
      choosePlan: (server) async => quickPlan(),
      startEngine: (variant) async {
        final started = FakeEngine();
        variants.add(started);
        // The first pass's own engine, for its replay.
        if (variants.length == 2) await gate.future;
        return started;
      },
      appEngine: shared.lease,
    );
    await host(tester, height: 1600);
    pushDeveloper(logs: devLogs(), hooks: hooks);
    await frames(tester);
    await startSpeedTest(tester);
    expect(variants, hasLength(2));
    nav.currentState!.pop();
    await frames(tester, 30);
    gate.complete();
    await frames(tester, 10);
    expect(variants.every((variant) => variant.disposed), isTrue);
    expect(variants.last.prepared, isEmpty, reason: 'the replay that asked for it was overtaken');
    expect(playback.live, 0);
    expect(engines.single.disposed, isFalse);
  });
}
