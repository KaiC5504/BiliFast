import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart'
    show Comment, CommentMember, CommentPicture, PlaySource, TextRun, VideoCard, VideoDetail, VideoOwner, VideoStat;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/comments/comment_overlays.dart';
import 'package:bilifast/comments/composer.dart';
import 'package:bilifast/comments/picture_viewer.dart';
import 'package:bilifast/comments/thread_view.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/vertical_chrome.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/space_api.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/space/space_route.dart';
import 'package:bilifast/space/uploader_tap.dart' show UploaderRef;
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/page_playback.dart';
import 'package:bilifast/video/page_session.dart';
import 'package:bilifast/video/page_tabs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:bilifast/video/story/story_feed.dart';
import 'package:bilifast/video/story/story_intro.dart';
import 'package:bilifast/video/story/story_sheet.dart';
import 'package:bilifast/video/story/story_sheet_view.dart';
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
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import 'mixed_lines.dart' show appTheme;
import 'story/fake_story_feed.dart';

const _bv = 'BV1GJ411x7h7';
const _p1 = 137649199;
const _portrait = Size(440, 956);
const _landscape = Size(956, 440);
const _portraitInsets = FakeViewPadding(top: 62, bottom: 34);
const _landscapeInsets = FakeViewPadding(left: 62, right: 62, bottom: 21);

/// 264's upright video: its frame measured on the reference, 422 × 785 px with the sheet up.
const _upright264 = (width: 1080, height: 2009);
const _wide269 = (width: 1920, height: 1080);

