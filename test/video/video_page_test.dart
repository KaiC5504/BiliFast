import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/player_ui/end_screen_landscape.dart';
import 'package:bilifast/player_ui/end_screen_portrait.dart';
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/portrait_controls.dart';
import 'package:bilifast/player_ui/vertical_chrome.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/page_session.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_player_area.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/fake_player_session.dart';

const heartbeatPath = '/x/click-interface/web/heartbeat';
const bv = 'BV1GJ411x7h7';
const p1 = 137649199;
const p2 = 137649200;
const cover = 'https://i0.hdslb.com/bfs/archive/cover.jpg';

/// iPhone 17 Pro Max in points, with its safe areas, as the official app's reference screenshots were taken.
const portrait = Size(440, 956);
const landscape = Size(956, 440);
const portraitInsets = FakeViewPadding(top: 62, bottom: 34);
const landscapeInsets = FakeViewPadding(left: 62, right: 62, bottom: 21);

/// Records each page's begin and end, naming pages in the order they first began.
class SpyOrientation extends OrientationController {
  final log = <String>[];
  final _names = <Object, String>{};

  String _name(Object owner) => _names.putIfAbsent(owner, () => 'page${_names.length + 1}');

  @override
  void begin(Object owner, {required bool videoIsVertical}) {
    log.add('begin ${_name(owner)}${videoIsVertical ? ' vertical' : ''}');
    super.begin(owner, videoIsVertical: videoIsVertical);
  }

  @override
  void end(Object owner) {
    log.add('end ${_name(owner)}');
    super.end(owner);
  }
}

