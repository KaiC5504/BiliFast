import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';

const heartbeatPath = '/x/click-interface/web/heartbeat';
const bv = 'BV1GJ411x7h7';
const p1 = 137649199;
const p2 = 137649200;
const cover = 'https://i0.hdslb.com/bfs/archive/cover.jpg';

void main() {
  late CannedHttp http;
  late FakePlayer player;
  late ManualClock time;
  late PlaybackController controller;
  late AppEnvironment environment;
  late GlobalKey<NavigatorState> nav;

  setUp(() {
    http = Canned.http()..routes[heartbeatPath] = (200, '{"code":0,"message":"0"}');
    player = FakePlayer();
    time = ManualClock(10000);
    nav = GlobalKey<NavigatorState>();
  });

  Future<void> host(
    WidgetTester tester, {
    Widget home = const SizedBox(),
    Future<PlaybackController> Function()? start,
    bool checkAccount = true,
  }) async {
    tester.view.physicalSize = const Size(440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    if (checkAccount) await environment.refreshAccount();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    controller = PlaybackController(
      client: environment.client,
      engine: FakeEngine(),
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
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: home,
      ),
    );
  }

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void pushVideo(VideoRoute route) =>
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => VideoPage(route: route))));

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('video-back')).last);
    await frames(tester, 20);
  }

  void position(double seconds) {
    time.advance(PlaybackClock.jumpSettleMs);
    player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));
  }

  /// Each heartbeat as (cid, played_time).
  List<(int, String)> sent() => [
    for (final request in http.to(heartbeatPath))
      (
        int.parse(Uri.splitQueryString(utf8.decode(request.body!))['cid']!),
        Uri.splitQueryString(utf8.decode(request.body!))['played_time']!,
      ),
  ];

  List<String> heartbeats() => [for (final (_, played) in sent()) played];

  testWidgets('S7 重试 after a failed open plays, and back still gives the player back', (tester) async {
    http.routes[Canned.playUrlPath] = (500, '');
    await host(tester);
    pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
    await frames(tester, 20);
    expect(find.byKey(const ValueKey('video-retry')), findsOneWidget);
    http.routes[Canned.playUrlPath] = (200, Canned.playUrl());
    await tester.tap(find.byKey(const ValueKey('video-retry')));
    await frames(tester, 20);
    expect(controller.phase, isNot(PlaybackPhase.failed));
    expect(player.loaded, isNotNull);
    await back(tester);
    expect(controller.video, isNull);
  });

  testWidgets('S8 back reports where playback stopped', (tester) async {
    await host(tester);
    pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
    await frames(tester, 20);
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(10);
    await back(tester);
    expect(heartbeats(), ['0', '10'], reason: 'leave() runs before close() clears the video');
  });

  testWidgets('S8b a login Bilibili no longer accepts reports nothing', (tester) async {
    http = Canned.http(loggedIn: false)..routes[heartbeatPath] = (200, '{"code":0}');
    await host(tester);
    expect(environment.account, isA<LoginExpired>());
    pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
    await frames(tester, 20);
    player.emit(const StatusChanged(PlayerStatus.playing));
    await back(tester);
    expect(heartbeats(), isEmpty);
  });

  testWidgets('heartbeats go out while the launch account check failed with a session in the jar', (tester) async {
    http.routes[Canned.navPath] = (500, '');
    await host(tester);
    expect(environment.account, isA<AccountUnknown>());
    // Back for the WBI keys the view and playurl calls sign with; the account stays unknown.
    http.routes[Canned.navPath] = (200, Canned.navLoggedIn);
    pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
    await frames(tester, 20);
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(10);
    await back(tester);
    expect(heartbeats(), ['0', '10']);
  });

  testWidgets('S15 a video page gone before the player started opens nothing', (tester) async {
    final ready = Completer<PlaybackController>();
    await host(tester, start: () => ready.future);
    pushVideo(const VideoRoute(bvid: bv));
    await frames(tester);
    nav.currentState!.pop();
    await frames(tester, 20);
    ready.complete(controller);
    await frames(tester);
    expect(controller.opens, 0);
    expect(http.to(Canned.signedViewPath), isEmpty);
  });

  testWidgets('a page popped while its video opens plays nothing', (tester) async {
    http.gates[Canned.playUrlPath] = Completer<void>();
    await host(tester);
    pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
    await frames(tester);
    expect(controller.video?.bvid, bv, reason: 'the view is in; playurl is held');
    await tester.tap(find.byKey(const ValueKey('video-back')));
    await tester.pump();
    expect(controller.video, isNull, reason: 'the player is given back at the pop, not after the transition');
    http.gates[Canned.playUrlPath]!.complete();
    await frames(tester, 20);
    expect(player.loaded, isNull);
    expect(controller.phase, PlaybackPhase.idle);
  });

  testWidgets('重试 starts the player again after a failed start, then plays', (tester) async {
    final failing = Completer<PlaybackController>();
    var attempts = 0;
    await host(tester, start: () => attempts++ == 0 ? failing.future : Future.value(controller));
    pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
    await frames(tester, 2);
    failing.completeError(StateError('no engine'));
    await frames(tester, 2);
    expect(find.textContaining('播放器启动失败'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video-retry')));
    await frames(tester, 20);
    expect(attempts, 2);
    expect(find.byKey(const ValueKey('video-error')), findsNothing);
    expect(controller.video?.bvid, bv);
    expect(player.loaded, isNotNull);
    await back(tester);
    expect(controller.video, isNull);
  });

  testWidgets('once the video has played, the cover stays gone through a replay', (tester) async {
    await host(tester);
    pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0, cover: cover));
    await frames(tester, 20);
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.descendant(of: find.byKey(const ValueKey('video-cover')), matching: find.byType(AnimatedOpacity)),
        )
        .opacity;
    expect(opacity(), 1);
    player.emit(const StatusChanged(PlayerStatus.playing));
    await frames(tester);
    expect(opacity(), 0);
    unawaited(controller.replay());
    await tester.pump();
    expect(controller.phase, PlaybackPhase.loading);
    expect(opacity(), 0);
    await frames(tester);
    expect(opacity(), 0);
    await back(tester);
  });

  testWidgets('the cover Hero keeps its element while the player starts and the video opens', (tester) async {
    final ready = Completer<PlaybackController>();
    await host(tester, start: () => ready.future);
    pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0, cover: cover));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    Element hero() => tester.element(find.descendant(of: find.byType(VideoPage), matching: find.byType(Hero)));
    final first = hero();
    ready.complete(controller);
    await frames(tester, 20);
    expect(find.byKey(const ValueKey('fake-video')), findsOneWidget, reason: 'the stage is in, under the cover');
    expect(identical(hero(), first), isTrue);
    player.emit(const StatusChanged(PlayerStatus.playing));
    await frames(tester);
    expect(identical(hero(), first), isTrue);
    await back(tester);
  });

  testWidgets('a push asks for at most two cover sizes: the card flies, the player box loads once', (tester) async {
    final requested = <String>[];
    debugNetworkImageHttpClientProvider = () => _RecordingHttpClient(requested);
    try {
      const route = VideoRoute(bvid: bv, cid: p1, start: 0, cover: cover);
      await host(
        tester,
        home: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              key: const ValueKey('card'),
              onTap: () => openVideoPage(context, route),
              child: SizedBox(
                width: 214,
                height: 160,
                child: Hero(tag: VideoRoute.coverTag(bv), child: const RemoteImage(cover)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(requested, [sizedImageUrl(cover, width: 240, height: 180)]);
      requested.clear();
      await tester.tap(find.byKey(const ValueKey('card')));
      final shuttle = find.byWidgetPredicate((widget) => widget is RemoteImage && widget.placeholder != null);
      var flew = false;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        flew |= shuttle.evaluate().isNotEmpty;
      }
      expect(flew, isTrue, reason: 'the card image flew under the player-sized cover');
      expect(requested.toSet().length, lessThanOrEqualTo(2));
      expect(requested.where((url) => url == sizedImageUrl(cover, width: 480, height: 300)), hasLength(1));
      await back(tester);
    } finally {
      debugNetworkImageHttpClientProvider = null;
      imageCache
        ..clear()
        ..clearLiveImages();
    }
  });

  group('a card opened during the pop', () {
    testWidgets('another part: the page reports its own part at its last position, nothing of the newer one',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await frames(tester, 20);
      player.emit(const StatusChanged(PlayerStatus.playing));
      position(10);
      await tester.tap(find.byKey(const ValueKey('video-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      pushVideo(const VideoRoute(bvid: bv, cid: p2, start: 0));
      await frames(tester, 20);
      expect(controller.page?.cid, p2);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester);
      expect(sent(), [(p1, '0'), (p1, '10'), (p2, '0')]);
      await back(tester);
    });

    testWidgets('the same card: the newer page\'s start never overwrites the position with 0', (tester) async {
      await host(tester);
      const route = VideoRoute(bvid: bv, cid: p1, start: 0);
      pushVideo(route);
      await frames(tester, 20);
      player.emit(const StatusChanged(PlayerStatus.playing));
      position(10);
      await tester.tap(find.byKey(const ValueKey('video-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      pushVideo(route);
      await frames(tester, 20);
      expect(controller.video?.bvid, bv);
      expect(heartbeats(), ['0', '10']);
      await back(tester);
      expect(heartbeats(), ['0', '10'], reason: 'the newer page never played');
    });
  });
}

/// Records the image URLs asked for and never answers, as covers still downloading.
final class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(this.requested);

  final List<String> requested;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requested.add('$url');
    return Completer<HttpClientRequest>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