/// 竖屏's 简介/评论 sheet on the video page (264-271): opening and closing, the picture in the room above it, the
/// controls standing aside, back, and the pages its 相关视频 pushes.
void main() {
  late ManualClock time;
  late AppEnvironment environment;
  late PlaybackController controller;
  late FakePlayer player;
  late AppPlayback playback;
  late AppServices services;
  late GlobalKey<NavigatorState> nav;
  late OrientationController orientation;
  late List<FakePlayerSession> sessions;
  late List<FeedRecord> feeds;
  late List<VideoRoute> pushed;
  late FakePageApi api;

  setUp(() {
    time = ManualClock(10000);
    orientation = OrientationController();
    sessions = [];
    feeds = [];
    pushed = [];
    final reply = _comment(201, root: 100, parent: 100);
    api = FakePageApi()
      ..commentList = [
        _comment(100, replyCount: 1, preview: [reply]),
        for (var i = 1; i <= 12; i++) _comment(300 + i),
      ]
      ..threadReplies = {
        100: [reply],
      };
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

  StoryFeed pageFeed(PagePlayback playback) {
    final feed = FakeStoryFeed([storyEntry(playback.bvid), storyEntry('BV1next000001')]);
    feeds.add((feed: feed, related: null));
    return feed;
  }

  StoryFeed relatedFeed(PagePlayback playback, RelatedStory story) {
    final feed = FakeStoryFeed([for (final card in story.cards) storyEntry(card.bvid)]);
    feeds.add((feed: feed, related: story));
    return feed;
  }

  late Widget Function(VideoRoute route) page;

  /// openVideoPage's plain push, with the test's session, details and feeds.
  Future<void> pushRelated(BuildContext context, VideoRoute route) {
    pushed.add(route);
    return Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => page(route)));
  }

  page = (route) => VideoPage(
    route: route,
    createSession: fakeSession,
    createDetails: fakeDetails,
    openPage: (context, route) => replaceVideoPage(context, route, page: page),
    createStory: pageFeed,
    pushRelated: pushRelated,
    createRelatedStory: relatedFeed,
  );

  void screen(WidgetTester tester, Size size, FakeViewPadding insets) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
  }

  Future<void> host(
    WidgetTester tester, {
    ThemeData? theme,
    Widget Function(Widget app)? wrap,
    bool phone = false,
    SpaceApi? spaceApi,
  }) async {
    if (!phone) {
      screen(tester, _portrait, _portraitInsets);
      addTearDown(tester.view.reset);
    }
    final logger = Logger(session: 'test');
    environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    await environment.refreshAccount();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    PlaybackController make() {
      player = FakePlayer();
      return controller = PlaybackController(
        client: environment.client,
        engine: FakeEngine(),
        player: player,
        clock: time.clock,
        now: () => now,
        startTimer: FakeTimers().start,
        logger: logger,
      );
    }

    playback = AppPlayback(() async => make());
    addTearDown(playback.dispose);
    services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(orientation: orientation, controls: NoDeviceControls()),
      pageApi: api,
      spaceApi: spaceApi,
      loginGate: _Gate(),
    );
    nav = services.navigator;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        navigatorKey: nav,
        navigatorObservers: [pageRoutes],
        builder: (context, child) => AppScope(services: services, child: wrap?.call(child!) ?? child!),
        home: const SizedBox(),
      ),
    );
  }

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  PlayerUi ui(WidgetTester tester) => tester.widget<PanelLayer>(find.byType(PanelLayer).last).ui;
  StorySheetController sheet(WidgetTester tester) => ui(tester).storySheet!;
  final video = find.byKey(const ValueKey('fake-video'));

  /// The page pushed with [shape]'s video, its detail and related videos in, then turned to 竖屏.
  Future<void> vertical(
    WidgetTester tester, {
    ({int width, int height}) shape = _upright264,
    List<VideoCard> related = const [],
    ThemeData? theme,
    Widget Function(Widget app)? wrap,
    bool phone = false,
    PlaySource source = PlaySource.unknown,
    SpaceApi? spaceApi,
  }) async {
    await host(tester, theme: theme, wrap: wrap, phone: phone, spaceApi: spaceApi);
    final route = VideoRoute(bvid: _bv, cid: _p1, start: 0, source: source);
    unawaited(nav.currentState!.push(SwipeBackPageRoute<void>(builder: (_) => page(route))));
    await frames(tester, 20);
    sessions.single
      ..video = controller.video
      ..isVertical = shape.height > shape.width
      ..videoShape = shape
      ..detail = _detail(_bv, reply: 98)
      ..related = related
      ..changed();
    await tester.pump();
    orientation.enterVertical();
    await frames(tester, 4);
    expect(orientation.presentation, Presentation.vertical);
  }

  /// The visible chrome's fade over 竖屏's controls.
  double chromeOpacity(WidgetTester tester) => tester
      .widget<Opacity>(find.ancestor(of: find.byType(VerticalChrome), matching: find.byType(Opacity)).first)
      .opacity;

  Future<void> back(WidgetTester tester) async {
    unawaited(nav.currentState!.maybePop());
    await frames(tester, 20);
  }

  group('opening and closing', () {
    testWidgets("竖屏's 评论 opens the sheet on 评论, the title's call on 简介; landscape's 评论 still goes to the small "
        'player', (tester) async {
      await vertical(tester, shape: _wide269);
      expect(sheet(tester).stop, SheetStop.closed);
      ui(tester).onComments!();
      await frames(tester);
      expect(sheet(tester).stop, SheetStop.half);
      expect(sheet(tester).tab, PageTab.comments);
      expect(orientation.presentation, Presentation.vertical, reason: '竖屏 stays, the sheet over it');
      expect(find.byType(StorySheetView), findsOneWidget);
      expect(sessions.single.calls, isNot(contains('togglePlay')), reason: 'the play state is left as it was');

      sheet(tester).close();
      await frames(tester);
      ui(tester).onIntroSheet!();
      await frames(tester);
      expect(sheet(tester).stop, SheetStop.half);
      expect(sheet(tester).tab, PageTab.intro);
      expect(find.byType(StoryIntro), findsOneWidget);
      sheet(tester).close();
      await frames(tester);

      screen(tester, _landscape, _landscapeInsets);
      orientation.enterLandscape();
      await frames(tester, 4);
      ui(tester).onComments!();
      await frames(tester, 4);
      expect(orientation.presentation, Presentation.inline);
      expect(sheet(tester).stop, SheetStop.closed);
      screen(tester, _portrait, _portraitInsets);
      await frames(tester, 10);
      await back(tester);
    });

    testWidgets('竖屏 ending closes the sheet: 详情页, a turn to landscape, and the page leaving', (tester) async {
      await vertical(tester, shape: _wide269);
      ui(tester).onComments!();
      await frames(tester);
      orientation.exitToInline();
      await frames(tester);
      expect(sheet(tester).stop, SheetStop.closed);
      expect(find.byType(StorySheetView), findsNothing);

      orientation.enterVertical();
      await frames(tester);
      ui(tester).onComments!();
      await frames(tester);
      screen(tester, _landscape, _landscapeInsets);
      orientation.enterLandscape();
      await frames(tester, 10);
      expect(sheet(tester).stop, SheetStop.closed);
      expect(tester.widget<VideoPlayerArea>(find.byType(VideoPlayerArea)).room!.value, isNull);
      screen(tester, _portrait, _portraitInsets);
      orientation.enterVertical();
      await frames(tester);
      expect(sheet(tester).stop, SheetStop.closed, reason: 'back in 竖屏 the sheet stays down');

      ui(tester).onComments!();
      await frames(tester);
      final open = sheet(tester);
      nav.currentState!.pop();
      await tester.pump();
      expect(open.stop, SheetStop.closed);
      await frames(tester, 20);
    });
  });

  group('the picture in the room above it', () {
    testWidgets("264: an upright frame fills the room's height, centred across; closed, it is back in its band", (
      tester,
    ) async {
      await vertical(tester);
      final band = tester.getRect(video);
      expect(band, const Rect.fromLTWH(0, 0, 440, 926));
      ui(tester).onComments!();
      await frames(tester);
      final box = tester.getRect(video);
      expect(box, const Rect.fromLTRB(0, StorySheetRoomTheme.pictureTop, 440, StorySheetTheme.halfTop));
      // What the player draws in that box: 264's picture spans 449-870 × 162-946 px.
      final picture = videoPicture(box.size, fit: FitMode.fit, video: const Size(1080, 2009))!.shift(box.topLeft);
      expect(picture.left * 3, closeTo(449, 2));
      expect(picture.right * 3, closeTo(871, 2));
      expect(picture.top * 3, closeTo(162, 1));
      expect(picture.bottom * 3, closeTo(StorySheetTheme.halfTop * 3, 1));
      expect(sessions.single.calls, isNot(contains('togglePlay')));

      sheet(tester).toggle();
      await frames(tester);
      expect(sheet(tester).stop, SheetStop.full);
      expect(tester.getRect(video).height, 0, reason: '266: the full sheet covers it');

      sheet(tester).close();
      await frames(tester);
      expect(tester.getRect(video), band);
      expect(tester.widget<VideoPlayerArea>(find.byType(VideoPlayerArea)).room!.value, isNull);
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });

    testWidgets('269: a wide one spans the width at 16:9, its bottom on the sheet, with its danmaku flying over it', (
      tester,
    ) async {
      await vertical(tester, shape: _wide269);
      ui(tester).onComments!();
      await frames(tester);
      final box = tester.getRect(video);
      expect(box.width, 440);
      expect(box.height, closeTo(440 * 9 / 16, 0.01));
      expect(box.bottom, closeTo(StorySheetTheme.halfTop, 0.01));
      expect(box.top * 3, closeTo(204, 2), reason: "269's picture starts at 204 px");

      final danmaku = find.byType(DanmakuLayer);
      final shown = tester
          .widget<Visibility>(find.ancestor(of: danmaku, matching: find.byType(Visibility)).first)
          .visible;
      expect(shown, isTrue, reason: 'at rest they fly over the picture');
      expect(tester.getRect(danmaku), box, reason: 'over the whole picture, from its top');
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });

    test("268: the room follows the sheet's top, frame by frame as it is dragged", () {
      // 268's upright frame, its picture's left and right edges (pt) measured with the sheet's top at each place.
      const measured = [(410.0, 124.0, 315.0), (582.0, 79.0, 360.0), (320.0, 148.0, 291.0), (290.0, 156.0, 283.0)];
      const screen = Size(440, 956);
      const shape = Size(422, 785);
      for (final (top, left, right) in measured) {
        final half = StorySheetTheme.halfTop;
        final position = top >= half
            ? (screen.height - top) / (screen.height - half)
            : 1 + (half - top) / (half - StorySheetTheme.fullTop);
        expect(StorySheetController.topFor(position, screen.height), closeTo(top, 0.001));
        final box = storySheetRoom(screen: screen, position: position, upright: true, fit: FitMode.fit, video: shape);
        expect(box.bottom, closeTo(top, 0.001), reason: 'on the sheet at $top');
        final picture = videoPicture(box.size, fit: FitMode.fit, video: shape)!.shift(box.topLeft);
        expect(picture.top, closeTo(StorySheetRoomTheme.pictureTop, 0.5));
        expect(picture.left, closeTo(left, 2), reason: 'at $top');
        expect(picture.right, closeTo(right, 2), reason: 'at $top');
      }
    });

    test('rising from closed, the picture stays in its band until the sheet reaches it', () {
      const screen = Size(440, 956);
      Rect at(double position, bool upright, Size video) =>
          storySheetRoom(screen: screen, position: position, upright: upright, fit: FitMode.fit, video: video);
      const wide = Size(1920, 1080);
      final place = Rect.fromCenter(
        center: Offset(220, 956 * BiliMetrics.verticalVideoCentre),
        width: 440,
        height: 440 * 9 / 16,
      );
      for (final position in [0.01, 0.2, 0.4]) {
        final box = at(position, false, wide);
        expect(box.top, closeTo(place.top, 0.01));
        expect(box.bottom, closeTo(place.bottom, 0.01));
      }
      final low = at(0.9, false, wide);
      expect(low.bottom, closeTo(StorySheetController.topFor(0.9, 956), 0.01));
      expect(low.height, closeTo(440 * 9 / 16, 0.01));
      expect(at(2, false, wide).height, 0);
      // 9:16 in 竖屏's upright band, 72-854: just open, it is where it was.
      final tall = at(0.01, true, const Size(1080, 1920));
      expect(tall.top, closeTo(926 / 2 - 440 * 16 / 9 / 2, 0.01));
    });
  });

  group('while it is up', () {
    testWidgets("竖屏's controls fade out as it rises and back as it closes", (tester) async {
      await vertical(tester);
      expect(chromeOpacity(tester), 1);
      ui(tester).onComments!();
      await frames(tester);
      expect(chromeOpacity(tester), 0, reason: '268: gone at half');
      final ignoring = tester.widgetList<IgnorePointer>(
        find.ancestor(of: find.byType(VerticalChrome), matching: find.byType(IgnorePointer)),
      );
      expect(ignoring.any((widget) => widget.ignoring), isTrue);
      sheet(tester).close();
      await frames(tester);
      expect(chromeOpacity(tester), 1);
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });

    testWidgets('the swipe and the drags on the picture are off, and a tap above it plays or pauses', (tester) async {
      await vertical(tester);
      final feed = feeds.single.feed;
      ui(tester).onComments!();
      await frames(tester);
      await tester.timedDragFrom(const Offset(220, 250), const Offset(0, -200), const Duration(milliseconds: 150));
      await frames(tester, 6);
      expect(feed.moves, isEmpty);
      expect(ui(tester).storyDrag!.moving, isFalse);
      expect(sessions.single.calls, isNot(contains('togglePlay')), reason: 'a drag is no tap');

      await tester.tapAt(const Offset(220, 150));
      await tester.pump(const Duration(milliseconds: 400));
      expect(sessions.single.calls.where((call) => call == 'togglePlay'), hasLength(1));
      expect(sheet(tester).stop, SheetStop.half, reason: 'the tap leaves the sheet up');
      await tester.tapAt(const Offset(300, 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(sessions.single.calls.where((call) => call == 'togglePlay'), hasLength(2));

      sheet(tester).close();
      await frames(tester);
      await tester.timedDragFrom(const Offset(250, 650), const Offset(0, -300), const Duration(milliseconds: 150));
      await frames(tester, 6);
      expect(feed.moves, [1], reason: 'closed, the swipe is back');
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });

    testWidgets('back closes the composer and 评论详情 first, then the sheet, then 竖屏', (tester) async {
      await vertical(tester);
      ui(tester).onComments!();
      await frames(tester, 20);
      final inSheet = find.descendant(of: find.byType(StorySheetView), matching: find.byKey(const ValueKey(100)));
      expect(inSheet, findsOneWidget, reason: "评论's list in the sheet");

      await tester.tap(
        find.descendant(of: inSheet, matching: find.byKey(const ValueKey('comment-replies'))),
      );
      await frames(tester, 20);
      expect(find.byType(ThreadView), findsOneWidget);
      expect(
        tester.getRect(find.byType(ThreadView)).top,
        closeTo(StorySheetTheme.halfTop + StorySheetTheme.headerHeight, 0.01),
        reason: '267: under the tab row',
      );
      await tester.tap(
        find.descendant(of: find.byType(ThreadView), matching: find.byKey(const ValueKey('comment-bar'))),
      );
      await frames(tester);
      expect(find.byType(Composer), findsOneWidget);

      await back(tester);
      expect(find.byType(Composer), findsNothing);
      expect(find.byType(ThreadView), findsOneWidget);
      await back(tester);
      expect(find.byType(ThreadView), findsNothing);
      expect(sheet(tester).stop, SheetStop.half);
      await back(tester);
      expect(sheet(tester).stop, SheetStop.closed);
      expect(orientation.presentation, Presentation.vertical);
      await back(tester);
      expect(orientation.presentation, Presentation.inline);
      await back(tester);
      expect(find.byType(VideoPage), findsNothing);
    });

    testWidgets("the picture viewer opened from its 评论 goes with it: neither a turn to landscape and back nor 详情页 "
        'finds it still up', (tester) async {
      const pictures = [CommentPicture(url: '', width: 1080, height: 1920)];
      await vertical(tester, shape: _wide269);
      ui(tester).onComments!();
      await frames(tester, 20);
      final overlays = tester.widget<CommentOverlays>(find.byType(CommentOverlays)).controller;
      overlays.viewPictures(pictures, 0);
      await frames(tester);
      expect(find.byType(PictureViewer), findsOneWidget);

      screen(tester, _landscape, _landscapeInsets);
      orientation.enterLandscape();
      await frames(tester, 10);
      expect(overlays.value, isNull, reason: 'the sheet closed for the turn, and the viewer with it');
      screen(tester, _portrait, _portraitInsets);
      orientation.enterVertical();
      await frames(tester, 10);
      await back(tester);
      expect(orientation.presentation, Presentation.inline);
      expect(find.byType(PictureViewer), findsNothing, reason: '详情页 bare');

      orientation.enterVertical();
      await frames(tester);
      ui(tester).onComments!();
      await frames(tester, 20);
      overlays.viewPictures(pictures, 0);
      await frames(tester);
      orientation.exitToInline();
      await frames(tester);
      expect(overlays.value, isNull);
      expect(find.byType(PictureViewer), findsNothing);
      await back(tester);
    });

    testWidgets("the left edge's swipe is back too, over the sheet and above it", (tester) async {
      await vertical(tester);
      ui(tester).onComments!();
      await frames(tester);
      await tester.timedDragFrom(const Offset(4, 600), const Offset(300, 0), const Duration(milliseconds: 300));
      await frames(tester);
      expect(sheet(tester).stop, SheetStop.closed);
      expect(orientation.presentation, Presentation.vertical);

      ui(tester).onIntroSheet!();
      await frames(tester);
      await tester.timedDragFrom(const Offset(4, 150), const Offset(300, 0), const Duration(milliseconds: 300));
      await frames(tester);
      expect(sheet(tester).stop, SheetStop.closed);
      expect(orientation.presentation, Presentation.vertical);
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });
  });

  group('相关视频', () {
    final related = [for (var i = 0; i < 25; i++) _card('BV1related${i.toString().padLeft(3, '0')}')];

    testWidgets('a card closes the sheet and pushes its page over this one, with the first 20 and the card tapped', (
      tester,
    ) async {
      await vertical(tester, related: related);
      ui(tester).onIntroSheet!();
      await frames(tester);
      tester.widget<StoryIntro>(find.byType(StoryIntro)).onOpenRelated(3);
      await tester.pump();
      expect(pushed, hasLength(1));
      final route = pushed.single;
      expect(route.bvid, related[3].bvid);
      expect(route.cidHint, related[3].cid);
      expect(route.cover, related[3].cover);
      expect(route.relatedStory!.index, 3);
      expect(route.relatedStory!.cards.map((card) => card.bvid), related.take(20).map((card) => card.bvid));
      await frames(tester, 20);
      expect(find.byType(VideoPage), findsOneWidget, reason: 'the page under it is offstage');
      expect(find.byType(VideoPage, skipOffstage: false), findsNWidgets(2), reason: 'pushed, not in its place');
      expect(sessions.first.player.calls, contains('pause'), reason: 'covered, it pauses as any page does');
      nav.currentState!.pop();
      await frames(tester, 20);
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });

    testWidgets("its page opens straight in 竖屏 on the related list, and ‹ pops it onto this one's 竖屏, sheet down", (
      tester,
    ) async {
      await vertical(tester, related: related);
      final under = sheet(tester);
      ui(tester).onIntroSheet!();
      await frames(tester);
      tester.widget<StoryIntro>(find.byType(StoryIntro)).onOpenRelated(5);
      await tester.pump();
      // The page arrives laid out in 竖屏, not sliding out of a small player's box.
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(VerticalChrome), findsWidgets);
      await frames(tester, 20);
      expect(orientation.presentation, Presentation.vertical);
      expect(feeds.last.related?.index, 5, reason: 'its feed is the related list, from the card tapped');
      expect(ui(tester).story!.value, same(feeds.last.feed));
      expect(find.byType(PageTabRow), findsNothing, reason: 'no body under a small player');

      // Its video comes in: still 竖屏, whatever its shape.
      sessions.last
        ..video = controller.video
        ..isVertical = false
        ..videoShape = _wide269
        ..changed();
      await frames(tester, 4);
      expect(orientation.presentation, Presentation.vertical);

      ui(tester).onBack();
      await frames(tester, 20);
      expect(find.byType(VideoPage, skipOffstage: false), findsOneWidget, reason: '‹ popped it');
      expect(orientation.presentation, Presentation.vertical, reason: '270: back on the old video in 竖屏');
      expect(ui(tester).storySheet, same(under));
      expect(under.stop, SheetStop.closed);
      expect(find.byType(VerticalChrome), findsOneWidget);
      expect(feeds.where((made) => made.related == null), hasLength(1), reason: 'the old feed carried on');
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });

    testWidgets("back from its page, the old video's 竖屏 has its feed and its loop: a swipe moves on", (tester) async {
      await vertical(tester, related: related);
      final feed = feeds.single.feed;
      final under = sessions.single;
      expect(under.loopsAtEnd, isTrue);
      ui(tester).onIntroSheet!();
      await frames(tester);
      tester.widget<StoryIntro>(find.byType(StoryIntro)).onOpenRelated(2);
      await frames(tester, 20);
      expect(ui(tester).story!.value, same(feeds.last.feed));
      expect(sessions.last.loopsAtEnd, isTrue, reason: "its own first claim keeps 竖屏's loop");

      ui(tester).onBack();
      await frames(tester, 20);
      expect(find.byType(VideoPage, skipOffstage: false), findsOneWidget);
      expect(ui(tester).story!.value, same(feed), reason: 'the old feed is still up');
      expect(feed.disposed, isFalse);
      expect(under.loopsAtEnd, isTrue, reason: 'the video loops, no end screen over 竖屏');
      await tester.timedDragFrom(const Offset(250, 650), const Offset(0, -300), const Duration(milliseconds: 150));
      await frames(tester, 6);
      expect(feed.moves, [1]);
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });

    testWidgets('‹ slides its page out still in 竖屏, as does a page a link in the sheet puts in its place', (
      tester,
    ) async {
      Finder areaOf(String bvid) => find.descendant(
        of: find.byWidgetPredicate((widget) => widget is VideoPage && widget.route.bvid == bvid),
        matching: find.byType(VideoPlayerArea),
      );
      await vertical(tester, related: related);
      ui(tester).onIntroSheet!();
      await frames(tester);
      tester.widget<StoryIntro>(find.byType(StoryIntro)).onOpenRelated(1);
      await frames(tester, 20);
      ui(tester).onBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(VideoPage), findsNWidgets(2), reason: 'mid-slide');
      expect(tester.widget<VideoPlayerArea>(areaOf(related[1].bvid)).presentation, Presentation.vertical);
      expect(find.byType(PageTabRow), findsNothing, reason: 'no small player page slides out');
      await frames(tester, 20);
      expect(find.byType(VideoPage), findsOneWidget);

      ui(tester).onIntroSheet!();
      await frames(tester);
      tester.widget<StoryIntro>(find.byType(StoryIntro)).onOpenVideo('BV1xx411c7mD');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(VideoPage), findsNWidgets(2), reason: 'the new page slides in over it');
      expect(tester.widget<VideoPlayerArea>(areaOf(_bv)).presentation, Presentation.vertical);
      await frames(tester, 20);
      expect(find.byType(VideoPage, skipOffstage: false), findsOneWidget, reason: 'replaced, not stacked');
      await back(tester);
    });

    testWidgets("its page's reports name where this page's 竖屏 was entered from, without that video's track data", (
      tester,
    ) async {
      const entered = PlaySource(fromSpmid: 'tm.recommend.0.0', from: '7', trackId: 'TRACK', flowData: '{"f":1}');
      await vertical(tester, related: related, source: entered);
      ui(tester).onIntroSheet!();
      await frames(tester);
      tester.widget<StoryIntro>(find.byType(StoryIntro)).onOpenRelated(3);
      await frames(tester, 20);
      final source = pushed.single.source;
      expect((source.fromSpmid, source.from), ('tm.recommend.0.0', '7'));
      expect((source.trackId, source.flowData), (null, null));

      // And on from there: its own related page names the same place.
      sessions.last
        ..video = controller.video
        ..videoShape = _upright264
        ..detail = _detail(related[3].bvid)
        ..related = related
        ..changed();
      await frames(tester, 4);
      ui(tester).onIntroSheet!();
      await frames(tester);
      tester.widget<StoryIntro>(find.byType(StoryIntro).last).onOpenRelated(0);
      await frames(tester, 20);
      expect(pushed, hasLength(2));
      expect((pushed.last.source.fromSpmid, pushed.last.source.trackId), ('tm.recommend.0.0', null));
      nav.currentState!.pop();
      await frames(tester, 20);
      nav.currentState!.pop();
      await frames(tester, 20);
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });

    testWidgets('a second tap before its page is up stacks no other', (tester) async {
      await vertical(tester, related: related);
      ui(tester).onIntroSheet!();
      await frames(tester);
      final intro = tester.widget<StoryIntro>(find.byType(StoryIntro));
      intro
        ..onOpenRelated(1)
        ..onOpenRelated(2);
      await tester.pump();
      intro.onOpenRelated(3);
      await frames(tester, 20);
      expect(pushed.map((route) => route.bvid), [related[1].bvid]);
      expect(find.byType(VideoPage, skipOffstage: false), findsNWidgets(2));
      nav.currentState!.pop();
      await frames(tester, 20);
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });

    testWidgets('brought back by the small window, its page is one again: 竖屏 on the related list, ‹ pops it', (
      tester,
    ) async {
      await vertical(tester, related: related);
      ui(tester).onIntroSheet!();
      await frames(tester);
      tester.widget<StoryIntro>(find.byType(StoryIntro)).onOpenRelated(4);
      await frames(tester, 20);
      final small = player;
      small.emit(const PictureInPictureChanged(true));
      await tester.pump();
      ui(tester).onBack();
      await frames(tester, 20);
      expect(find.byType(VideoPage, skipOffstage: false), findsOneWidget);
      expect(services.pipKeeper.kept, isNotNull, reason: 'the small window keeps it');

      small.emit(const PictureInPictureRestore());
      await frames(tester, 20);
      final pages = tester.widgetList<VideoPage>(find.byType(VideoPage, skipOffstage: false)).toList();
      expect(pages, hasLength(2));
      expect(pages.last.route.relatedStory?.index, 4);
      expect(orientation.presentation, Presentation.vertical);
      expect(feeds.last.related?.index, 4, reason: 'its feed is the related list again');
      expect(ui(tester).story!.value, same(feeds.last.feed));

      small.emit(const PictureInPictureChanged(false));
      await tester.pump();
      ui(tester).onBack();
      await frames(tester, 20);
      expect(find.byType(VideoPage, skipOffstage: false), findsOneWidget, reason: '‹ popped it');
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });

    testWidgets('its 详情页 keeps its own small player', (tester) async {
      await vertical(tester, related: related);
      ui(tester).onIntroSheet!();
      await frames(tester);
      tester.widget<StoryIntro>(find.byType(StoryIntro)).onOpenRelated(0);
      await frames(tester, 20);
      orientation.exitToInline();
      await frames(tester);
      expect(find.byType(VideoPage, skipOffstage: false), findsNWidgets(2));
      expect(find.byType(PageTabRow), findsOneWidget, reason: 'its own small player and tabs');
      await back(tester);
      expect(find.byType(VideoPage, skipOffstage: false), findsOneWidget);
      orientation.exitToInline();
      await frames(tester);
      await back(tester);
    });
  });

  group('a page pushed over it', () {
    testWidgets("a commenter's space from its 评论: back in 竖屏 with the feed and the sheet as they were, the space "
        'with bars of its own; pushed with the sheet down, the page comes back as before', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method.startsWith('SystemChrome.setEnabledSystemUI')) calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await vertical(tester, spaceApi: FakeSpaceApi());
      final feed = feeds.single.feed;
      ui(tester).onComments!();
      await frames(tester, 20);
      final inSheet = find.descendant(of: find.byType(StorySheetView), matching: find.byKey(const ValueKey(100)));
      await tester.tap(find.descendant(of: inSheet, matching: find.byKey(const ValueKey('comment-avatar'))));
      await frames(tester, 20);
      expect(find.byType(SpacePage), findsOneWidget);
      expect(calls.last.method, 'SystemChrome.setEnabledSystemUIMode');
      expect(calls.last.arguments, 'SystemUiMode.edgeToEdge', reason: "the space's home indicator stays");

      nav.currentState!.pop();
      await frames(tester, 20);
      expect(orientation.presentation, Presentation.vertical);
      expect(ui(tester).story!.value, same(feed));
      expect(feed.disposed, isFalse);
      expect(sessions.single.loopsAtEnd, isTrue);
      expect(sheet(tester).stop, SheetStop.half);
      expect(sheet(tester).tab, PageTab.comments);
      expect(find.byType(StorySheetView), findsOneWidget);
      expect(calls.last.method, 'SystemChrome.setEnabledSystemUIOverlays');
      expect(calls.last.arguments, ['SystemUiOverlay.top']);

      sheet(tester).close();
      await frames(tester);
      unawaited(openSpace(tester.element(find.byType(VideoPlayerArea)), const UploaderRef(mid: 5)));
      await frames(tester, 20);
      nav.currentState!.pop();
      await frames(tester, 20);
      expect(orientation.presentation, Presentation.inline, reason: '竖屏 given up under it, as before');
      await back(tester);
    });
  });

  group('look-alikes, saved for tools/screen_diff.py', () {
    for (final (name, shape, tab) in [
      ('264', _upright264, PageTab.comments),
      ('269', _wide269, PageTab.intro),
    ]) {
      testWidgets('$name: the picture and the sheet', (tester) async {
        final saved = BiliFonts.family;
        addTearDown(() => BiliFonts.family = saved);
        await tester.runAsync(loadSystemFontStandIns);
        showAsPhone(tester);
        final picture = ValueNotifier<Rect?>(null);
        addTearDown(picture.dispose);
        await vertical(
          tester,
          shape: shape,
          theme: appTheme(),
          phone: true,
          // The native view's picture as AVPlayer fits it, in a stand-in colour.
          wrap: (app) => RepaintBoundary(
            key: const ValueKey('screen'),
            child: Stack(
              fit: StackFit.expand,
              children: [
                app,
                ValueListenableBuilder(
                  valueListenable: picture,
                  builder: (context, rect, _) => rect == null
                      ? const SizedBox.shrink()
                      : Positioned.fromRect(
                          rect: rect,
                          child: const IgnorePointer(child: ColoredBox(color: Color(0xFF8E8460))),
                        ),
                ),
              ],
            ),
          ),
        );
        BiliFonts.family = BiliFonts.system;
        if (tab == PageTab.comments) {
          ui(tester).onComments!();
        } else {
          ui(tester).onIntroSheet!();
        }
        await frames(tester, 20);
        final box = tester.getRect(video);
        picture.value = videoPicture(
          box.size,
          fit: FitMode.fit,
          video: Size(shape.width.toDouble(), shape.height.toDouble()),
        )!.shift(box.topLeft);
        await tester.pump();
        final shots = Platform.environment['BILIFAST_SHOTS'];
        if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/story-sheet-$name.png');
        expect(sheet(tester).stop, SheetStop.half);
        sheet(tester).close();
        await frames(tester);
        orientation.exitToInline();
        await frames(tester);
        await back(tester);
      });
    }
  });
}