void main() {
  late CannedHttp http;
  late FakePlayer player;
  late ManualClock time;
  late PlaybackController controller;
  late AppEnvironment environment;
  late GlobalKey<NavigatorState> nav;
  late SpyOrientation orientation;

  /// Each page's session and the open it was handed, in the order the pages made them.
  late List<FakePlayerSession> sessions;
  late List<SessionOpen> sessionOpens;

  setUp(() {
    http = Canned.http()..routes[heartbeatPath] = (200, '{"code":0,"message":"0"}');
    player = FakePlayer();
    time = ManualClock(10000);
    nav = GlobalKey<NavigatorState>();
    orientation = SpyOrientation();
    sessions = [];
    sessionOpens = [];
  });

  PlayerSession fakeSession({
    required PlaybackController controller,
    required AppServices services,
    required SessionOpen open,
    required void Function(double seconds) onSeeked,
  }) {
    final session = FakePlayerSession(player: player);
    sessions.add(session);
    sessionOpens.add(open);
    return session;
  }

  void screen(WidgetTester tester, Size size, FakeViewPadding insets) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
  }

  Future<void> host(
    WidgetTester tester, {
    Widget home = const SizedBox(),
    Future<PlaybackController> Function()? start,
    bool checkAccount = true,
  }) async {
    screen(tester, portrait, portraitInsets);
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
      device: PlayerDevice(orientation: orientation, controls: NoDeviceControls()),
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

  void pushVideo(VideoRoute route) => unawaited(
    nav.currentState!.push(SwipeBackPageRoute<void>(builder: (_) => VideoPage(route: route, createSession: fakeSession))),
  );

  /// The top page's back, as the chrome's arrow and the system's back both pop it.
  Future<void> back(WidgetTester tester) async {
    unawaited(nav.currentState!.maybePop());
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

  /// The player interface the top page handed its chrome and panels.
  PlayerUi ui(WidgetTester tester) => tester.widget<PanelLayer>(find.byType(PanelLayer).last).ui;

  Rect area(WidgetTester tester) => tester.getRect(find.byType(VideoPlayerArea).last);

  /// A page with its video loaded and known to the session, so it has taken the orientation.
  Future<void> opened(WidgetTester tester, {bool vertical = false, int page = 0}) async {
    await frames(tester, 20);
    sessions[page]
      ..video = controller.video
      ..isVertical = vertical
      ..changed();
    await tester.pump();
  }

  Future<void> rotate(WidgetTester tester, Presentation to) async {
    switch (to) {
      case Presentation.inline:
        screen(tester, portrait, portraitInsets);
        orientation.exitToInline();
      case Presentation.landscape:
        screen(tester, landscape, landscapeInsets);
        orientation.enterLandscape();
      case Presentation.vertical:
        screen(tester, portrait, portraitInsets);
        orientation.enterVertical();
    }
    await frames(tester, 2);
  }

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
    expect(sessions, hasLength(1), reason: 'one session per page, through 重试');
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
    expect(find.byKey(const ValueKey('video-back')), findsOneWidget, reason: 'no chrome yet, so the page has its own');
    await tester.tap(find.byKey(const ValueKey('video-back')));
    await frames(tester, 20);
    expect(find.byType(VideoPage), findsNothing);
    ready.complete(controller);
    await frames(tester);
    expect(controller.opens, 0);
    expect(sessions, isEmpty);
    expect(http.to(Canned.signedViewPath), isEmpty);
  });

  testWidgets('a page popped while its video opens plays nothing', (tester) async {
    http.gates[Canned.playUrlPath] = Completer<void>();
    await host(tester);
    pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
    await frames(tester);
    expect(controller.video?.bvid, bv, reason: 'the view is in; playurl is held');
    unawaited(nav.currentState!.maybePop());
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
    expect(find.byKey(const ValueKey('fake-video')), findsOneWidget, reason: 'the video is in, under the cover');
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
              // openVideoPage's push, with the test's session.
              onTap: () => Navigator.of(context).push(
                SwipeBackPageRoute<void>(builder: (_) => VideoPage(route: route, createSession: fakeSession)),
              ),
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
      unawaited(nav.currentState!.maybePop());
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
      unawaited(nav.currentState!.maybePop());
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

  group('full screen is the same page laid out again', () {
    testWidgets('inline: black under the status bar, the 16:9 player, the details below (screen 03)', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      expect(area(tester), const Rect.fromLTWH(0, 62, 440, 440 / BiliMetrics.videoAspect));
      expect(tester.getTopLeft(find.byKey(const ValueKey('video-title'))).dy, greaterThan(62 + 247.5));
      expect(find.byType(PortraitControls), findsOneWidget);
      expect(
        MediaQuery.paddingOf(tester.element(find.byType(PortraitControls))),
        EdgeInsets.zero,
        reason: 'the small player sits below the status bar with no insets of its own',
      );
      final black = tester.widget<ColoredBox>(
        find.ancestor(of: find.byType(VideoPlayerArea), matching: find.byType(ColoredBox)).first,
      );
      expect(black.color, BiliColors.videoBackground);
      expect(
        tester.getRect(find.ancestor(of: find.byType(VideoPlayerArea), matching: find.byType(ColoredBox)).first),
        const Rect.fromLTWH(0, 0, 440, 62 + 440 / BiliMetrics.videoAspect),
      );
      await back(tester);
    });

    testWidgets('landscape: the player fills the screen around the notch, the details out of sight (screen 04)',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      await rotate(tester, Presentation.landscape);
      expect(area(tester), const Rect.fromLTWH(0, 0, 956, 440));
      expect(find.byType(LandscapeChrome), findsOneWidget);
      expect(find.byType(PortraitControls), findsNothing);
      expect(find.byKey(const ValueKey('video-title')), findsNothing, reason: 'offstage');
      expect(
        MediaQuery.paddingOf(tester.element(find.byType(LandscapeChrome))),
        const EdgeInsets.fromLTRB(62, 0, 62, 21),
        reason: 'the chrome keeps clear of the notch and the home indicator itself',
      );
      expect(tester.getRect(find.byKey(const ValueKey('fake-video'))), const Rect.fromLTWH(0, 0, 956, 440));

      await rotate(tester, Presentation.inline);
      expect(area(tester), const Rect.fromLTWH(0, 62, 440, 440 / BiliMetrics.videoAspect));
      expect(find.byKey(const ValueKey('video-title')), findsOneWidget);
      await back(tester);
    });

    testWidgets('竖屏: the player fills the upright screen, a landscape video above the middle (screen 09)',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      await rotate(tester, Presentation.vertical);
      expect(area(tester), const Rect.fromLTWH(0, 0, 440, 956));
      expect(find.byType(VerticalChrome), findsOneWidget);
      expect(MediaQuery.paddingOf(tester.element(find.byType(VerticalChrome))), const EdgeInsets.only(top: 62, bottom: 34));
      // The surface runs to 83% of the screen, so a fitted 16:9 picture centres at 41.5% as in the screenshot.
      final surface = tester.getRect(find.byKey(const ValueKey('fake-video')));
      expect(surface, Rect.fromLTWH(0, 0, 440, 956 * BiliMetrics.verticalVideoCentre * 2));
      expect(surface.center.dy, closeTo(397, 1));

      sessions.single
        ..isVertical = true
        ..changed();
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey('fake-video'))), const Rect.fromLTWH(0, 0, 440, 956));
      expect(orientation.videoIsVertical, isTrue, reason: 'the page passes the video\'s shape on');
      await rotate(tester, Presentation.inline);
      await back(tester);
    });

    testWidgets('the native view is built once and keeps its element through every layout and chrome change',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final first = tester.element(find.byKey(const ValueKey('fake-video')));
      void same() => expect(identical(tester.element(find.byKey(const ValueKey('fake-video'))), first), isTrue);
      await rotate(tester, Presentation.landscape);
      same();
      await rotate(tester, Presentation.inline);
      same();
      await rotate(tester, Presentation.vertical);
      same();
      sessions.single
        ..ended = true
        ..changed();
      await tester.pump();
      same();
      await rotate(tester, Presentation.landscape);
      same();
      ui(tester).panels.open(PlayerPanel.more);
      ui(tester).chrome.hide();
      await tester.pump();
      same();
      await rotate(tester, Presentation.inline);
      same();
      await back(tester);
    });

    testWidgets('the right chrome and end screen for each presentation', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      sessions.single
        ..ended = true
        ..changed();
      await tester.pump();
      expect(find.byType(EndScreenPortrait), findsOneWidget);
      expect(find.byType(PortraitControls), findsNothing);
      await rotate(tester, Presentation.landscape);
      expect(find.byType(EndScreenLandscape), findsOneWidget);
      expect(find.byType(EndScreenPortrait), findsNothing);
      expect(tester.getRect(find.byType(EndScreenLandscape)), const Rect.fromLTWH(0, 0, 956, 440));
      sessions.single
        ..ended = false
        ..changed();
      await tester.pump();
      expect(find.byType(LandscapeChrome), findsOneWidget);
      expect(find.byType(EndScreenLandscape), findsNothing);
      await rotate(tester, Presentation.inline);
      await back(tester);
    });

    testWidgets('panels go over the whole page, inline and full screen', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      expect(tester.getRect(find.byType(PanelLayer)), const Rect.fromLTWH(0, 0, 440, 956));
      await rotate(tester, Presentation.landscape);
      expect(tester.getRect(find.byType(PanelLayer)), const Rect.fromLTWH(0, 0, 956, 440));
      final stack = tester.widget<Stack>(
        find.ancestor(of: find.byType(PanelLayer), matching: find.byType(Stack)).first,
      );
      expect(stack.children.last.key, const ValueKey('video-panels'), reason: 'above the player and the details');
      await rotate(tester, Presentation.inline);
      await back(tester);
    });

    testWidgets('the chrome hides by itself only while playing, not scrubbing and with no panel open', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final chrome = ui(tester).chrome;
      final session = sessions.single;
      expect(chrome.autoHide, isFalse);
      player.emit(const StatusChanged(PlayerStatus.playing));
      expect(chrome.autoHide, isTrue);
      session.scrub(30);
      expect(chrome.autoHide, isFalse);
      session.cancelScrub();
      expect(chrome.autoHide, isTrue);
      ui(tester).panels.open(PlayerPanel.speed);
      expect(chrome.autoHide, isFalse);
      ui(tester).panels.close();
      expect(chrome.autoHide, isTrue);
      player.emit(const StatusChanged(PlayerStatus.paused));
      expect(chrome.autoHide, isFalse);
      await back(tester);
    });

    testWidgets('two stacked pages: the latest begin wins and the page below takes the orientation back',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await frames(tester, 20);
      expect(orientation.log, isEmpty, reason: 'not before the video is known');
      await opened(tester);
      expect(orientation.log, ['begin page1']);

      pushVideo(const VideoRoute(bvid: bv, cid: p2, start: 0));
      await opened(tester, page: 1, vertical: true);
      expect(orientation.log, ['begin page1', 'begin page2 vertical']);
      sessions.first
        ..isVertical = true
        ..video = null
        ..changed();
      await tester.pump();
      expect(orientation.log, hasLength(2), reason: 'the covered page leaves the orientation alone');

      await back(tester);
      expect(orientation.log, ['begin page1', 'begin page2 vertical', 'end page2', 'begin page1']);
      expect(orientation.videoIsVertical, isFalse, reason: 'the page below begins with its own video\'s shape');
      await back(tester);
      expect(orientation.log.last, 'end page1');
    });

    testWidgets('in full screen the edge swipe and a pop go back to the small player, not off the page',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      await rotate(tester, Presentation.landscape);
      expect(tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).last).canPop, isFalse);
      await tester.dragFrom(const Offset(2, 220), const Offset(600, 0));
      await frames(tester, 20);
      expect(find.byType(VideoPage), findsOneWidget, reason: 'no swipe back in full screen');

      unawaited(nav.currentState!.maybePop());
      await frames(tester, 2);
      expect(find.byType(VideoPage), findsOneWidget);
      expect(orientation.presentation, Presentation.inline);
      expect(controller.video, isNotNull, reason: 'the page kept the player');
      expect(tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).last).canPop, isTrue);
      screen(tester, portrait, portraitInsets);
      await back(tester);
      expect(find.byType(VideoPage), findsNothing);
    });

    testWidgets('the back arrow: off the page inline, to the small player from full screen', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      for (final full in [Presentation.landscape, Presentation.vertical]) {
        await rotate(tester, full);
        ui(tester).onBack();
        await frames(tester, 2);
        expect(orientation.presentation, Presentation.inline);
        expect(find.byType(VideoPage), findsOneWidget);
        screen(tester, portrait, portraitInsets);
      }
      ui(tester).onBack();
      await frames(tester, 20);
      expect(find.byType(VideoPage), findsNothing);
      expect(controller.video, isNull);
    });

    testWidgets('full screen keeps the status bar and hides the home indicator; inline gives both back',
        (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method.startsWith('SystemChrome.setEnabledSystemUI')) calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      expect(calls, isEmpty);
      await rotate(tester, Presentation.landscape);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'SystemChrome.setEnabledSystemUIOverlays');
      expect(calls.single.arguments, ['SystemUiOverlay.top']);
      await rotate(tester, Presentation.inline);
      expect(calls.last.method, 'SystemChrome.setEnabledSystemUIMode');
      expect(calls.last.arguments, 'SystemUiMode.edgeToEdge');
      expect(calls, hasLength(2));
      await back(tester);
    });
  });

  group('the session', () {
    testWidgets('its open plays another part on the same page, with its own watch reports and title', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0, title: '卡片标题'));
      await opened(tester);
      expect(find.text('测试视频'), findsOneWidget);
      player.emit(const StatusChanged(PlayerStatus.playing));
      position(10);
      sessionOpens.single(bv, cid: p2);
      await frames(tester, 20);
      expect(controller.page?.cid, p2);
      expect(find.byType(VideoPage), findsOneWidget);
      expect(sessions, hasLength(1));
      expect(find.text('UP主 · P2 第二集'), findsOneWidget);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester);
      expect(sent(), [(p1, '0'), (p1, '10'), (p2, '0')]);
      expect(find.byKey(const ValueKey('fake-video')), findsOneWidget);

      await back(tester);
      final opens = controller.opens;
      sessionOpens.single(bv, cid: p1);
      await frames(tester);
      expect(controller.opens, opens, reason: 'a page that left opens nothing');
    });

    testWidgets('another video clears the last one\'s title until its own arrives', (tester) async {
      final view = Completer<void>();
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0, title: '卡片标题'));
      await opened(tester);
      expect(find.text('测试视频'), findsOneWidget);
      http.gates[Canned.signedViewPath] = view;
      sessionOpens.single('BV1xx411c7mD');
      await frames(tester);
      expect(find.text('测试视频'), findsNothing);
      expect(find.text('卡片标题'), findsNothing, reason: 'the card\'s title is the first video\'s');
      view.complete();
      await frames(tester, 20);
      expect(find.text('测试视频'), findsOneWidget, reason: 'the canned view answers every bvid');
      await back(tester);
    });

    testWidgets('is made once the player is the page\'s and disposed when the page leaves', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await frames(tester, 20);
      expect(sessions, hasLength(1));
      await back(tester);
      expect(() => sessions.single.addListener(() {}), throwsFlutterError);
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
