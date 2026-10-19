import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/devtools/log_forwarder.dart';
import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/screens/player_test_page.dart';
import 'package:bilifast/speedtest/speed_test_plan.dart';
import 'package:bilifast/speedtest/speed_test_runner.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../speedtest/fake_target.dart';
import '../support/fake_player.dart';

const bv = 'BV1GJ411x7h7';

/// 开发者 on the app's shared player (ownsController: false), as 设置 opens it.
void main() {
  late CannedHttp http;
  late FakePlayer player;
  late FakeEngine engine;
  late ManualClock time;
  late PlaybackController controller;
  late AppEnvironment environment;
  late GlobalKey<NavigatorState> nav;

  setUp(() {
    http = Canned.http()..routes['/x/click-interface/web/heartbeat'] = (200, '{"code":0,"message":"0"}');
    player = FakePlayer();
    engine = FakeEngine();
    time = ManualClock(10000);
    nav = GlobalKey<NavigatorState>();
  });

  /// [home] is built under the pushed pages, as home is under 开发者 in the app.
  Future<void> host(WidgetTester tester,
      {Future<PlaybackController> Function()? start, WidgetBuilder? home, double height = 900}) async {
    tester.view.physicalSize = Size(440, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    environment = await AppEnvironment.load(
        keychain: FakeKeychain(const StoredCookies(Canned.cookies)), http: http, logger: logger);
    await environment.refreshAccount();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    controller = PlaybackController(
      client: environment.client,
      engine: engine,
      player: player,
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    final playback = AppPlayback(start ?? () async => controller);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
    );
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      builder: (context, child) => AppScope(services: services, child: child!),
      home: Builder(builder: home ?? (_) => const SizedBox()),
    ));
  }

  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void pushDeveloper({Future<PlaybackController> Function()? start, LogForwarder? logs, SpeedTestHooks? hooks}) =>
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => PlayerTestPage(
          environment: environment,
          startPlayback: start ?? () async => controller,
          logs: logs,
          speedTestHooks: hooks ?? appSpeedTestHooks,
          ownsController: false,
        ),
      )));

  void pushVideo(VideoRoute route) =>
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => VideoPage(route: route))));

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

  testWidgets('leaving 开发者 before the shared player is ready leaves it alive', (tester) async {
    final ready = Completer<PlaybackController>();
    await host(tester, start: () => ready.future);
    pushDeveloper(start: () => ready.future);
    await frames(tester);
    nav.currentState!.pop();
    await frames(tester, 20);
    ready.complete(controller);
    await frames(tester);
    expect(player.disposed, isFalse);
    expect(engine.disposed, isFalse);
  });

  testWidgets('a video page opened while 开发者 is leaving keeps playing', (tester) async {
    await host(tester);
    pushDeveloper();
    await frames(tester);
    await play(tester, bv);
    nav.currentState!.pop();
    await tester.pump();
    pushVideo(const VideoRoute(bvid: bv, cid: 137649199, start: 0));
    await frames(tester, 30);
    expect(controller.video?.bvid, bv);
    expect(controller.phase, isNot(PlaybackPhase.idle));
    expect(player.calls, isNot(contains('unload')));
  });

  testWidgets('leaving 开发者 closes and unloads its own video after the tree is torn down', (tester) async {
    // A page still listening below, as home may: a close inside dispose would rebuild it while the tree is locked.
    await host(tester, home: (_) => ListenableBuilder(listenable: controller, builder: (_, _) => const SizedBox()));
    pushDeveloper();
    await frames(tester);
    await play(tester, bv);
    expect(controller.video?.bvid, bv);
    nav.currentState!.pop();
    await frames(tester, 20);
    expect(tester.takeException(), isNull);
    expect(controller.video, isNull);
    expect(player.calls.last, 'unload');
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

    pushDeveloper();
    await frames(tester);
    final back = find.semantics.byLabel('返回');
    expect(back.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(back);
    await frames(tester, 20);
    expect(find.byType(PlayerTestPage), findsNothing);
    semantics.dispose();
  });

  testWidgets('leaving 开发者 without playing anything closes nothing', (tester) async {
    await host(tester);
    pushDeveloper();
    await frames(tester);
    nav.currentState!.pop();
    await frames(tester, 20);
    expect(player.calls, isNot(contains('unload')));
  });

  testWidgets('a new video reads 0 s on the bar from the start, not the last one\'s time', (tester) async {
    await host(tester);
    pushDeveloper();
    await frames(tester);
    await play(tester, bv);
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

  testWidgets('leaving 开发者 mid speed test puts the app engine, quality and sound back on the shared player',
      (tester) async {
    final engines = <String>[];
    final hooks = SpeedTestHooks(
      choosePlan: (server) async => quickPlan(),
      startEngine: (variant) async {
        engines.add(variant.name);
        return FakeEngine();
      },
      appEngine: () async {
        engines.add('app');
        return FakeEngine();
      },
    );
    await host(tester, height: 1600);
    // Checks on the PC run with --mute.
    await player.setMuted(true);
    pushDeveloper(logs: devLogs(), hooks: hooks);
    await frames(tester);
    await startSpeedTest(tester);
    expect(engines, isNotEmpty);
    expect(controller.selectedQuality, 120);
    nav.currentState!.pop();
    await frames(tester, 30);
    expect(engines.last, 'app', reason: 'the next video page must not play on a speed test variant');
    expect(controller.video, isNull);
    expect(controller.selectedQuality, PlaybackController.defaultQuality);
    expect(controller.mode, PlaybackMode.btr);
    expect(player.muted, isTrue, reason: 'the run found it muted');
    expect(player.calls.where((call) => call.startsWith('muted')).last, 'muted true');
  });

  testWidgets('an engine swap still starting when 开发者 goes ends on the app engine', (tester) async {
    final gate = Completer<void>();
    final engines = <String>[];
    final variants = <FakeEngine>[];
    final app = FakeEngine();
    final hooks = SpeedTestHooks(
      choosePlan: (server) async => quickPlan(),
      startEngine: (variant) async {
        engines.add(variant.name);
        final started = FakeEngine();
        variants.add(started);
        // The first pass's own engine, for its replay.
        if (engines.length == 2) await gate.future;
        return started;
      },
      appEngine: () async {
        engines.add('app');
        return app;
      },
    );
    await host(tester, height: 1600);
    pushDeveloper(logs: devLogs(), hooks: hooks);
    await frames(tester);
    await startSpeedTest(tester);
    expect(engines, ['A', 'A']);
    nav.currentState!.pop();
    await frames(tester, 30);
    expect(engines, ['A', 'A'], reason: 'the app engine waits for the swap in flight');
    gate.complete();
    await frames(tester, 10);
    expect(engines, ['A', 'A', 'app']);
    expect(controller.engine, same(app));
    expect(variants.every((variant) => variant.disposed), isTrue);
    expect(app.disposed, isFalse);
    expect(variants.last.prepared, isEmpty, reason: 'the replay that asked for it was overtaken');
  });
}
