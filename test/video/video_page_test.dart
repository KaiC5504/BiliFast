import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart' show OfficialKind, UploaderCard, VideoCard, VideoDetail, VideoOwner, VideoStat;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
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
import 'package:bilifast/video/actions/action_overlays.dart';
import 'package:bilifast/video/actions/video_actions.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/intro/intro_tab.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/page_details_model.dart';
import 'package:bilifast/video/page_session.dart';
import 'package:bilifast/video/page_tabs.dart';
import 'package:bilifast/video/player_prefs.dart';
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
import '../support/fake_video_actions.dart';

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

  /// Each page's details, in the order the pages made them.
  late List<FakePageDetails> detailsMade;
  late FakePageDetails Function() makeDetails;

  setUp(() {
    http = Canned.http()..routes[heartbeatPath] = (200, '{"code":0,"message":"0"}');
    player = FakePlayer();
    time = ManualClock(10000);
    nav = GlobalKey<NavigatorState>();
    orientation = SpyOrientation();
    sessions = [];
    sessionOpens = [];
    detailsMade = [];
    makeDetails = FakePageDetails.new;
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
        navigatorObservers: [pageRoutes],
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

  PageDetails fakeDetails({
    required PlayerSession session,
    required AppServices services,
    required void Function(String message) toast,
  }) {
    final details = makeDetails();
    detailsMade.add(details);
    return details;
  }

  late VideoPageOpener openPage;

  Widget page(VideoRoute route) =>
      VideoPage(route: route, createSession: fakeSession, createDetails: fakeDetails, openPage: openPage);

  /// openVideoPage's push, with the test's session and details.
  openPage = (context, route) => Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => page(route)));

  void pushVideo(VideoRoute route) =>
      unawaited(nav.currentState!.push(SwipeBackPageRoute<void>(builder: (_) => page(route))));

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
              onTap: () => Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => page(route))),
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
    testWidgets('inline: black under the status bar, the 16:9 player, the tab row right under it and the tabs below '
        '(screen 03 without its ad card)', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      expect(area(tester), const Rect.fromLTWH(0, 62, 440, 440 / BiliMetrics.videoAspect));
      expect(tester.getRect(find.byType(PageTabRow)), const Rect.fromLTWH(0, 62 + 247.5, 440, PageTheme.tabRowHeight));
      expect(
        tester.getRect(find.byType(PageTabs)),
        const Rect.fromLTRB(0, 62 + 247.5 + PageTheme.tabRowHeight, 440, 956),
      );
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
      expect(find.byType(PageTabRow), findsNothing, reason: 'offstage');
      expect(
        MediaQuery.paddingOf(tester.element(find.byType(LandscapeChrome))),
        const EdgeInsets.fromLTRB(62, 0, 62, 21),
        reason: 'the chrome keeps clear of the notch and the home indicator itself',
      );
      expect(tester.getRect(find.byKey(const ValueKey('fake-video'))), const Rect.fromLTWH(0, 0, 956, 440));

      await rotate(tester, Presentation.inline);
      expect(area(tester), const Rect.fromLTWH(0, 62, 440, 440 / BiliMetrics.videoAspect));
      expect(find.byType(PageTabRow), findsOneWidget);
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
      // The surface runs to 83% of the screen, so a fitted 16:9 picture centres at 41.5% as on 09.
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
      expect(
        [for (final child in stack.children.skip(stack.children.length - 2)) child.key],
        const [ValueKey('video-panels'), ValueKey('video-overlays')],
        reason: 'above the player and the tabs, with the action overlays over the panels',
      );
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

    testWidgets('with a panel open, the back arrow and a pop close it first; the next back leaves the page',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final panels = ui(tester).panels;
      bool canPop() => tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).last).canPop;

      panels.open(PlayerPanel.more);
      await tester.pump();
      ui(tester).onBack();
      await frames(tester, 2);
      expect(panels.value, isNull);
      expect(find.byType(VideoPage), findsOneWidget);

      panels.open(PlayerPanel.speed);
      await tester.pump();
      expect(canPop(), isFalse);
      unawaited(nav.currentState!.maybePop());
      await frames(tester, 2);
      expect(panels.value, isNull);
      expect(find.byType(VideoPage), findsOneWidget);
      expect(controller.video, isNotNull, reason: 'the page kept the player');
      expect(canPop(), isTrue);

      ui(tester).onBack();
      await frames(tester, 20);
      expect(find.byType(VideoPage), findsNothing);
    });

    testWidgets('in full screen with a panel open, back closes it first; the next back goes to the small player',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final panels = ui(tester).panels;
      for (final full in [Presentation.landscape, Presentation.vertical]) {
        await rotate(tester, full);
        panels.open(PlayerPanel.more);
        await tester.pump();
        ui(tester).onBack();
        await frames(tester, 2);
        expect(panels.value, isNull, reason: '$full');
        expect(orientation.presentation, full);

        panels.open(PlayerPanel.quality);
        await tester.pump();
        unawaited(nav.currentState!.maybePop());
        await frames(tester, 2);
        expect(panels.value, isNull, reason: '$full');
        expect(orientation.presentation, full);

        unawaited(nav.currentState!.maybePop());
        await frames(tester, 2);
        expect(orientation.presentation, Presentation.inline);
        expect(find.byType(VideoPage), findsOneWidget);
        screen(tester, portrait, portraitInsets);
      }
      await back(tester);
      expect(find.byType(VideoPage), findsNothing);
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

    testWidgets('the chrome stops hiding by itself while the next part loads, then hides again once it plays',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final chrome = ui(tester).chrome;
      player.emit(const StatusChanged(PlayerStatus.playing));
      expect(chrome.autoHide, isTrue);
      http.gates[Canned.playUrlPath] = Completer<void>();
      // As 自动连播 or 选集 opens the next part: the player still reports P1 playing until P2's load starts.
      sessionOpens.single(bv, cid: p2);
      await tester.pump();
      expect(controller.phase, PlaybackPhase.loading);
      expect(sessions.single.readout.wantsPlay, isTrue);
      expect(chrome.autoHide, isFalse);
      http.gates[Canned.playUrlPath]!.complete();
      await frames(tester, 20);
      expect(chrome.autoHide, isFalse);
      player.emit(const StatusChanged(PlayerStatus.playing));
      expect(chrome.autoHide, isTrue);
      await back(tester);
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
    testWidgets('its open plays another part on the same page, with its own watch reports', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0, title: '卡片标题'));
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.playing));
      position(10);
      sessionOpens.single(bv, cid: p2);
      await frames(tester, 20);
      expect(controller.page?.cid, p2);
      expect(find.byType(VideoPage), findsOneWidget);
      expect(sessions, hasLength(1));
      expect(detailsMade, hasLength(1), reason: 'one details per page, through its parts');
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

    testWidgets('简介 follows the session\'s video while the player is the page\'s, and keeps it under a newer page',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      IntroContent intro() => tester.widget<IntroTab>(find.byType(IntroTab, skipOffstage: false).first).content;
      expect(intro().detail, isNull);
      sessions.single
        ..detail = detail(bv, reply: 213)
        ..episodes = const [
          Episode(bvid: bv, cid: p1, title: 'P1 第一集', current: true),
          Episode(bvid: bv, cid: p2, title: 'P2 第二集', current: false),
        ]
        ..changed();
      await tester.pump();
      expect(intro().detail?.bvid, bv);
      expect(intro().episodes, hasLength(2));
      expect(find.bySemanticsLabel('评论 213'), findsOneWidget);

      pushVideo(const VideoRoute(bvid: 'BV1xx411c7mD', start: 0));
      await opened(tester, page: 1);
      sessions.first
        ..detail = detail('BV1xx411c7mD')
        ..changed();
      await tester.pump();
      expect(intro().detail?.bvid, bv, reason: 'the covered page\'s session hears the newer video; its 简介 does not');
      await back(tester);
      await back(tester);
    });

    testWidgets('is inactive while another page covers the page, and active again once shown with its own open',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final session = sessions.single;
      expect(session.active, isTrue);
      unawaited(nav.currentState!.push(SwipeBackPageRoute<void>(builder: (_) => const SizedBox())));
      await frames(tester, 20);
      expect(session.active, isFalse);
      await back(tester);
      expect(session.active, isTrue, reason: 'the player is still this page\'s open');
      await back(tester);
      expect(session.active, isFalse, reason: 'the page left');
    });

    testWidgets('is inactive under a newer video page, then opens its own video again where it was covered',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.playing));
      position(42);
      pushVideo(const VideoRoute(bvid: 'BV1xx411c7mD', start: 0));
      await opened(tester, page: 1);
      expect(sessions.first.active, isFalse);
      expect(detailsMade.first.activeSet, isFalse);
      expect(sessions.last.active, isTrue);
      final opens = controller.opens;

      await back(tester);
      expect(sessions.last.active, isFalse, reason: 'the page on top left');
      expect(controller.opens, opens + 1, reason: 'the first page opened its video again');
      expect(controller.video?.bvid, bv);
      expect(controller.page?.cid, p1);
      expect(player.loaded?.startSeconds, closeTo(42, 0.5));
      expect(sessions.first.active, isTrue);
      expect(detailsMade.first.activeSet, isTrue);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester);
      expect(find.byKey(const ValueKey('video-loading')), findsNothing, reason: 'it plays rather than spinning');
      expect(find.byType(PortraitControls), findsOneWidget);
      await back(tester);
      expect(controller.video, isNull);
    });

    testWidgets('the app\'s own session across a part change: P2 plays on the page after P1, then the end screen',
        (tester) async {
      final prefs = PlayerPrefs.shared;
      PlayerPrefs.shared = PlayerPrefs.memory();
      addTearDown(() => PlayerPrefs.shared = prefs);
      await host(tester);
      unawaited(
        nav.currentState!.push(
          SwipeBackPageRoute<void>(
            builder: (_) => VideoPage(route: const VideoRoute(bvid: bv, cid: p1, start: 0), createDetails: fakeDetails),
          ),
        ),
      );
      await frames(tester, 20);
      expect(ui(tester).session, isA<PagePlayerSession>());
      expect(controller.page?.cid, p1);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester);

      player.emit(const StatusChanged(PlayerStatus.ended));
      await frames(tester, 20);
      expect(controller.page?.cid, p2, reason: '自动连播 opened P2');
      expect(find.byType(VideoPage), findsOneWidget);
      expect(ui(tester).session.title, '第二集');
      expect(
        tester.widget<IntroTab>(find.byType(IntroTab)).content.episodes.where((e) => e.current).single.cid,
        p2,
        reason: '简介 follows the app\'s session',
      );
      expect(find.byType(EndScreenPortrait), findsNothing);
      final opens = controller.opens;
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester);

      player.emit(const StatusChanged(PlayerStatus.ended));
      await frames(tester, 20);
      expect(find.byType(EndScreenPortrait), findsOneWidget);
      expect(controller.opens, opens, reason: 'nothing plays after the last part');
      expect(controller.page?.cid, p2);
      expect(sent(), [(p1, '0'), (p1, '-1'), (p2, '0'), (p2, '-1')]);
      await back(tester);
      expect(controller.video, isNull);
    });

    testWidgets('a menu or dialog over the page leaves it active and owning the orientation; a page on top covers it',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final session = sessions.single
        ..detail = detail(bv)
        ..related = [card('BV1xx411c7mD')]
        ..changed();
      await tester.pump();
      final details = detailsMade.single;
      final opens = controller.opens;
      final log = [...orientation.log];
      void stillActive(String what) {
        expect(session.active, isTrue, reason: what);
        expect(details.activeSet, isNot(isFalse), reason: what);
        expect(controller.opens, opens, reason: '$what: nothing opened again');
        expect(orientation.log, log, reason: '$what: the orientation stays the page\'s');
      }

      await tester.ensureVisible(find.byKey(const ValueKey('related-more')));
      await tester.tap(find.byKey(const ValueKey('related-more')));
      await frames(tester);
      expect(find.byKey(const ValueKey('related-watch-later')), findsOneWidget);
      stillActive('the related ⋮ menu');
      nav.currentState!.pop();
      await frames(tester);
      stillActive('the menu closed');

      unawaited(showDialog<void>(context: nav.currentContext!, builder: (_) => const SizedBox()));
      await frames(tester);
      stillActive('a dialog');
      nav.currentState!.pop();
      await frames(tester);
      stillActive('the dialog closed');

      unawaited(nav.currentState!.push(SwipeBackPageRoute<void>(builder: (_) => const SizedBox())));
      await frames(tester, 20);
      expect(session.active, isFalse);
      expect(details.activeSet, isFalse);
      await back(tester);
      expect(session.active, isTrue);
      expect(details.activeSet, isTrue);
      expect(orientation.log, [...log, 'begin page1'], reason: 'shown again, it takes the orientation back');
      await back(tester);
    });

    testWidgets('a newer video page and back with the real details: the same actions, no second uploader, relation '
        'or tags ask, and one fresh N人正在看', (tester) async {
      final prefs = PlayerPrefs.shared;
      PlayerPrefs.shared = PlayerPrefs.memory();
      addTearDown(() => PlayerPrefs.shared = prefs);
      final api = FakePageApi(
        uploader: const UploaderCard(
          mid: 1,
          name: 'UP主',
          face: '',
          fans: 10,
          videos: 2,
          isVip: false,
          following: false,
          official: OfficialKind.none,
        ),
      );
      VideoPageDetailsModel? model;
      await host(tester);
      unawaited(
        nav.currentState!.push(
          SwipeBackPageRoute<void>(
            builder: (_) => VideoPage(
              route: const VideoRoute(bvid: bv, cid: p1, start: 0),
              createDetails: ({required session, required services, required toast}) => model = VideoPageDetailsModel(
                session: session,
                api: api,
                isLoggedIn: () => true,
                accountMid: () => 12345,
                requestLogin: () {},
                toast: toast,
                periodic: FakeTimers().start,
              ),
              openPage: openPage,
            ),
          ),
        ),
      );
      await frames(tester, 20);
      player.emit(const StatusChanged(PlayerStatus.playing));
      position(42);
      await frames(tester);
      final actions = model!.actions;
      expect(actions, isNotNull);
      expect(api.calls, ['uploaderCard mid=1', 'relation', 'tags cid=$p1', 'onlineCount cid=$p1']);

      const other = 'BV1xx411c7mD';
      http.routes[Canned.signedViewPath] = (
        200,
        Canned.view
            .replaceAll(bv, other)
            .replaceAll('80433022', '80433023')
            .replaceAll('$p1', '237649199')
            .replaceAll('$p2', '237649200'),
      );
      pushVideo(const VideoRoute(bvid: other, start: 0));
      await frames(tester, 20);
      expect(controller.video?.bvid, other);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester);
      expect(api.calls, hasLength(4), reason: 'the covered page asks nothing for the newer video');

      http.routes[Canned.signedViewPath] = (200, Canned.view);
      await back(tester);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 20);
      expect(controller.video?.bvid, bv);
      expect(controller.page?.cid, p1);
      expect(model!.actions, same(actions));
      expect(api.calls.skip(4), ['onlineCount cid=$p1']);
      await back(tester);
      expect(controller.video, isNull);
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

  group('the page body', () {
    IntroTab intro(WidgetTester tester) => tester.widget<IntroTab>(find.byType(IntroTab));
    ActionOverlayController overlays(WidgetTester tester) =>
        tester.widget<ActionOverlays>(find.byType(ActionOverlays).last).controller;
    PageController pager(WidgetTester tester) =>
        tester.widget<PageView>(find.byKey(const ValueKey('page-tabs')).last).controller!;

    testWidgets('the details are made once with the session, handed to the player, follow its active, and go with '
        'the page', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final details = detailsMade.single;
      expect(ui(tester).details, same(details));
      expect(intro(tester).details, same(details));
      expect(ui(tester).onComments, isNotNull);
      unawaited(nav.currentState!.push(SwipeBackPageRoute<void>(builder: (_) => const SizedBox())));
      await frames(tester, 20);
      expect(details.activeSet, isFalse);
      await back(tester);
      expect(details.activeSet, isTrue);
      await back(tester);
      expect(details.activeSet, isFalse);
      expect(() => details.addListener(() {}), throwsFlutterError, reason: 'disposed with the page');
      expect(detailsMade, hasLength(1));
    });

    testWidgets('the row: 评论 shows the reply count, the 弹 toggle switches danmaku, 点我发弹幕 says it comes next',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final session = sessions.single
        ..detail = detail(bv, reply: 12345)
        ..changed();
      await tester.pump();
      expect(find.bySemanticsLabel('评论 1.2万'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('danmaku-toggle')));
      await tester.pump();
      expect(session.calls, contains('setDanmakuOn false'));
      expect(find.byKey(const ValueKey('danmaku-send')), findsOneWidget);
      session
        ..danmakuOn = true
        ..changed();
      await frames(tester, 8);
      await tester.tap(find.byKey(const ValueKey('danmaku-send')));
      await tester.pump();
      expect(find.text('发弹幕将在下个版本推出'), findsOneWidget);
      await frames(tester, 70);
      await back(tester);
    });

    testWidgets('back closes an open overlay first, then a panel, then full screen, then leaves', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final panels = ui(tester).panels;
      bool canPop() => tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).last).canPop;

      overlays(tester).value = ActionPrompt.coin;
      await tester.pump();
      expect(canPop(), isFalse);
      unawaited(nav.currentState!.maybePop());
      await frames(tester, 2);
      expect(overlays(tester).value, isNull);
      expect(find.byType(VideoPage), findsOneWidget);

      await rotate(tester, Presentation.landscape);
      panels.open(PlayerPanel.more);
      overlays(tester).value = ActionPrompt.favourites;
      await tester.pump();
      expect(
        tester.widget<ActionOverlays>(find.byType(ActionOverlays)).landscape,
        isTrue,
        reason: 'the overlays lay out for landscape',
      );
      ui(tester).onBack();
      await frames(tester, 2);
      expect(overlays(tester).value, isNull);
      expect(panels.value, PlayerPanel.more, reason: 'the overlay went first');
      ui(tester).onBack();
      await frames(tester, 2);
      expect(panels.value, isNull);
      expect(orientation.presentation, Presentation.landscape);
      ui(tester).onBack();
      await frames(tester, 2);
      expect(orientation.presentation, Presentation.inline);
      screen(tester, portrait, portraitInsets);
      expect(canPop(), isTrue);
      ui(tester).onBack();
      await frames(tester, 20);
      expect(find.byType(VideoPage), findsNothing);
    });

    testWidgets('评论 in full screen goes back to the small player on the 评论 tab', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      await rotate(tester, Presentation.landscape);
      ui(tester).onComments!();
      screen(tester, portrait, portraitInsets);
      await frames(tester, 4);
      expect(orientation.presentation, Presentation.inline);
      expect(pager(tester).page, 1);
      expect(find.byWidgetPredicate((widget) => widget is CommentsTab || widget is CommentsSlot), findsOneWidget);
      await back(tester);
    });

    testWidgets('简介\'s parts, 选集, timestamps, video ids and 稍后再看 reach the session, the panel and the details',
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final session = sessions.single;
      intro(tester).onPlayEpisode(const Episode(bvid: bv, cid: p2, title: 'P2 第二集', current: false));
      expect(session.calls, contains('playEpisode $bv $p2'));
      intro(tester).onOpenEpisodes();
      expect(ui(tester).panels.value, PlayerPanel.episodes);
      ui(tester).panels.close();
      sessions.single.duration.value = 200;
      intro(tester).onSeek(83);
      expect(session.calls, contains('commitSeek 83.0'));

      intro(tester).onWatchLater(card('BV1xx411c7mD'));
      await tester.pump();
      expect(detailsMade.single.watchLaterCalls, ['BV1xx411c7mD']);
      expect(find.text('已添加至稍后再看'), findsOneWidget);
      await frames(tester, 70);

      intro(tester).onOpenVideo('BV1xx411c7mD');
      await frames(tester, 20);
      expect(find.byType(VideoPage, skipOffstage: false), findsNWidgets(2));
      expect(tester.widget<VideoPage>(find.byType(VideoPage)).route.bvid, 'BV1xx411c7mD');
      await back(tester);
      await back(tester);
    });

    testWidgets('in full screen an action overlay puts the chrome and the end screen away as a panel does, and gives '
        'them back as they were; inline the small controls stay', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final chrome = ui(tester).chrome;
      player.emit(const StatusChanged(PlayerStatus.playing));
      expect(chrome.autoHide, isTrue);
      overlays(tester).value = ActionPrompt.coin;
      await tester.pump();
      expect(chrome.autoHide, isFalse, reason: 'no hide timer while it is up');
      expect(chrome.visible, isTrue);
      overlays(tester).close();
      await tester.pump();
      expect(chrome.autoHide, isTrue);

      await rotate(tester, Presentation.landscape);
      chrome.show();
      await tester.pump();
      bool shown() => !tester.widget<IgnorePointer>(find.byKey(const ValueKey('landscape-chrome'))).ignoring;
      expect(shown(), isTrue);
      overlays(tester).value = ActionPrompt.favourites;
      await tester.pump();
      expect(shown(), isFalse);
      expect(chrome.autoHide, isFalse);
      await tester.pump(const Duration(seconds: 5));
      overlays(tester).close();
      await tester.pump();
      expect(shown(), isTrue, reason: 'back as it was');
      expect(chrome.autoHide, isTrue);
      await tester.pump(chrome.hideDelay + const Duration(milliseconds: 50));
      expect(shown(), isFalse, reason: 'the hide timer runs again');
      overlays(tester).value = ActionPrompt.coin;
      await tester.pump();
      overlays(tester).close();
      await tester.pump();
      expect(shown(), isFalse, reason: 'hidden when the overlay went up, it stays hidden');

      sessions.single
        ..ended = true
        ..changed();
      await tester.pump();
      bool endShown() => !tester.widget<IgnorePointer>(find.byKey(const ValueKey('video-end'))).ignoring;
      expect(find.byType(EndScreenLandscape), findsOneWidget);
      expect(endShown(), isTrue);
      overlays(tester).value = ActionPrompt.favourites;
      await tester.pump();
      expect(endShown(), isFalse);
      overlays(tester).close();
      await tester.pump();
      expect(endShown(), isTrue);
      await rotate(tester, Presentation.inline);
      await back(tester);
    });

    testWidgets('the danmaku keep below the status bar in 竖屏, as inline and in landscape', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester, vertical: true);
      double top() => tester.getRect(find.byType(DanmakuLayer)).top;
      expect(top(), 62, reason: 'inline: under the status bar band, at the top of the player');
      await rotate(tester, Presentation.vertical);
      expect(tester.getRect(find.byKey(const ValueKey('fake-video'))).top, 0, reason: 'the video runs under it');
      expect(top(), 62);
      sessions.single
        ..isVertical = false
        ..changed();
      await tester.pump();
      expect(top(), 62, reason: 'a landscape video in 竖屏 too');
      await rotate(tester, Presentation.landscape);
      expect(top(), 0);
      await rotate(tester, Presentation.inline);
      await back(tester);
    });

    testWidgets('a description timestamp seeks and plays a paused video; a playing one just seeks', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final session = sessions.single;
      player.emit(const StatusChanged(PlayerStatus.paused));
      player.calls.clear();
      sessions.single.duration.value = 200;
      intro(tester).onSeek(83);
      await tester.pump();
      expect(session.calls, contains('commitSeek 83.0'));
      expect(player.calls, ['play']);
      expect(session.calls, isNot(contains('togglePlay')));

      player.emit(const StatusChanged(PlayerStatus.playing));
      player.calls.clear();
      intro(tester).onSeek(90);
      await tester.pump();
      expect(session.calls, contains('commitSeek 90.0'));
      expect(player.calls, isEmpty);
      await back(tester);
    });

    testWidgets('a timestamp tapped before the duration is known neither seeks nor plays', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.paused));
      player.calls.clear();
      intro(tester).onSeek(83);
      await tester.pump();
      expect(sessions.single.calls, isNot(contains('commitSeek 83.0')));
      expect(player.calls, isEmpty);
      await back(tester);
    });

    testWidgets('the video\'s own id in its description opens nothing', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      sessions.single
        ..detail = detail(bv)
        ..changed();
      await tester.pump();
      final views = http.to(Canned.viewPath).length;
      intro(tester).onOpenVideo(bv);
      intro(tester).onOpenVideo('av1');
      await frames(tester, 20);
      expect(find.byType(VideoPage, skipOffstage: false), findsOneWidget);
      expect(http.to(Canned.viewPath), hasLength(views), reason: 'its own av id is not looked up');
      await back(tester);
    });

    testWidgets('an av id is looked up once however often it is tapped, and a failed lookup is logged and toasted',
        (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      final views = http.to(Canned.viewPath).length;
      final lookup = http.gates[Canned.viewPath] = Completer<void>();
      http.errors[Canned.viewPath] = const SocketException('lost');
      intro(tester).onOpenVideo('av170001');
      await tester.pump();
      intro(tester).onOpenVideo('av170001');
      await tester.pump();
      expect(http.to(Canned.viewPath), hasLength(views + 1));
      lookup.complete();
      await frames(tester, 2);
      expect(find.byType(VideoPage, skipOffstage: false), findsOneWidget);
      expect(
        logs.events.where((event) => event.msg == 'open video id failed').map((event) => event.cat),
        [LogCategory.ui],
      );
      expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
      await frames(tester, 70);

      http.gates.remove(Canned.viewPath);
      intro(tester).onOpenVideo('av170001');
      await frames(tester, 2);
      expect(http.to(Canned.viewPath), hasLength(views + 2), reason: 'a tap after the failure asks again');
      await frames(tester, 70);
      await back(tester);
    });

    testWidgets('稍后再看 with nothing to say shows no toast', (tester) async {
      makeDetails = _QuietDetails.new;
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      intro(tester).onWatchLater(card('BV1xx411c7mD'));
      await tester.pump();
      expect(detailsMade.single.watchLaterCalls, ['BV1xx411c7mD']);
      expect(find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_Toast'), findsNothing);
      await back(tester);
    });

    testWidgets('the cover\'s Hero stands down once the video played or while 简介 lists the same video, so no two '
        'Heroes share a tag', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0, cover: cover));
      await opened(tester);
      Element hero() =>
          tester.element(find.descendant(of: find.byKey(const ValueKey('video-cover')), matching: find.byType(Hero)));
      final first = hero();
      bool flies() => tester
          .widget<HeroMode>(
            find.descendant(of: find.byKey(const ValueKey('video-cover')), matching: find.byType(HeroMode)),
          )
          .enabled;
      expect(flies(), isTrue);
      sessions.single
        ..detail = detail(bv)
        ..related = [card(bv)]
        ..changed();
      await tester.pump();
      expect(flies(), isFalse, reason: 'a related row has the same tag');
      sessions.single
        ..related = [card('BV1xx411c7mD')]
        ..changed();
      await tester.pump();
      expect(flies(), isTrue);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester);
      expect(flies(), isFalse, reason: 'played');
      expect(identical(hero(), first), isTrue, reason: 'the cover keeps its element');

      // As after 自动连播 to a video whose related videos hold this one: the next push gathers the page's Heroes.
      sessions.single
        ..related = [card(bv)]
        ..changed();
      await tester.pump();
      pushVideo(const VideoRoute(bvid: 'BV1xx411c7mD', start: 0, cover: cover));
      await frames(tester, 20);
      expect(tester.takeException(), isNull);
      await back(tester);
      expect(tester.takeException(), isNull);
      await back(tester);
    });

    testWidgets("leaving, the body's Heroes stand down so a related cover never flies back to a feed card",
        (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      sessions.single
        ..detail = detail(bv)
        ..related = [card('BV1xx411c7mD')]
        ..changed();
      await tester.pump();
      bool bodyFlies() => tester
          .widget<HeroMode>(find.ancestor(of: find.byType(PageTabs), matching: find.byType(HeroMode)).first)
          .enabled;
      expect(bodyFlies(), isTrue);
      unawaited(nav.currentState!.maybePop());
      await tester.pump();
      expect(bodyFlies(), isFalse);
      await frames(tester, 20);
    });

    testWidgets('a related video opens a page on top, and back returns to the first video playing', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p2, start: 0));
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.playing));
      position(30);
      intro(tester).onOpenRelated(card('BV1xx411c7mD'));
      await frames(tester, 20);
      expect(find.byType(VideoPage, skipOffstage: false), findsNWidgets(2));
      expect(sessions, hasLength(2));
      final opens = controller.opens;
      final top = tester.widget<VideoPage>(find.byType(VideoPage).last).route;
      expect((top.bvid, top.title, top.cover), ('BV1xx411c7mD', '相关视频', cover));

      await back(tester);
      expect(find.byType(VideoPage), findsOneWidget);
      expect(controller.opens, opens + 1, reason: 'the first page opened its video again');
      expect(sessions.first.active, isTrue);
      expect(controller.page?.cid, p2, reason: 'the part it was on');
      expect(player.loaded?.startSeconds, closeTo(30, 0.5));
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester);
      expect(controller.phase, PlaybackPhase.playing);
      expect(find.byKey(const ValueKey('fake-video')), findsOneWidget);
      await back(tester);
      expect(controller.video, isNull);
    });

    testWidgets('a sideways swipe over the tabs switches them; only the left edge goes back', (tester) async {
      await host(tester);
      pushVideo(const VideoRoute(bvid: bv, cid: p1, start: 0));
      await opened(tester);
      await tester.timedDragFrom(const Offset(300, 700), const Offset(-250, 0), const Duration(milliseconds: 200));
      await frames(tester, 20);
      expect(find.byType(VideoPage), findsOneWidget);
      expect(pager(tester).page, 1);
      await tester.timedDragFrom(const Offset(100, 700), const Offset(250, 0), const Duration(milliseconds: 200));
      await frames(tester, 20);
      expect(find.byType(VideoPage), findsOneWidget);
      expect(pager(tester).page, 0);
      await tester.timedDragFrom(const Offset(5, 700), const Offset(300, 0), const Duration(milliseconds: 200));
      await frames(tester, 20);
      expect(find.byType(VideoPage), findsNothing, reason: 'the edge swipe went back, not to the other tab');
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}

VideoDetail detail(String bvid, {int reply = 0}) => VideoDetail(
  bvid: bvid,
  aid: 1,
  title: '测试视频',
  cover: '',
  pubdate: 0,
  duration: 712,
  desc: '',
  descParts: const [],
  copyright: 1,
  owner: VideoOwner.empty,
  stat: VideoStat(view: 0, danmaku: 0, reply: reply, favorite: 0, coin: 0, share: 0, like: 0),
  pages: const [],
  season: null,
  staff: const [],
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
);

VideoCard card(String bvid) => VideoCard(
  aid: 2,
  bvid: bvid,
  cid: 3,
  title: '相关视频',
  cover: cover,
  duration: 60,
  ownerMid: 4,
  ownerName: 'UP',
  views: 1,
  danmaku: 1,
  likes: 1,
);

/// As the logged-out 稍后再看: the model asked for a login itself, so there is nothing to toast.
final class _QuietDetails extends FakePageDetails {
  @override
  Future<ActionResult> watchLater(VideoCard card) async {
    watchLaterCalls.add(card.bvid);
    return const ActionResult('', ok: false);
  }
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
