import 'dart:async';
import 'dart:io' show SocketException;

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/main.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player.dart';
import 'fake_keychain.dart';

const bv = 'BV1GJ411x7h7';

void main() {
  late CannedHttp http;
  late FakePlayer player;
  late FakeEngine engine;
  late AppEnvironment environment;

  setUp(() {
    http = Canned.http()..routes['/x/click-interface/web/heartbeat'] = (200, '{"code":0,"message":"0"}');
    player = FakePlayer();
    engine = FakeEngine();
  });

  Future<void> loadEnvironment({bool checkAccount = true}) async {
    environment = await AppEnvironment.load(
        keychain: FakeKeychain(const StoredCookies(Canned.cookies)), http: http, logger: Logger(session: 'test'));
    if (checkAccount) await environment.refreshAccount();
  }

  PlaybackController makeController() {
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    return PlaybackController(
      client: environment.client,
      engine: engine,
      player: player,
      clock: ManualClock(10000).clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: Logger(session: 'test'),
    );
  }

  AppPlayback appPlayback(Future<PlaybackController> Function() start, {VoidCallback? onResumed}) {
    final playback = AppPlayback(start, onResumed: onResumed);
    addTearDown(playback.dispose);
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

  testWidgets('memory pressure and coming back reach the shared player', (tester) async {
    tester.view.physicalSize = const Size(440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadEnvironment();
    final controller = makeController();
    final services = AppServices(
      environment: environment,
      playback: appPlayback(() async => controller),
      recents: await RecentStore.load(null, logger: Logger(session: 'test')),
    );
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      builder: (context, child) => AppScope(services: services, child: child!),
      home: const SizedBox(),
    ));
    unawaited(nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const VideoPage(route: VideoRoute(bvid: bv, cid: 137649199, start: 0)))));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.binding.handleMemoryPressure();
    expect(engine.cacheDrops, 1);
    final before = engine.ensureCalls;
    resume(tester);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(engine.ensureCalls, before + 1);
  });

  testWidgets("after a failed start the next obtain starts the player again, as a page's 重试 does", (tester) async {
    await loadEnvironment();
    final controller = makeController();
    var starts = 0;
    var failing = true;
    final playback = appPlayback(() async {
      starts += 1;
      if (failing) throw StateError('no engine');
      return controller;
    });
    await tester.pump();
    expect(starts, 1, reason: 'started at launch');
    expect(playback.ready, isNull);
    await expectLater(playback.obtain(), throwsStateError);
    expect(starts, 2);

    failing = false;
    expect(await playback.obtain(), same(controller));
    expect(playback.ready, same(controller));
    expect(await playback.obtain(), same(controller));
    expect(starts, 3, reason: 'a started player is not started again');
  });

  testWidgets('coming back re-checks an account the launch could not confirm, and only then', (tester) async {
    http.errors[Canned.navPath] = const SocketException('lost');
    await loadEnvironment();
    expect(environment.account, isA<AccountUnknown>());
    expect(environment.accountCheckFailed, isTrue);
    appPlayback(() async => makeController(), onResumed: () => recheckUnknownAccount(environment));
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
