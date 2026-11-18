import 'dart:async';

import 'package:bili_core/api.dart' show BiliError, Comment, CommentMember, TextRun, VideoDetail, VideoOwner, VideoStat;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/comments/comment_overlays.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/comments/thread_view.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/page_session.dart';
import 'package:bilifast/video/page_tabs.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';
import '../support/look_alike.dart';

const bv = 'BV1GJ411x7h7';
const p1 = 137649199;

/// KaiC's iPad Pro 11" upright and sideways, in points.
const tall = Size(834, 1194);
const wide = Size(1194, 834);

/// A reply notification's page: 评论 under it, and the thread of comment 100 (20 replies, 201 the oldest) up over it.
void main() {
  late PlaybackController controller;
  late GlobalKey<NavigatorState> nav;
  late List<FakePlayerSession> sessions;
  late FakePageApi api;
  late CannedHttp http;
  late OrientationController orientation;
  late PlayerPrefs prefs;

  setUp(() {
    sessions = [];
    final savedPrefs = PlayerPrefs.shared;
    PlayerPrefs.shared = prefs = PlayerPrefs.memory();
    addTearDown(() => PlayerPrefs.shared = savedPrefs);
    final replies = [for (var n = 1; n <= 20; n++) comment(200 + n, root: 100, parent: 100)];
    api = FakePageApi()
      ..commentList = [
        comment(100, replyCount: 20, preview: replies.take(3).toList()),
        for (var i = 1; i <= 25; i++) comment(300 + i),
      ]
      ..threadReplies = {100: replies};
  });

  PlayerSession fakeSession({
    required PlaybackController controller,
    required AppServices services,
    required SessionOpen open,
    required void Function(double seconds) onSeeked,
    required VoidCallback requestLogin,
    required VoidCallback willPlay,
  }) {
    final session = FakePlayerSession(player: controller.player as FakePlayer);
    sessions.add(session);
    return session;
  }

  PageDetails fakeDetails({
    required PlayerSession session,
    required AppServices services,
    required void Function(String message) toast,
    required VoidCallback requestLogin,
    required Listenable logins,
  }) => FakePageDetails();

  /// KaiC's iPhone, or his iPad held [padSize].
  Future<void> host(WidgetTester tester, {Size? padSize}) async {
    if (padSize == null) {
      tester.view
        ..physicalSize = const Size(440, 956)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: 62, bottom: 34)
        ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.reset);
    } else {
      showAsPad(tester, landscape: padSize == wide);
    }
    final logger = Logger(session: 'test');
    http = Canned.http()..routes['/x/click-interface/web/heartbeat'] = (200, '{"code":0,"message":"0"}');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final time = ManualClock(10000);
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    PlaybackController make() => controller = PlaybackController(
      client: environment.client,
      engine: FakeEngine(),
      player: FakePlayer(),
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );

    make();
    final playback = AppPlayback(() async => make());
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(orientation: orientation = OrientationController(), controls: NoDeviceControls()),
      pageApi: api,
    );
    nav = services.navigator;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
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

  /// The page pushed with [comment], its video and detail in.
  Future<void> open(WidgetTester tester, {CommentFocus? comment}) async {
    final route = VideoRoute(bvid: bv, cid: p1, start: 0, comment: comment);
    unawaited(
      nav.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => VideoPage(route: route, createSession: fakeSession, createDetails: fakeDetails),
        ),
      ),
    );
    await frames(tester, 20);
    sessions.last
      ..video = controller.video
      ..detail = detail(bv, aid: controller.video!.aid)
      ..changed();
    await frames(tester, 20);
  }

  Future<void> back(WidgetTester tester) async {
    unawaited(nav.currentState!.maybePop());
    await frames(tester, 20);
  }

  /// The video's shape in, which 详情页直接全屏播放 waits for.
  Future<void> shaped(WidgetTester tester) async {
    sessions.last
      ..videoShape = (width: 1920, height: 1080)
      ..changed();
    await frames(tester);
  }

  /// The page pushed with [comment] for a video Bilibili answers -404 for: the view fails, so no aid comes.
  Future<void> openGone(WidgetTester tester, {CommentFocus? comment}) async {
    const gone = '{"code":-404,"message":"啥都木有","ttl":1}';
    http.routes
      ..[Canned.viewPath] = (200, gone)
      ..[Canned.signedViewPath] = (200, gone);
    final route = VideoRoute(bvid: bv, cid: p1, start: 0, comment: comment);
    unawaited(
      nav.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => VideoPage(route: route, createSession: fakeSession, createDetails: fakeDetails),
        ),
      ),
    );
    await frames(tester, 20);
    expect(controller.phase, PlaybackPhase.failed);
  }

  Finder inSlot(Finder finder) => find.descendant(of: find.byType(CommentsSlot), matching: finder);
  List<String> commentCalls() => [
    for (final call in api.calls)
      if (call.startsWith('comments ') || call.startsWith('thread ')) call,
  ];

  double tab(WidgetTester tester) =>
      tester.widget<PageView>(find.byKey(const ValueKey('page-tabs')).last).controller!.page!;
  Finder inThread(Finder finder) => find.descendant(of: find.byType(ThreadView), matching: finder);
  Rect threadViewport(WidgetTester tester) => tester.getRect(inThread(find.byType(Scrollable)).first);
  double threadScrolled(WidgetTester tester) =>
      tester.state<ScrollableState>(inThread(find.byType(Scrollable)).first).position.pixels;
  List<String> threadCalls() => [
    for (final call in api.calls)
      if (call.startsWith('thread ')) call,
  ];

  group('on the iPhone', () {
    testWidgets('opens on 评论 with 评论详情 up for the root: the root on top, its replies by time', (tester) async {
      await host(tester);
      await open(tester, comment: const CommentFocus(root: 100));
      expect(tab(tester), 1, reason: '评论, not 简介');
      expect(find.byType(CommentsTab), findsOneWidget, reason: 'the list loads under the thread');
      expect(threadCalls(), ['thread root=100 page=1 sort=time']);
      expect(find.byType(ThreadView), findsOneWidget);
      expect(
        find.descendant(of: inThread(find.byKey(const ValueKey('thread-root'))), matching: find.text('第100条评论')),
        findsOneWidget,
      );
      expect(inThread(find.byKey(const ValueKey(201))), findsOneWidget);
      expect(find.text('相关回复共20条'), findsOneWidget);
      expect(threadScrolled(tester), 0, reason: 'no reply to bring into view');
      expect(sessions, hasLength(1), reason: 'the player opens as any page\'s does');
      await back(tester);
      await back(tester);
    });

    testWidgets('a reply out of sight is scrolled into view; one in sight leaves the thread at its top', (
      tester,
    ) async {
      await host(tester);
      await open(tester, comment: const CommentFocus(root: 100, reply: 216));
      final viewport = threadViewport(tester);
      final row = tester.getRect(inThread(find.byKey(const ValueKey(216))));
      expect(threadScrolled(tester), greaterThan(0));
      expect(row.top, greaterThanOrEqualTo(viewport.top - 0.5));
      expect(row.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
      expect(row.top, closeTo(viewport.top, 0.5), reason: 'at the top, the replies after it below');
      await back(tester);
      await back(tester);

      await open(tester, comment: const CommentFocus(root: 100, reply: 201));
      expect(threadScrolled(tester), 0);
      expect(inThread(find.byKey(const ValueKey(201))), findsOneWidget);
      await back(tester);
      await back(tester);
    });

    testWidgets('a root deleted stays on 评论 with Bilibili\'s words; no empty thread goes up', (tester) async {
      await host(tester);
      api.failures['thread'] = const BiliError.api(code: 12022, message: '已经被删除了');
      await open(tester, comment: const CommentFocus(root: 100, reply: 216));
      expect(tab(tester), 1);
      expect(find.byType(ThreadView), findsNothing);
      expect(find.byKey(const ValueKey('comment-thread')), findsNothing);
      expect(find.text('已经被删除了'), findsOneWidget);
      expect(find.byKey(const ValueKey(100)), findsOneWidget, reason: 'the list is there');
      await back(tester);
      expect(find.byType(VideoPage), findsNothing, reason: 'nothing open, back leaves');
    });

    testWidgets('a failed call says the network\'s wording and stays on 评论', (tester) async {
      await host(tester);
      api.failures['thread'] = const BiliError.network('SocketException');
      await open(tester, comment: const CommentFocus(root: 100));
      expect(tab(tester), 1);
      expect(find.byType(ThreadView), findsNothing);
      expect(find.text('网络连接失败，请稍后再试'), findsOneWidget);
      await back(tester);
    });

    testWidgets('back closes the thread first, leaving 评论; the next back leaves the page', (tester) async {
      await host(tester);
      await open(tester, comment: const CommentFocus(root: 100, reply: 216));
      await back(tester);
      expect(find.byType(ThreadView), findsNothing);
      expect(find.byType(VideoPage), findsOneWidget);
      expect(tab(tester), 1);
      await back(tester);
      expect(find.byType(VideoPage), findsNothing);
    });

    testWidgets('without one, the page opens on 简介 and asks for no thread', (tester) async {
      await host(tester);
      await open(tester);
      expect(tab(tester), 0);
      expect(find.byType(ThreadView), findsNothing);
      expect(threadCalls(), isEmpty);
      await back(tester);
    });

    testWidgets('详情页直接全屏播放 on: the page stays on the small player with the thread up', (tester) async {
      prefs.detailFullScreen = true;
      await host(tester);
      await open(tester);
      await shaped(tester);
      expect(orientation.presentation, Presentation.landscape, reason: 'a page opened without one goes full screen');
      orientation.exitToInline();
      await frames(tester, 4);
      await back(tester);

      await open(tester, comment: const CommentFocus(root: 100, reply: 216));
      await shaped(tester);
      expect(orientation.presentation, Presentation.inline);
      expect(find.byType(ThreadView), findsOneWidget);
      expect(inThread(find.byKey(const ValueKey(216))), findsOneWidget);
      await back(tester);
      await back(tester);
    });

    testWidgets('a video that fails to load: 评论 shows the list\'s failure, not the loading TV; 点击重试 retries it', (
      tester,
    ) async {
      await host(tester);
      await openGone(tester);
      await tester.tap(find.byKey(const ValueKey('tab-comments')));
      await frames(tester, 20);
      expect(find.byKey(const ValueKey('comments-slot-loading')), findsNothing);
      expect(inSlot(find.byKey(const ValueKey('comments-retry'))), findsOneWidget);
      expect(inSlot(find.text('视频不存在或已被删除')), findsOneWidget);
      expect(commentCalls(), isEmpty);

      http.routes
        ..[Canned.viewPath] = (200, Canned.view)
        ..[Canned.signedViewPath] = (200, Canned.view);
      await tester.tap(find.byKey(const ValueKey('comments-retry')));
      await frames(tester, 20);
      expect(find.byType(CommentsSlot), findsNothing);
      expect(find.byKey(const ValueKey(100)), findsOneWidget, reason: 'the video in, its list loads');
      await back(tester);
    });

    testWidgets('a video that fails to load with a thread to open: 评论 shows the failure, no thread, no call', (
      tester,
    ) async {
      await host(tester);
      await openGone(tester, comment: const CommentFocus(root: 100, reply: 216));
      expect(tab(tester), 1);
      expect(inSlot(find.byKey(const ValueKey('comments-retry'))), findsOneWidget);
      expect(find.byKey(const ValueKey('comments-slot-loading')), findsNothing);
      expect(find.byType(ThreadView), findsNothing);
      expect(commentCalls(), isEmpty);
      await back(tester);
      expect(find.byType(VideoPage), findsNothing, reason: 'nothing open, back leaves');
    });

    testWidgets('another video opened on the page later opens no thread of its own', (tester) async {
      await host(tester);
      await open(tester, comment: const CommentFocus(root: 100));
      await back(tester);
      sessions.single
        ..detail = detail('BV1xx411c7mD', aid: 2)
        ..changed();
      await frames(tester, 20);
      expect(find.byType(ThreadView), findsNothing);
      expect(threadCalls(), hasLength(1));
      await back(tester);
    });
  });

  group('on the iPad', () {
    testWidgets('upright: 评论 with the thread up, as on the iPhone; back closes it, then leaves', (tester) async {
      await host(tester, padSize: tall);
      await open(tester, comment: const CommentFocus(root: 100, reply: 216));
      expect(find.byType(PadPageTabRow), findsOneWidget);
      expect(tab(tester), 1);
      expect(find.byType(ThreadView), findsOneWidget);
      expect(inThread(find.byKey(const ValueKey(216))), findsOneWidget);
      await back(tester);
      expect(find.byType(ThreadView), findsNothing);
      expect(find.byType(VideoPage), findsOneWidget);
      await back(tester);
      expect(find.byType(VideoPage), findsNothing);
    });

    testWidgets('详情页直接全屏播放 on: the page stays as it is with the thread up', (tester) async {
      prefs.detailFullScreen = true;
      await host(tester, padSize: tall);
      await open(tester);
      await shaped(tester);
      expect(orientation.presentation, Presentation.landscape, reason: 'a page opened without one goes full screen');
      orientation.exitToInline();
      await frames(tester, 4);
      await back(tester);

      await open(tester, comment: const CommentFocus(root: 100, reply: 216));
      await shaped(tester);
      expect(orientation.presentation, Presentation.inline);
      expect(find.byType(ThreadView), findsOneWidget);
      await back(tester);
      await back(tester);
    });

    testWidgets('upright, a video that fails to load: 评论 shows the failure, with a thread to open or without', (
      tester,
    ) async {
      await host(tester, padSize: tall);
      await openGone(tester, comment: const CommentFocus(root: 100));
      expect(tab(tester), 1);
      expect(inSlot(find.byKey(const ValueKey('comments-retry'))), findsOneWidget);
      expect(find.byType(ThreadView), findsNothing);
      await back(tester);

      await openGone(tester);
      await tester.tap(find.byKey(const ValueKey('tab-comments')).last);
      await frames(tester, 20);
      expect(inSlot(find.byKey(const ValueKey('comments-retry'))), findsOneWidget);
      expect(find.byKey(const ValueKey('comments-slot-loading')), findsNothing);
      expect(commentCalls(), isEmpty);
      await back(tester);
    });

    testWidgets('sideways: no tabs, the thread up over the left column', (tester) async {
      await host(tester, padSize: wide);
      await open(tester, comment: const CommentFocus(root: 100));
      expect(find.byType(PadPageTabRow), findsNothing);
      expect(find.byType(ThreadView), findsOneWidget);
      const column = 1194 - PadPageTheme.relatedWidth - PadPageTheme.rule;
      expect(tester.getRect(find.byType(CommentOverlays)).width, column);
      expect(tester.getRect(find.byType(ThreadView)).width, column);
      await back(tester);
      expect(find.byType(ThreadView), findsNothing);
      expect(find.byType(PadCommentsHeader), findsOneWidget, reason: '热门评论 in the column under it');
      await back(tester);
      expect(find.byType(VideoPage), findsNothing);
    });
  });
}

VideoDetail detail(String bvid, {int aid = 1}) => VideoDetail(
  bvid: bvid,
  aid: aid,
  title: '测试视频',
  cover: '',
  pubdate: 0,
  duration: 712,
  desc: '',
  descParts: const [],
  copyright: 1,
  owner: VideoOwner.empty,
  stat: const VideoStat(view: 0, danmaku: 0, reply: 0, favorite: 0, coin: 0, share: 0, like: 0),
  pages: const [],
  season: null,
  staff: const [],
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
);

Comment comment(int rpid, {int root = 0, int parent = 0, int replyCount = 0, List<Comment> preview = const []}) =>
    Comment(
      rpid: rpid,
      oid: 1,
      mid: 2001,
      root: root,
      parent: parent,
      ctime: rpid,
      likes: 10,
      replyCount: replyCount,
      member: const CommentMember(mid: 2001, name: '用户', level: 5),
      message: '第$rpid条评论',
      runs: [TextRun('第$rpid条评论')],
      previewReplies: preview,
    );