typedef FeedRecord = ({FakeStoryFeed feed, RelatedStory? related});

class _Gate implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

VideoDetail _detail(String bvid, {int reply = 0}) => VideoDetail(
  bvid: bvid,
  aid: 1,
  title: '测试视频',
  cover: '',
  pubdate: 0,
  duration: 97,
  desc: '',
  descParts: const [],
  copyright: 1,
  owner: VideoOwner.empty,
  stat: VideoStat(view: 0, danmaku: 0, reply: reply, favorite: 0, coin: 0, share: 0, like: 0),
  pages: const [],
  season: null,
  staff: const [],
  width: 1080,
  height: 1920,
  honor: null,
  redirectURL: null,
);

VideoCard _card(String bvid) => VideoCard(
  aid: 2,
  bvid: bvid,
  cid: 30,
  title: '相关视频',
  cover: '',
  duration: 60,
  ownerMid: 4,
  ownerName: 'UP',
  views: 1,
  danmaku: 1,
  likes: 1,
);

Comment _comment(int rpid, {int root = 0, int parent = 0, int replyCount = 0, List<Comment> preview = const []}) =>
    Comment(
      rpid: rpid,
      oid: 1,
      mid: 2001,
      root: root,
      parent: parent,
      ctime: rpid,
      likes: 10,
      replyCount: replyCount,
      member: CommentMember(mid: 2001, name: '测试用户$rpid', level: 5),
      message: '第$rpid条评论',
      runs: [TextRun('第$rpid条评论')],
      previewReplies: preview,
    );
