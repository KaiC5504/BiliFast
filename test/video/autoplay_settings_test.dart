import 'dart:async';

import 'package:bili_core/api.dart' show VideoCard;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/settings/autoplay_policy.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/intro/intro_tab.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/page_playback.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/fake_video_actions.dart';
import '../support/look_alike.dart' show showAsPad;

const heartbeatPath = '/x/click-interface/web/heartbeat';
const bv = 'BV1GJ411x7h7';
const other = 'BV1xx411c7mD';
const p1 = 137649199;
const p2 = 137649200;
const cover = 'https://i0.hdslb.com/bfs/archive/cover.jpg';

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

/// 自动播放设置's video page side (172, 174): 详情页直接播放 (and 流量网络下自动播放) opening a page paused with its
/// cover and ▶, 详情页直接全屏播放 taking a page opened to full screen, and 应用外自动小窗播放 keeping auto picture in
/// picture off, on the app's own playback and session.
void main() {
  late CannedHttp http;
  late AppPlayback playback;
  late AppServices services;
  late OrientationController orientation;
  late PlayerPrefs prefs;
  late List<PlaybackController> controllers;
  late List<FakePlayer> players;
  late MemorySink logs;
  Completer<void>? createGate;

  setUp(() {
    http = Canned.http()..routes[heartbeatPath] = (200, '{"code":0,"message":"0"}');
    orientation = OrientationController();
    controllers = [];
    players = [];
    createGate = null;
    final savedPrefs = PlayerPrefs.shared;
    final savedPolicy = AutoplayPolicy.shared;
    PlayerPrefs.shared = prefs = PlayerPrefs.memory();
    AutoplayPolicy.shared = AutoplayPolicy.fixed();
    logs = MemorySink();
    Logger.shared.add(logs);
    addTearDown(() {
      PlayerPrefs.shared = savedPrefs;
      AutoplayPolicy.shared = savedPolicy;
      Logger.shared.remove(logs);
    });
  });

  PageDetails fakeDetails({
    required PlayerSession session,
    required AppServices services,
    required void Function(String message) toast,
    required VoidCallback requestLogin,
    required Listenable logins,
  }) => FakePageDetails();

  late VideoPageOpener openPage;
  Widget page(VideoRoute route) =>
      VideoPage(route: route, createSession: pageSession, createDetails: fakeDetails, openPage: openPage);
  Future<void> pushing(BuildContext context, VideoRoute route) =>
      Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => page(route)));
  openPage = pushing;

  Future<void> host(WidgetTester tester, {bool pad = false}) async {
    if (pad) {
      showAsPad(tester);
    } else {
      tester.view
        ..physicalSize = const Size(440, 956)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: 62, bottom: 34)
        ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.reset);
    }
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final time = ManualClock(10000);
    playback = AppPlayback(() async {
      if (createGate case final gate?) await gate.future;
      final player = FakePlayer();
      players.add(player);
      final controller = PlaybackController(
        client: environment.client,
        engine: FakeEngine(),
        player: player,
        clock: time.clock,
        now: () => now,
        startTimer: FakeTimers().start,
        logger: logger,
      );
      controllers.add(controller);
      return controller;
    });
    addTearDown(playback.dispose);
    services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(orientation: orientation, controls: NoDeviceControls()),
      loginGate: _NoLogin(),
      pageApi: FakePageApi(),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: services.navigator,
        navigatorObservers: [pageRoutes],
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

  void push(Route<void> route) => unawaited(services.navigator.currentState!.push(route));

  /// A page pushed as a list opens one, its video loaded.
  Future<FakePlayer> open(WidgetTester tester, VideoRoute route) async {
    push(SwipeBackPageRoute<void>(builder: (_) => page(route)));
    await frames(tester, 20);
    return players.last;
  }

  /// A plain page over the video page, as 设置 or a space goes over it.
  void coverPage(WidgetTester tester) => push(SwipeBackPageRoute<void>(builder: (_) => const Scaffold()));

  /// The top page's back; from full screen, back to the small player first, as the page's back goes.
  Future<void> back(WidgetTester tester) async {
    if (orientation.presentation.fullScreen) {
      orientation.exitToInline();
      await frames(tester, 4);
    }
    unawaited(services.navigator.currentState!.maybePop());
    await frames(tester, 20);
  }

  PlayerUi ui(WidgetTester tester) => tester.widget<PanelLayer>(find.byType(PanelLayer).last).ui;

  /// Each [msg] logged, by its reason, else its video.
  List<String> messages(String msg) => [
    for (final event in logs.events)
      if (event.msg == msg)
        switch (event.f['reason'] ?? event.f['bvid']) {
          LogString(:final value) => value,
          final other => '$other',
        },
  ];

  double coverOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(of: find.byKey(const ValueKey('video-cover')), matching: find.byType(AnimatedOpacity)),
      )
      .opacity;

  List<String> autoPip(FakePlayer player) => [
    for (final call in player.calls)
      if (call.startsWith('pip auto')) call,
  ];

  /// 推荐's big card's playback, played inline and, if [paused], then paused by the card's rule, handed over as
  /// FeedInlinePlayback.handOver does: the hold lifted to play, and played.
  Future<PagePlayback> handedOver(WidgetTester tester, {bool paused = false}) async {
    final inline = PagePlayback(
      services: services,
      route: const VideoRoute(bvid: bv, cid: p1, start: 0),
      createSession: pageSession,
      restorePage: page,
      inline: true,
    )..start();
    await frames(tester, 10);
    final controller = controllers.single;
    final player = players.single;
    player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump();
    if (paused) {
      controller.holdAutoplay(true);
      await player.pause();
      player.emit(const StatusChanged(PlayerStatus.paused));
      await tester.pump();
    }
    controller.holdAutoplay(false, play: true);
    await player.play();
    player.calls.clear();
    return inline;
  }

  group('推荐\'s big card handing its playback to the page', () {
    for (final detail in [true, false]) {
      testWidgets('playing when tapped, it plays on with sound whatever 详情页直接播放 says (${detail ? 'on' : 'off'})', (
        tester,
      ) async {
        prefs.detailAutoplay = detail;
        await host(tester);
        final inline = await handedOver(tester);
        push(
          SwipeBackPageRoute<void>(
            builder: (_) => page(VideoRoute(bvid: bv, playback: inline)),
          ),
        );
        await frames(tester, 20);
        final player = players.single;
        expect(players, hasLength(1), reason: 'the same player');
        expect(player.calls.where((call) => call.startsWith('load')), isEmpty, reason: 'no reload');
        expect(player.calls, isNot(contains('pause')));
        expect(player.calls, contains('muted false'));
        expect(messages('video open paused'), isEmpty);
        await back(tester);
      });
    }

    testWidgets('paused by its rule, 详情页直接播放 off keeps it paused on the page', (tester) async {
      prefs.detailAutoplay = false;
      await host(tester);
      final inline = await handedOver(tester, paused: true);
      push(
        SwipeBackPageRoute<void>(
          builder: (_) => page(VideoRoute(bvid: bv, playback: inline)),
        ),
      );
      await frames(tester, 20);
      final player = players.single;
      expect(player.calls, contains('pause'));
      expect(controllers.single.loadWillPlay, isFalse);
      expect(autoPip(player), isNot(contains('pip auto true')), reason: 'its first play on the page turns it on');
      expect(messages('video open paused'), ['detail']);

      await tester.tap(find.byKey(const ValueKey('portrait-play')));
      await tester.pump();
      expect(player.calls.last, 'play');
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 2);
      expect(autoPip(player), ['pip auto true']);
      await back(tester);
    });

    testWidgets('paused by its rule, 详情页直接播放 on resumes it on the page', (tester) async {
      await host(tester);
      final inline = await handedOver(tester, paused: true);
      push(
        SwipeBackPageRoute<void>(
          builder: (_) => page(VideoRoute(bvid: bv, playback: inline)),
        ),
      );
      await frames(tester, 20);
      expect(players.single.calls, isNot(contains('pause')));
      expect(messages('video open paused'), isEmpty);
      await back(tester);
    });
  });

  group('详情页直接播放', () {
    testWidgets('off, a page opened from a list loads paused under its cover with ▶, and ▶ plays it', (tester) async {
      prefs.detailAutoplay = false;
      await host(tester);
      final player = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0, cover: cover));
      expect(player.loaded?.autoplay, isFalse);
      expect(messages('video open paused'), ['detail']);
      player
        ..emit(const DurationChanged(712))
        ..emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 4);
      expect(coverOpacity(tester), 1, reason: 'loaded, but the cover stays until it plays');
      expect(find.byKey(const ValueKey('video-loading')), findsNothing);
      expect(ui(tester).chrome.visible, isTrue, reason: 'the paused controls');
      expect(find.bySemanticsLabel('播放'), findsOneWidget);
      await frames(tester, 80);
      expect(ui(tester).chrome.visible, isTrue, reason: 'paused, they never hide by themselves');
      expect(player.calls, isNot(contains('play')));

      await tester.tap(find.byKey(const ValueKey('portrait-play')));
      await tester.pump();
      expect(player.calls, contains('play'));
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 6);
      expect(coverOpacity(tester), 0);
      await back(tester);
    });

    testWidgets('on mobile data with 流量网络下自动播放 off it loads paused; on, or on Wi-Fi, it plays', (tester) async {
      AutoplayPolicy.shared = AutoplayPolicy.fixed(onCellular: true);
      prefs.cellularAutoplay = false;
      await host(tester);
      expect((await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0))).loaded?.autoplay, isFalse);
      expect(messages('video open paused'), ['cellular']);
      await back(tester);

      prefs.cellularAutoplay = true;
      expect((await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0))).loaded?.autoplay, isTrue);
      await back(tester);

      prefs.cellularAutoplay = false;
      AutoplayPolicy.shared = AutoplayPolicy.fixed();
      expect((await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0))).loaded?.autoplay, isTrue);
      expect(messages('video open paused'), hasLength(1));
      await back(tester);
    });

    testWidgets('opened paused it still starts where Bilibili saw it last', (tester) async {
      prefs.detailAutoplay = false;
      http.routes[Canned.playUrlPath] = (
        200,
        Canned.playUrl().replaceFirst('"quality":120,', '"quality":120,"last_play_time":45000,"last_play_cid":$p1,'),
      );
      await host(tester);
      final player = await open(tester, const VideoRoute(bvid: bv, cid: p1));
      expect((player.loaded?.autoplay, player.loaded?.startSeconds), (false, 45));
      await back(tester);
    });

    testWidgets('a video opened on the page in its place opens paused too; another part chosen on it plays', (
      tester,
    ) async {
      prefs.detailAutoplay = false;
      await host(tester);
      unawaited(openVideoPage(services.navigator.currentContext!, const VideoRoute(bvid: bv, cid: p1, start: 0)));
      await frames(tester, 20);
      expect(players.single.loaded?.autoplay, isFalse);
      http.routes[Canned.signedViewPath] = (200, Canned.view.replaceAll(bv, other));
      tester
          .widget<IntroTab>(find.byType(IntroTab).last)
          .onOpenRelated(
            const VideoCard(
              aid: 2,
              bvid: other,
              cid: 3,
              title: '相关视频',
              cover: '',
              duration: 60,
              ownerMid: 4,
              ownerName: 'UP',
              views: 1,
              danmaku: 1,
              likes: 1,
            ),
          );
      await frames(tester, 20);
      expect(tester.widget<VideoPage>(find.byType(VideoPage)).route.bvid, other, reason: 'replaced, not stacked');
      final replaced = players.last;
      expect(players, hasLength(2));
      expect(replaced.loaded?.autoplay, isFalse);

      ui(tester).session.playEpisode(const Episode(bvid: other, cid: p2, title: 'P2 第二集', current: false));
      await frames(tester, 10);
      expect(controllers.last.page?.cid, p2);
      expect(replaced.loaded?.autoplay, isTrue, reason: 'a part picked on the page plays');
      await back(tester);
    });

    testWidgets('covered before its player came, a page opened paused stays paused when shown', (tester) async {
      prefs.detailAutoplay = false;
      createGate = Completer<void>();
      await host(tester);
      push(
        SwipeBackPageRoute<void>(
          builder: (_) => page(const VideoRoute(bvid: bv, cid: p1, start: 0)),
        ),
      );
      await frames(tester, 2);
      coverPage(tester);
      await frames(tester, 10);
      createGate!.complete();
      await frames(tester, 20);
      final player = players.single;
      expect(player.loaded?.autoplay, isFalse);
      await back(tester);
      expect(player.calls, isNot(contains('play')));
      await back(tester);
    });

    testWidgets('重试 after a failed paused open opens it paused again', (tester) async {
      prefs.detailAutoplay = false;
      http.routes[Canned.playUrlPath] = (500, '');
      await host(tester);
      final player = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
      expect(find.byKey(const ValueKey('video-retry')), findsOneWidget);
      http.routes[Canned.playUrlPath] = (200, Canned.playUrl());
      await tester.tap(find.byKey(const ValueKey('video-retry')));
      await frames(tester, 20);
      expect(player.loaded?.autoplay, isFalse);
      await back(tester);
    });
  });

  group('详情页直接全屏播放', () {
    testWidgets('on, a page opened goes to full screen once its video is known; back returns to the page, for good', (
      tester,
    ) async {
      prefs.detailFullScreen = true;
      await host(tester);
      await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
      expect(orientation.presentation, Presentation.landscape);
      expect(messages('video open full screen'), [bv]);

      ui(tester).onBack();
      await frames(tester, 4);
      expect(orientation.presentation, Presentation.inline);
      expect(find.byType(VideoPage), findsOneWidget, reason: 'back from it is the page, as usual');

      coverPage(tester);
      await frames(tester, 10);
      await back(tester);
      players.single.emit(const SizeChanged(width: 3840, height: 2160));
      await frames(tester, 4);
      expect(orientation.presentation, Presentation.inline, reason: 'once per open');
      expect(messages('video open full screen'), hasLength(1));
      await back(tester);
    });

    testWidgets('an upright video takes 竖屏', (tester) async {
      prefs.detailFullScreen = true;
      http.routes[Canned.playUrlPath] = (
        200,
        Canned.playUrl()
            .replaceAll('"width":3840,"height":2160', '"width":2160,"height":3840')
            .replaceAll('"width":1920,"height":1080', '"width":1080,"height":1920'),
      );
      await host(tester);
      await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
      expect(orientation.presentation, Presentation.vertical);
      await back(tester);
    });

    testWidgets('off, a page opens on the small player', (tester) async {
      await host(tester);
      await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
      expect(orientation.presentation, Presentation.inline);
      expect(messages('video open full screen'), isEmpty);
      await back(tester);
    });

    testWidgets('already in full screen when its shape comes, it stays as it is', (tester) async {
      prefs.detailFullScreen = true;
      http.gates[Canned.playUrlPath] = Completer<void>();
      await host(tester);
      push(
        SwipeBackPageRoute<void>(
          builder: (_) => page(const VideoRoute(bvid: bv, cid: p1, start: 0)),
        ),
      );
      await frames(tester, 20);
      expect(controllers.single.video?.bvid, bv, reason: 'the view is in, the shape not yet');
      expect(orientation.presentation, Presentation.inline);
      orientation.enterLandscape();
      await frames(tester, 2);
      http.gates[Canned.playUrlPath]!.complete();
      await frames(tester, 10);
      expect(controllers.single.videoSize, isNotNull);
      expect(orientation.presentation, Presentation.landscape);
      expect(messages('video open full screen'), isEmpty);
      await back(tester);
    });

    testWidgets('not for a page the small window brings back, nor one started over after a lost restore', (
      tester,
    ) async {
      await host(tester);
      final first = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
      first.emit(const StatusChanged(PlayerStatus.playing));
      first.emit(const PictureInPictureChanged(true));
      await back(tester);
      prefs.detailFullScreen = true;
      prefs.detailAutoplay = false;
      first
        ..emit(const PictureInPictureRestore())
        ..emit(const PictureInPictureChanged(false));
      await frames(tester, 20);
      expect(ModalRoute.of(tester.element(find.byType(VideoPage))), isA<RestoredPageRoute<void>>());
      expect(orientation.presentation, Presentation.inline);

      first.emit(const PictureInPictureChanged(true));
      await back(tester);
      final kept = services.pipKeeper.kept! as PagePlayback;
      services.pipKeeper.release();
      await tester.pump();
      push(
        RestoredPageRoute<void>(
          builder: (_) => page(VideoRoute(bvid: kept.bvid, playback: kept)),
        ),
      );
      await frames(tester, 20);
      expect(players, hasLength(2), reason: 'started over on a new player');
      expect(players.last.loaded?.autoplay, isTrue, reason: 'a restore plays as it did');
      expect(orientation.presentation, Presentation.inline);
      expect(messages('video open full screen'), isEmpty);
      await back(tester);
    });

    testWidgets('on the iPad too', (tester) async {
      prefs.detailFullScreen = true;
      await host(tester, pad: true);
      await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
      expect(orientation.presentation, Presentation.landscape);
      await back(tester);
    });

    testWidgets('a page 推荐\'s big card hands its video to is a page opened', (tester) async {
      prefs.detailFullScreen = true;
      await host(tester);
      final inline = await handedOver(tester);
      push(
        SwipeBackPageRoute<void>(
          builder: (_) => page(VideoRoute(bvid: bv, playback: inline)),
        ),
      );
      await frames(tester, 20);
      expect(orientation.presentation, Presentation.landscape);
      await back(tester);
    });
  });

  group('应用外自动小窗播放', () {
    testWidgets('off, auto picture in picture never turns on; ⋮\'s 小窗播放 still starts the small window', (tester) async {
      prefs.autoPip = false;
      await host(tester);
      final player = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 2);
      coverPage(tester);
      await frames(tester, 10);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await back(tester);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 2);
      expect(autoPip(player), isNot(contains('pip auto true')));

      expect(await ui(tester).session.startPictureInPicture(), isNull);
      expect(player.calls, contains('pip start'));
      await back(tester);
    });

    testWidgets('changed while 设置 covers the page, it holds once the page shows', (tester) async {
      await host(tester);
      final player = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 2);
      expect(autoPip(player), ['pip auto true']);

      coverPage(tester);
      await frames(tester, 10);
      player.emit(const StatusChanged(PlayerStatus.paused));
      prefs.autoPip = false;
      player.calls.clear();
      await back(tester);
      expect(player.calls, contains('play'), reason: 'it was playing, so it plays on');
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 2);
      expect(autoPip(player), ['pip auto false']);

      coverPage(tester);
      await frames(tester, 10);
      player.emit(const StatusChanged(PlayerStatus.paused));
      prefs.autoPip = true;
      player.calls.clear();
      await back(tester);
      expect(autoPip(player), ['pip auto true']);
      await back(tester);
    });

    testWidgets('turned on while covered after its first play went without, the next play turns it on', (tester) async {
      prefs.autoPip = false;
      await host(tester);
      final player = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 2);
      coverPage(tester);
      await frames(tester, 10);
      player.emit(const StatusChanged(PlayerStatus.paused));
      prefs.autoPip = true;
      player.calls.clear();
      await back(tester);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 2);
      expect(autoPip(player), ['pip auto true']);
      await back(tester);
    });

    testWidgets('off, a page taking 推荐\'s playing card over leaves it off', (tester) async {
      prefs.autoPip = false;
      await host(tester);
      final inline = await handedOver(tester);
      final player = players.single;
      push(
        SwipeBackPageRoute<void>(
          builder: (_) => page(VideoRoute(bvid: bv, playback: inline)),
        ),
      );
      await frames(tester, 20);
      expect(autoPip(player), isNot(contains('pip auto true')));
      await back(tester);
    });
  });
}
