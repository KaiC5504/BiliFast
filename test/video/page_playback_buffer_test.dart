import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/settings/autoplay_policy.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_playback.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';

const bv = 'BV1GJ411x7h7';
const p1 = 137649199;

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

/// How far ahead AVPlayer buffers and whether the engine keeps an idle session, as a page's playback moves between
/// 推荐's card, the page shown and the page covered.
void main() {
  late AppServices services;
  late List<FakePlayer> players;
  late List<FakeEngine> engines;
  late CannedHttp http;
  late MemorySink logs;

  setUp(() {
    players = [];
    engines = [];
    final savedPrefs = PlayerPrefs.shared;
    final savedPolicy = AutoplayPolicy.shared;
    PlayerPrefs.shared = PlayerPrefs.memory();
    AutoplayPolicy.shared = AutoplayPolicy.fixed();
    addTearDown(() {
      PlayerPrefs.shared = savedPrefs;
      AutoplayPolicy.shared = savedPolicy;
    });
  });

  Future<void> host(WidgetTester tester) async {
    http = Canned.http();
    logs = MemorySink();
    final logger = Logger(session: 'test')..add(logs);
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final playback = AppPlayback(() async {
      final player = FakePlayer();
      players.add(player);
      final engine = FakeEngine();
      engines.add(engine);
      return PlaybackController(
        client: environment.client,
        engine: engine,
        player: player,
        clock: ManualClock(10000).clock,
        now: () => now,
        startTimer: FakeTimers().start,
        logger: logger,
      );
    });
    addTearDown(playback.dispose);
    services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(orientation: OrientationController(), controls: NoDeviceControls()),
      loginGate: _NoLogin(),
      pageApi: FakePageApi(),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: services.navigator,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const SizedBox(),
      ),
    );
  }

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  PagePlayback playback({bool inline = false, VideoRoute route = const VideoRoute(bvid: bv, cid: p1, start: 0)}) =>
      PagePlayback(
        services: services,
        route: route,
        createSession: pageSession,
        restorePage: (_) => const SizedBox(),
        inline: inline,
      );

  List<String?> playUrlCids() => [
    for (final request in http.to(Canned.playUrlPath)) request.url.queryParameters['cid'],
  ];

  Object? loadParallel() => logs.events.lastWhere((event) => event.msg == 'load').f['parallel']?.toJson();

  Future<void> closed(WidgetTester tester, PagePlayback playback) async {
    playback.close();
    await frames(tester, 4);
  }

  testWidgets("a page's playback keeps the player's 30 s; covered it buffers 1 s and its engine session goes idle, "
      'shown again both come back', (tester) async {
    await host(tester);
    final page = playback()..start();
    await frames(tester);
    final player = players.single;
    final engine = engines.single;
    final controller = page.controller!;
    expect(player.forwardBuffers, isEmpty, reason: "the player's own default is a page's");
    expect(controller.idle, isFalse);

    page.cover();
    expect(player.forwardBuffers.last, PagePlayback.heldBuffer);
    expect(controller.idle, isTrue);
    expect(engine.idles.last.idle, isTrue);

    page.show(resuming: true);
    await tester.pump();
    expect(player.forwardBuffers, [PagePlayback.heldBuffer, PagePlayback.pageBuffer]);
    expect(controller.idle, isFalse);
    expect(engine.idles.last.idle, isFalse);
    await closed(tester, page);
  });

  testWidgets('a page covered before its player came in starts held: 1 s and idle', (tester) async {
    await host(tester);
    final page = playback()
      ..cover()
      ..start();
    await frames(tester);
    expect(players.single.forwardBuffers, [PagePlayback.heldBuffer]);
    expect(page.controller!.idle, isTrue);
    expect(players.single.loaded?.master, FakeEngine.masterOf('tok1'));
    expect(engines.single.idles.last, (token: 'tok1', idle: true), reason: 'its token starts in use on the engine');
    page.show(resuming: true);
    await tester.pump();
    expect(players.single.forwardBuffers.last, PagePlayback.pageBuffer);
    expect(page.controller!.idle, isFalse);
    expect(engines.single.idles.last, (token: 'tok1', idle: false));
    await closed(tester, page);
  });

  testWidgets("the route's cidHint asks that part's playurl beside the view, for its own open only", (tester) async {
    await host(tester);
    final view = http.gates[Canned.signedViewPath] = Completer<void>();
    final page = playback(route: const VideoRoute(bvid: bv, cidHint: p1))..start();
    await frames(tester);
    expect(page.controller!.video, isNull, reason: 'the view is still out');
    expect(playUrlCids(), ['$p1']);
    view.complete();
    await frames(tester);
    expect(page.controller!.page?.cid, p1);
    expect(playUrlCids(), ['$p1'], reason: 'the open kept what it asked beside the view');
    expect(loadParallel(), 'kept');

    final next = http.gates[Canned.signedViewPath] = Completer<void>();
    page.openOnPage('BV1EF411e9oF');
    await frames(tester);
    expect(playUrlCids(), ['$p1'], reason: 'another video opened on the page has no hint');
    next.complete();
    await frames(tester);
    await closed(tester, page);
  });

  testWidgets('without a hint or a part, nothing is asked before the view', (tester) async {
    await host(tester);
    final view = http.gates[Canned.signedViewPath] = Completer<void>();
    final page = playback(route: const VideoRoute(bvid: bv))..start();
    await frames(tester);
    expect(page.controller!.video, isNull);
    expect(playUrlCids(), isEmpty);
    view.complete();
    await frames(tester);
    expect(playUrlCids(), hasLength(1));
    await closed(tester, page);
  });

  testWidgets("推荐's card buffers 8 s; a page taking it over goes back to 30 s and its session is no longer idle", (
    tester,
  ) async {
    await host(tester);
    final card = playback(inline: true)..start();
    await frames(tester);
    final player = players.single;
    final controller = card.controller!;
    expect(player.forwardBuffers, [PagePlayback.inlineBuffer]);

    // The card's own pause marks it idle (feed_inline_player.dart); the page lifts it.
    controller.setIdle(true);
    card.attach(Object(), requestLogin: () {});
    await tester.pump();
    expect(card.inline, isFalse);
    expect(player.forwardBuffers, [PagePlayback.inlineBuffer, PagePlayback.pageBuffer]);
    expect(controller.idle, isFalse);
    expect(engines.single.idles.last.idle, isFalse);
    await closed(tester, card);
  });

  testWidgets('a card covered and shown again goes back to 8 s, not a page\'s 30', (tester) async {
    await host(tester);
    final card = playback(inline: true)..start();
    await frames(tester);
    card.cover();
    card.show(resuming: true);
    await tester.pump();
    expect(players.single.forwardBuffers, [
      PagePlayback.inlineBuffer,
      PagePlayback.heldBuffer,
      PagePlayback.inlineBuffer,
    ]);
    await closed(tester, card);
  });
}
