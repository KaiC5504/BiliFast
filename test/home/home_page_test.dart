import 'dart:async';
import 'dart:convert';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/zoom_back_route.dart';
import 'package:bilifast/history/watch_history_page.dart';
import 'package:bilifast/home/avatar_page.dart';
import 'package:bilifast/home/feed_model.dart';
import 'package:bilifast/home/feed_more_sheet.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/search/search_api.dart';
import 'package:bilifast/search/search_page.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/video/intro/title_block.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator, CupertinoSliverRefreshControl;
import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../video/mixed_lines.dart';
import 'fake_login_gate.dart';
import 'feed_fakes.dart';

const _watchLaterPath = '/x/v2/history/toview/add';

/// A store that keeps the system font on, where the default one would turn this platform's MiSans back on.
FontStore _systemFont() => FontStore.memory()..select(FontChoice.system);

/// The fingerprint cookies alone: logged out, with no `spi` call.
const _loggedOutCookies = {'buvid3': 'b3', 'buvid4': 'b4'};

/// The search entry's default word.
const _word = '崩铁新版本即将上线';

class _FailingSearchApi extends FakeSearchApi {
  @override
  Future<String?> defaultWord() async {
    calls.add('defaultWord');
    throw Exception('offline');
  }
}

void main() {
  late FeedHttp http;
  late FakePlayer player;
  late PlaybackController controller;
  late RecentStore recents;
  late AppEnvironment environment;
  late FakeLoginGate gate;

  setUp(() {
    http = FeedHttp();
    http.pages[1] = [feedItem('BV1aaa', reason: '1万点赞'), feedItem('BV1bbb')];
    player = FakePlayer();
    gate = FakeLoginGate();
  });

  List<Map<String, Object?>> twenty() => [for (var i = 0; i < 20; i++) feedItem('BV1c$i')];

  Future<void> show(
    WidgetTester tester, {
    bool developer = false,
    double scale = 1,
    bool still = false,
    Map<String, String> cookies = Canned.cookies,
    ThemeData? theme,
    FontStore? fonts,
    SearchApi? search,
    String? initialLink,
  }) async {
    tester.view.physicalSize = const Size(440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (scale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    if (still) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    final logger = Logger(session: 'test');
    environment = await AppEnvironment.load(keychain: FakeKeychain(StoredCookies(cookies)), http: http, logger: logger);
    await environment.refreshAccount();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    // Each video page gets a controller and player of its own; [controller] is the newest.
    final playback = AppPlayback(() async {
      player = FakePlayer();
      return controller = PlaybackController(
        client: environment.client,
        engine: FakeEngine(),
        player: player,
        clock: ManualClock(10000).clock,
        now: () => now,
        startTimer: FakeTimers().start,
        logger: logger,
      );
    });
    recents = await RecentStore.load(null, logger: logger);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: recents,
      loginGate: gate,
      fonts: fonts,
      searchApi: search ?? FakeSearchApi(defaultWord: _word),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: HomePage(developerPage: developer ? (context) => const Text('开发者页面') : null, initialLink: initialLink),
      ),
    );
  }

  /// Lets requests answer and frames run without waiting on the loading cards' endless sweep.
  Future<void> settle(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Lets a toast run out, so its timer is not left pending.
  Future<void> toastGone(WidgetTester tester) => settle(tester, 60);

  Finder card(String bvid) => find.byKey(ValueKey('feed-card-$bvid'));

  /// The card's cover picture, only while drawn: not left Offstage in the Hero's placeholder from the push's flight.
  Finder cover(String bvid) => find.descendant(
    of: find.descendant(of: card(bvid), matching: find.byType(Hero)),
    matching: find.byType(RemoteImage),
  );

  Finder entrance(String bvid) => find.descendant(of: card(bvid), matching: find.byType(SlideTransition));

  testWidgets('loading cards sweep until the feed answers, then two columns of cards', (tester) async {
    http.gates[1] = Completer<void>();
    await show(tester);
    await settle(tester, 2);
    expect(find.text('推荐'), findsOneWidget);
    expect(card('BV1aaa'), findsNothing);
    http.gates[1]!.complete();
    await settle(tester);
    expect(find.text('视频 BV1aaa'), findsOneWidget);
    expect(find.text('1万点赞'), findsOneWidget, reason: 'the reason tag');
    expect(find.text('UP BV1bbb'), findsOneWidget);
    expect(find.text('1.2万'), findsNWidgets(2));
    expect(find.text('2:05'), findsNWidgets(2));
    final first = tester.getTopLeft(card('BV1aaa'));
    final second = tester.getTopLeft(card('BV1bbb'));
    expect(first.dy, second.dy, reason: 'side by side');
    expect(http.asked.first, 1);
  });

  group('under the system font a line mixing Latin and Chinese sits on the Chinese line', () {
    testWidgets('a card\'s title over both lines, its uploader and its reason', (tester) async {
      await useSystemFont(tester);
      http.pages[1] = [feedItem('BV1aaa', title: mixedLines, reason: '1万点赞'), feedItem('BV1bbb')];
      await show(tester, theme: appTheme(), fonts: _systemFont());
      await settle(tester);
      expectOnChineseLine(tester, find.text('$mixedLines BV1aaa'));
      expectOnChineseLine(tester, find.text('UP BV1bbb'));
      expectOnChineseLine(tester, find.text('1万点赞'));
    });

    testWidgets("the search entry's default word", (tester) async {
      await useSystemFont(tester);
      await show(
        tester,
        theme: appTheme(),
        fonts: _systemFont(),
        search: FakeSearchApi(defaultWord: mixedLine),
      );
      await settle(tester);
      expectOnChineseLine(tester, find.text(mixedLine));
    });

    testWidgets('a failed feed\'s message', (tester) async {
      await useSystemFont(tester);
      http.failing.add(1);
      await show(tester, theme: appTheme(), fonts: _systemFont());
      await settle(tester);
      expectOnChineseLine(tester, find.byKey(const ValueKey('feed-error')));
    });
  });

  testWidgets('a failed feed says why, and 重试 loads it', (tester) async {
    http.failing.add(1);
    await show(tester);
    await settle(tester);
    expect(find.byKey(const ValueKey('feed-error')), findsOneWidget);
    http.failing.clear();
    await tester.tap(find.byKey(const ValueKey('feed-retry')));
    await settle(tester);
    expect(find.text('视频 BV1aaa'), findsOneWidget);
  });

  testWidgets('an empty first page says so with 重试 instead of loading forever', (tester) async {
    http.pages[1] = [];
    await show(tester);
    await settle(tester);
    expect(find.text(FeedModel.emptyMessage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    http.pages[1] = twenty();
    await tester.tap(find.byKey(const ValueKey('feed-retry')));
    await settle(tester);
    expect(card('BV1c0'), findsOneWidget);
    expect(http.asked, [1, 1]);
  });

  testWidgets('the next page is asked for only near the end of the grid, never by building cards', (tester) async {
    http.pages[1] = twenty();
    http.pages[2] = [for (var i = 20; i < 40; i++) feedItem('BV1c$i')];
    await show(tester);
    await settle(tester, 40);
    expect(http.asked, [1], reason: 'the end is far below the screen');
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -3000));
    await settle(tester, 20);
    expect(http.asked, [1, 2]);
  });

  testWidgets('a short feed whose next pages add nothing asks three more times, then offers 没有更多了', (tester) async {
    await show(tester);
    await settle(tester, 40);
    expect(http.asked, [1, 2, 3, 4]);
    expect(find.text(FeedModel.endMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-more')), findsNothing, reason: 'no spinner while nothing loads');

    http.pages[5] = [feedItem('BV1ccc')];
    await tester.tap(find.byKey(const ValueKey('feed-retry')));
    await settle(tester, 40);
    expect(http.asked.take(5), [1, 2, 3, 4, 5]);
    expect(card('BV1ccc'), findsOneWidget);
  });

  testWidgets('a failed load more waits for 重试 instead of asking again', (tester) async {
    http.pages[1] = twenty();
    http.failing.add(2);
    await show(tester);
    await settle(tester);
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -3000));
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('feed-error')), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -300));
    await settle(tester, 20);
    expect(http.asked, [1, 2]);
    http.failing.clear();
    http.pages[2] = [for (var i = 20; i < 40; i++) feedItem('BV1c$i')];
    await tester.tap(find.byKey(const ValueKey('feed-retry')));
    await settle(tester, 20);
    expect(http.asked, [1, 2, 2]);
    expect(find.byKey(const ValueKey('feed-error')), findsNothing);
  });

  testWidgets('a pull to refresh that fails keeps the cards and says why in a toast', (tester) async {
    http.pages[1] = twenty();
    await show(tester);
    await settle(tester);
    http.failing.add(1);
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, 500));
    await settle(tester, 20);
    expect(http.asked, [1, 1]);
    expect(find.text('网络请求失败（HTTP 500）'), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-error')), findsNothing);
    expect(card('BV1c0'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets("推荐's pull shows the TV: held while dragged short of the trigger, cycling while it refreshes", (
    tester,
  ) async {
    http.pages[1] = twenty();
    await show(tester);
    await settle(tester);
    Finder spinners() => find.descendant(
      of: find.byType(CupertinoSliverRefreshControl),
      matching: find.byType(CupertinoActivityIndicator),
    );
    final feed = find.byKey(const ValueKey('feed'));
    final pull = await tester.startGesture(tester.getCenter(feed));
    for (var i = 0; i < 4; i++) {
      await pull.moveBy(const Offset(0, 20));
      await tester.pump();
    }
    expect(find.byType(LoadingTv), findsOneWidget);
    // The builder's box spans the width; the 60 pt face is scaled down into it, centred.
    expect(tester.getSize(find.byType(LoadingTv)).height, LoadingTvTheme.size);
    expect(tester.getCenter(find.byType(LoadingTv)).dx, 220);
    await tester.pump(LoadingTvTheme.frame * 2);
    expect(tvFace(tester), 0, reason: 'held');
    expect(spinners(), findsNothing);
    expect(http.asked, [1], reason: 'short of the trigger');

    http.gates[1] = Completer<void>();
    for (var i = 0; i < 10; i++) {
      await pull.moveBy(const Offset(0, 40));
      await tester.pump();
    }
    await pull.up();
    await settle(tester, 10);
    expect(http.asked, [1, 1]);
    expect(find.byType(LoadingTv), findsOneWidget);
    final first = tvFace(tester);
    await tester.pump(LoadingTvTheme.frame);
    expect(tvFace(tester), (first + 1) % LoadingTv.frames.length, reason: 'cycling');
    expect(spinners(), findsNothing);

    http.pages[1] = [for (var i = 0; i < 20; i++) feedItem('BV1n$i')];
    http.gates[1]!.complete();
    await settle(tester, 30);
    expect(card('BV1n0'), findsOneWidget);
    expect(find.byType(LoadingTv), findsNothing);
  });

  testWidgets('home goes idle once the feed shows: nothing ticks, no frame waits', (tester) async {
    http.pages[1] = twenty();
    http.gates[1] = Completer<void>();
    await show(tester);
    await settle(tester, 2);
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'the loading cards sweep');
    http.gates[1]!.complete();
    await settle(tester, 40);
    expect(card('BV1c0'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('cards fade in the first time they appear, never again when scrolled back', (tester) async {
    http.pages[1] = twenty();
    await show(tester);
    await settle(tester, 20);
    expect(entrance('BV1c0'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -2500));
    await settle(tester, 20);
    expect(card('BV1c0'), findsNothing, reason: 'scrolled out and let go');
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, 2500));
    await tester.pump();
    expect(card('BV1c0'), findsOneWidget);
    expect(entrance('BV1c0'), findsNothing);
    await settle(tester, 20);
  });

  testWidgets('with reduced motion the cards just appear and the loading cards keep still', (tester) async {
    http.pages[1] = twenty();
    http.gates[1] = Completer<void>();
    await show(tester, still: true);
    await settle(tester, 2);
    expect(tester.binding.transientCallbackCount, 0);
    http.gates[1]!.complete();
    await tester.pump();
    await tester.pump();
    expect(card('BV1c0'), findsOneWidget);
    expect(entrance('BV1c0'), findsNothing);
  });

  testWidgets('--play= opens its part on the video page, with no zoom back, lands in 最近打开, and back closes it', (
    tester,
  ) async {
    await show(tester, initialLink: 'https://www.bilibili.com/video/BV1GJ411x7h7?p=2');
    await settle(tester, 20);
    expect(controller.video?.title, '测试视频');
    expect(controller.page?.cid, 137649200);
    expect(shownTitle(tester), '测试视频', reason: 'the page shows the video it opened');
    expect(recents.items.single.id, 'BV1GJ411x7h7#137649200');
    final route = tester.widget<VideoPage>(find.byType(VideoPage)).route;
    expect(route.detail?.bvid, 'BV1GJ411x7h7', reason: 'the signed view that resolved the link, for its 合集');
    expect(route.zoomSource, isNull);
    expect(ModalRoute.of(tester.element(find.byType(VideoPage))), isNot(isA<ZoomBackPageRoute<void>>()));
    expect(http.canned.to(Canned.signedViewPath), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('video-back')));
    await settle(tester, 20);
    expect(find.text('推荐'), findsOneWidget);
    expect(controller.video, isNull, reason: 'the page gave the player back');
  });

  testWidgets('--play= shows the spinner while its link resolves', (tester) async {
    http.canned.gates[Canned.signedViewPath] = Completer<void>();
    await show(tester, initialLink: 'https://www.bilibili.com/video/BV1GJ411x7h7?p=2');
    await settle(tester);
    expect(find.byKey(const ValueKey('opening')), findsOneWidget);
    expect(find.byType(VideoPage), findsNothing);
    http.canned.gates[Canned.signedViewPath]!.complete();
    await settle(tester, 20);
    expect(find.byType(VideoPage), findsOneWidget);
    expect(find.byKey(const ValueKey('opening')), findsNothing);
  });

  testWidgets('--play= to a video in parts asks which part, with no spinner left behind the sheet', (tester) async {
    await show(tester, initialLink: 'BV1GJ411x7h7');
    await settle(tester, 20);
    expect(find.text('选择分P'), findsOneWidget);
    expect(find.byKey(const ValueKey('opening')), findsNothing);
    await tester.tap(find.text('P1 第一集'));
    await settle(tester, 20);
    expect(controller.page?.cid, 137649199);
  });

  testWidgets('a card opens its video page with the card title first', (tester) async {
    http.canned.gates[Canned.signedViewPath] = Completer<void>();
    await show(tester);
    await settle(tester);
    await tester.tap(card('BV1aaa'));
    await settle(tester, 20);
    expect(tester.widget<VideoPage>(find.byType(VideoPage)).route.title, '视频 BV1aaa');
    expect(shownTitle(tester), isNull, reason: '简介 waits for the video\'s detail');
    http.canned.gates[Canned.signedViewPath]!.complete();
    await settle(tester, 20);
    expect(controller.video?.title, '测试视频');
    expect(shownTitle(tester), '测试视频', reason: 'the page shows the video it opened');
  });

  testWidgets("a card opens the page that swipes back into it, with the card's rect", (tester) async {
    await show(tester);
    await settle(tester);
    final resting = tester.getRect(card('BV1aaa'));
    await tester.tap(card('BV1aaa'));
    await settle(tester, 20);
    final source = tester.widget<VideoPage>(find.byType(VideoPage)).route.zoomSource!;
    expect(ModalRoute.of(tester.element(find.byType(VideoPage))), isA<ZoomBackPageRoute<void>>());
    expect(source()!.size, resting.size);

    // Once the page shrinks home stops being slid aside, so the card is where the page lands.
    final gesture = await tester.startGesture(const Offset(5, 600));
    for (var i = 1; i <= 4; i++) {
      await gesture.moveTo(Offset(5 + 10.0 * i, 600), timeStamp: Duration(milliseconds: 16 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getRect(find.byType(VideoPage)).width, lessThan(440), reason: 'the page is shrunk');
    expect(source(), resting);
    // Held still before letting go, so it springs back.
    await gesture.moveTo(const Offset(45, 600), timeStamp: const Duration(milliseconds: 200));
    await gesture.up(timeStamp: const Duration(milliseconds: 300));
    await settle(tester, 20);
    expect(find.byType(VideoPage), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('video-back')));
    await settle(tester, 20);
    expect(source(), resting, reason: 'back where it was once the page has gone');
    expect(cover('BV1aaa'), findsOneWidget, reason: "the card's cover is back after a spring back and 〈");
  });

  testWidgets("〈 straight from a card's page flies back into it, and the card shows its cover again", (tester) async {
    await show(tester);
    await settle(tester);
    await tester.tap(card('BV1aaa'));
    await settle(tester, 20);
    await tester.tap(find.byKey(const ValueKey('video-back')));
    await settle(tester, 20);
    expect(find.byType(VideoPage), findsNothing);
    expect(cover('BV1aaa'), findsOneWidget, reason: 'not left Offstage in the Hero placeholder from the push');
  });

  group('swipe back on the real video page', () {
    for (final (where, y) in [('over the player', 150.0), ('over the body', 600.0)]) {
      testWidgets('from the left edge $where it flies back into the card', (tester) async {
        await show(tester);
        await settle(tester);
        final resting = tester.getRect(card('BV1aaa'));
        await tester.tap(card('BV1aaa'));
        await settle(tester, 20);
        expect(find.byType(VideoPage), findsOneWidget);
        final gesture = await tester.startGesture(Offset(5, y));
        for (var i = 1; i <= 10; i++) {
          await gesture.moveTo(Offset(5 + 25.0 * i, y), timeStamp: Duration(milliseconds: 16 * i));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final shrunk = tester.getRect(find.byType(VideoPage));
        expect(shrunk.width, lessThan(440), reason: 'the page shrinks under the finger');
        await gesture.up(timeStamp: const Duration(milliseconds: 176));
        await settle(tester, 20);
        expect(find.byType(VideoPage), findsNothing);
        expect(tester.getRect(card('BV1aaa')), resting);
        expect(cover('BV1aaa'), findsOneWidget, reason: "the card's cover is back");
      });
    }
  });

  testWidgets("⋮ opens 90's sheet whose 添加至稍后再看 adds the video; a web card has no 不感兴趣", (tester) async {
    http.canned.routes[_watchLaterPath] = (200, '{"code":0,"message":"0","ttl":1}');
    await show(tester);
    await settle(tester);
    final more = find.descendant(of: card('BV1aaa'), matching: find.byKey(const ValueKey('card-more')));
    expect(tester.getSize(more), const Size.square(24), reason: "Swift's tap target");
    await tester.tap(more);
    await settle(tester);
    expect(find.byType(FeedSheetRow), findsOneWidget);
    expect(find.text('添加至稍后再看'), findsOneWidget);
    expect(find.textContaining('不感兴趣'), findsNothing);
    expect(find.descendant(of: find.byType(FeedSheetRow), matching: find.byType(InkWell)), findsNothing);
    await tester.tap(find.byKey(const ValueKey('feed-more-watch-later')));
    await settle(tester);
    expect(find.byType(FeedSheetRow), findsNothing);
    expect(find.text('已添加至稍后再看'), findsOneWidget);
    final sent = Uri.splitQueryString(utf8.decode(http.canned.to(_watchLaterPath).single.body!));
    expect(sent['aid'], '${'BV1aaa'.hashCode.abs()}');
    await toastGone(tester);

    await tester.tap(more);
    await settle(tester);
    await tester.tapAt(const Offset(220, 300));
    await settle(tester);
    expect(find.byType(FeedSheetRow), findsNothing, reason: 'a tap on the dim closes it');
    expect(http.canned.to(_watchLaterPath), hasLength(1));
  });

  testWidgets('the avatar opens its page, whose 全部 lists 最近打开 while logged out, and back returns home', (tester) async {
    http = FeedHttp(loggedIn: false);
    await show(tester, developer: true);
    await settle(tester);
    recents.add(const RecentVideo(bvid: 'BV1x', cid: 3, title: '最近的视频', part: '', page: 1, pageCount: 1));
    await tester.tap(find.byKey(const ValueKey('home-avatar')));
    await settle(tester, 20);
    expect(find.byType(AvatarPage), findsOneWidget);
    expect(find.text('最近的视频'), findsOneWidget, reason: 'in the card on the page');
    expect(find.text('开发者'), findsNothing, reason: '开发者 is in 设置');
    await tester.tap(find.byKey(const ValueKey('avatar-all')));
    await settle(tester, 20);
    expect(find.text('最近打开'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ListView), matching: find.byType(InkWell)),
      findsNothing,
      reason: 'recents rows highlight instead of rippling',
    );
    await tester.tap(find.byKey(const ValueKey('recents-clear')));
    await settle(tester, 20);
    await tester.tap(find.byKey(const ValueKey('recents-clear-confirm')));
    await settle(tester, 20);
    expect(recents.items, isEmpty);

    await tester.pageBack();
    await settle(tester, 20);
    expect(find.text('还没有打开过视频'), findsOneWidget, reason: 'the avatar page follows the store');
    await tester.tap(find.byKey(const ValueKey('avatar-back')));
    await settle(tester, 20);
    expect(find.byType(AvatarPage), findsNothing);
    expect(find.text('推荐'), findsOneWidget);
  });

  testWidgets('⚙ on the avatar page opens 设置 with the font in use', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('home-avatar')));
    await settle(tester, 20);
    await tester.tap(find.byKey(const ValueKey('avatar-settings')));
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('settings-font')), findsOneWidget);
    expect(find.text('MiSans'), findsOneWidget);
  });

  testWidgets('back on home from the avatar page, an account check that failed is tried again', (tester) async {
    http.canned.routes[Canned.navPath] = (500, '');
    await show(tester);
    await settle(tester);
    expect(environment.account, isA<AccountUnknown>());
    expect(environment.accountCheckFailed, isTrue);

    Future<void> visit() async {
      await tester.tap(find.byKey(const ValueKey('home-avatar')));
      await settle(tester, 20);
      expect(find.byType(AvatarPage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('avatar-back')));
      await settle(tester, 20);
    }

    http.canned.routes[Canned.navPath] = (200, Canned.navLoggedIn);
    final asked = http.canned.to(Canned.navPath).length;
    await visit();
    expect(environment.account, isA<LoggedIn>());
    expect(http.canned.to(Canned.navPath), hasLength(asked + 1));

    await visit();
    expect(http.canned.to(Canned.navPath), hasLength(asked + 1), reason: 'a known account is not asked again');
  });

  testWidgets('历史记录 on the avatar page opens 历史记录, and back returns to the page', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('home-avatar')));
    await settle(tester, 20);
    await tester.tap(find.byKey(const ValueKey('avatar-history')));
    await settle(tester, 20);
    expect(find.byType(WatchHistoryPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester, 20);
    expect(find.byType(WatchHistoryPage), findsNothing);
    expect(find.byType(AvatarPage), findsOneWidget);
  });

  testWidgets('推荐 refreshes once when the account logs in or out, and not on other account news', (tester) async {
    http.pages[1] = twenty();
    http.canned.routes[Canned.navPath] = (200, Canned.navLoggedOut);
    await show(tester, cookies: _loggedOutCookies);
    await settle(tester, 20);
    expect(environment.account, isA<LoggedOut>());
    expect(http.asked, [1]);

    Future<void> check() async {
      await environment.refreshAccount();
      await settle(tester, 20);
    }

    await check();
    expect(http.asked, [1], reason: 'still logged out');

    http.canned.errors[Canned.navPath] = Exception('offline');
    await check();
    expect(environment.account, isA<LoggedOut>());
    expect(http.asked, [1], reason: 'a failed check changes nothing');
    http.canned.errors.remove(Canned.navPath);

    environment.cookies.set('SESSDATA', 's');
    http.canned.routes[Canned.navPath] = (200, Canned.navLoggedIn);
    await check();
    expect(environment.account, isA<LoggedIn>());
    expect(http.asked, [1, 1], reason: 'logged in');

    await check();
    expect(http.asked, [1, 1], reason: 'still logged in');

    http.canned.routes[Canned.navPath] = (200, Canned.navLoggedOut);
    await check();
    expect(environment.account, isA<LoginExpired>());
    expect(http.asked, [1, 1, 1], reason: 'expired');

    environment.cookies.remove('SESSDATA');
    await check();
    expect(environment.account, isA<LoggedOut>());
    expect(http.asked, [1, 1, 1], reason: 'expired to logged out is no flip');
  });

  for (final (state, cookies) in [('logged out', _loggedOutCookies), ('expired', Canned.cookies)]) {
    testWidgets('$state, ⋮ 稍后再看 opens the login page and sends nothing', (tester) async {
      http.canned.routes[Canned.navPath] = (200, Canned.navLoggedOut);
      http.canned.routes[_watchLaterPath] = (200, '{"code":0,"message":"0","ttl":1}');
      await show(tester, cookies: cookies);
      await settle(tester);
      expect(environment.account, anyOf(isA<LoggedOut>(), isA<LoginExpired>()));
      await tester.tap(find.descendant(of: card('BV1aaa'), matching: find.byKey(const ValueKey('card-more'))));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('feed-more-watch-later')));
      await settle(tester);
      expect(gate.requests, 1);
      expect(http.canned.to(_watchLaterPath), isEmpty);
      expect(find.text('已添加至稍后再看'), findsNothing);
    });
  }

  testWidgets('logged in, a needs-login answer to 稍后再看 opens the login page instead of a toast', (tester) async {
    http.canned.routes[_watchLaterPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
    await show(tester);
    await settle(tester);
    expect(environment.account, isA<LoggedIn>());
    await tester.tap(find.descendant(of: card('BV1aaa'), matching: find.byKey(const ValueKey('card-more'))));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('feed-more-watch-later')));
    await settle(tester);
    expect(http.canned.to(_watchLaterPath), hasLength(1));
    expect(gate.requests, 1);
    expect(find.text('需要登录'), findsNothing);
  });

  testWidgets('cards are buttons named by their title, with ⋮ and 稍后再看 as their actions', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    await settle(tester);
    expect(
      tester.getSemantics(card('BV1aaa')),
      isSemantics(
        label: '视频 BV1aaa',
        isButton: true,
        hasTapAction: true,
        customActions: const [CustomSemanticsAction(label: '更多'), CustomSemanticsAction(label: '稍后再看')],
      ),
    );
    semantics.dispose();
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets('nothing overflows at text scale $scale, on home or the avatar page', (tester) async {
      await show(tester, scale: scale);
      await settle(tester);
      expect(card('BV1aaa'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-avatar')));
      await settle(tester, 20);
      expect(find.byType(AvatarPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('the search entry', () {
    testWidgets('shows the default word, asked for once, and opens 搜索 with it; back returns home', (tester) async {
      final search = FakeSearchApi(defaultWord: _word);
      final semantics = tester.ensureSemantics();
      await show(tester, search: search);
      await settle(tester);
      expect(find.text(_word), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'a bar to tap, not a field');
      expect(
        tester.getSemantics(find.byKey(const ValueKey('home-search'))),
        isSemantics(label: '搜索', value: _word, isButton: true, hasTapAction: true),
      );

      await tester.tap(find.byKey(const ValueKey('home-search')));
      await settle(tester, 20);
      expect(tester.widget<SearchPage>(find.byType(SearchPage)).placeholder, _word);
      await tester.binding.handlePopRoute();
      await settle(tester, 20);
      expect(find.byType(SearchPage), findsNothing);
      expect(find.text(_word), findsOneWidget);
      expect(search.calls.where((call) => call == 'defaultWord'), hasLength(1));
      semantics.dispose();
    });

    testWidgets('greys while pressed, in its stadium, and clears when let go or the press moves off', (tester) async {
      await show(tester);
      await settle(tester);
      ShapeDecoration face() =>
          tester.widget<Container>(find.byKey(const ValueKey('home-search-field'))).foregroundDecoration!
              as ShapeDecoration;
      expect(face().color, isNull);

      final press = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('home-search'))));
      await tester.pump(kPressTimeout);
      expect(face().color, BiliColors.pressedFill);
      expect(face().shape, isA<StadiumBorder>());
      await press.moveBy(const Offset(0, 200));
      await tester.pump();
      expect(face().color, isNull, reason: 'dragged off, no tap');
      await press.up();
      await settle(tester);
      expect(find.byType(SearchPage), findsNothing);

      final tap = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('home-search'))));
      await tester.pump(kPressTimeout);
      expect(face().color, BiliColors.pressedFill);
      await tap.up();
      await tester.pump();
      expect(face().color, isNull);
      await settle(tester, 20);
      expect(find.byType(SearchPage), findsOneWidget);
    });

    testWidgets('a failed default word leaves the bar empty, and 搜索 opens with none', (tester) async {
      await show(tester, search: _FailingSearchApi());
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('home-search-word'))).data, isEmpty);
      await tester.tap(find.byKey(const ValueKey('home-search')));
      await settle(tester, 20);
      expect(tester.widget<SearchPage>(find.byType(SearchPage)).placeholder, isNull);
    });
  });

  group('the bottom bar', () {
    testWidgets('five slots across the bottom over the home indicator, the feed ending at it', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester);
      tester.view
        ..padding = const FakeViewPadding(bottom: 34)
        ..viewPadding = const FakeViewPadding(bottom: 34);
      await settle(tester);
      final bar = tester.getRect(find.byType(HomeTabBar));
      expect(bar.bottom, 900);
      expect(bar.height, 49 + 34);
      expect(tester.getRect(find.byKey(const ValueKey('feed'))).bottom, bar.top);

      for (final (i, tab) in HomeTab.values.indexed) {
        final slot = find.byKey(ValueKey('home-tab-${tab.name}'));
        expect(tester.getRect(slot), Rect.fromLTWH(88.0 * i, bar.top, 88, 49));
        expect(
          tester.getSemantics(slot),
          isSemantics(
            label: tab.label,
            isButton: true,
            hasTapAction: true,
            hasSelectedState: true,
            isSelected: tab == HomeTab.home,
          ),
        );
        if (tab == HomeTab.post) {
          expect(find.text(tab.label), findsNothing, reason: 'the + has no label');
          continue;
        }
        final label = find.text(tab.label);
        expect(tester.getCenter(label).dx, 44 + 88.0 * i);
        expect(tester.getTopLeft(label).dy, greaterThan(bar.top + 30));
        expect(tester.widget<Text>(label).style?.color, tab == HomeTab.home ? BiliColors.pink : HomeTabBarTheme.label);
      }
      semantics.dispose();
    });

    testWidgets('关注, +, 消息 and 我的 say 暂未开放 and change nothing', (tester) async {
      await show(tester);
      await settle(tester, 40);
      final asked = List.of(http.asked);
      for (final tab in [HomeTab.follow, HomeTab.post, HomeTab.messages, HomeTab.mine]) {
        await tester.tap(find.byKey(ValueKey('home-tab-${tab.name}')));
        await tester.pump();
        expect(find.text('暂未开放'), findsOneWidget, reason: tab.label);
        await toastGone(tester);
        expect(find.byType(HomePage), findsOneWidget);
        expect(find.byType(SearchPage), findsNothing);
        expect(http.asked, asked, reason: 'no refresh');
      }
    });
  });

  group("首页's tap", () {
    ScrollPosition feedScroll(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(of: find.byKey(const ValueKey('feed')), matching: find.byType(Scrollable)).first,
        )
        .position;

    Finder reloadTv() =>
        find.descendant(of: find.byKey(const ValueKey('feed-reload')), matching: find.byType(LoadingTv));

    List<Map<String, Object?>> fresh() => [for (var i = 0; i < 20; i++) feedItem('BV1n$i')];

    Future<void> tapHome(WidgetTester tester) => tester.tap(find.byKey(const ValueKey('home-tab-home')));

    testWidgets('scrolled, goes back to the top and refreshes 推荐 once, the TV up until the new cards', (
      tester,
    ) async {
      http.pages[1] = twenty();
      await show(tester);
      await settle(tester);
      await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -1500));
      await settle(tester, 20);
      final from = feedScroll(tester).pixels;
      expect(from, greaterThan(1000));
      final asked = http.asked.length;
      http.pages[1] = fresh();
      http.gates[1] = Completer<void>();

      await tapHome(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(http.asked.sublist(asked), [1], reason: 'straight away, not after the scroll');
      expect(feedScroll(tester).pixels, inExclusiveRange(0, from), reason: 'scrolling, not jumped');
      expect(reloadTv(), findsNothing, reason: 'the TV opens once at the top');
      await settle(tester, 10);
      expect(feedScroll(tester).pixels, 0);
      expect(reloadTv(), findsOneWidget);
      expect(card('BV1c0'), findsOneWidget, reason: 'the old cards stay until the new ones come');

      http.gates[1]!.complete();
      await settle(tester, 20);
      expect(card('BV1n0'), findsOneWidget);
      expect(card('BV1c0'), findsNothing);
      expect(find.byKey(const ValueKey('feed-reload')), findsNothing);
      expect(http.asked.sublist(asked), [1]);
      await settle(tester, 40);
      expect(tester.binding.transientCallbackCount, 0, reason: 'nothing left ticking');
    });

    testWidgets('the header holds the cycling TV centred in its 60 pt band, above the cards', (tester) async {
      http.pages[1] = twenty();
      await show(tester);
      await settle(tester);
      final cardTop = tester.getTopLeft(card('BV1c0')).dy;
      http.gates[1] = Completer<void>();
      await tapHome(tester);
      await settle(tester, 10);
      final band = tester.getRect(find.byKey(const ValueKey('feed-reload')));
      expect(band.height, LoadingTvTheme.size);
      expect(tester.getRect(reloadTv()), Rect.fromCenter(center: band.center, width: 60, height: 60));
      expect(tester.getTopLeft(card('BV1c0')).dy, cardTop + LoadingTvTheme.size);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('feed-reload')),
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsNothing,
      );
      final first = tvFace(tester);
      await tester.pump(LoadingTvTheme.frame);
      expect(tvFace(tester), (first + 1) % LoadingTv.frames.length);
      http.gates[1]!.complete();
      await settle(tester, 20);
      expect(find.byType(LoadingTv), findsNothing);
    });

    testWidgets('at the top, refreshes 推荐 once with the TV up', (tester) async {
      http.pages[1] = twenty();
      await show(tester);
      await settle(tester);
      expect(feedScroll(tester).pixels, 0);
      http.pages[1] = fresh();
      http.gates[1] = Completer<void>();
      await tapHome(tester);
      await settle(tester, 6);
      expect(http.asked, [1, 1]);
      expect(reloadTv(), findsOneWidget);
      expect(feedScroll(tester).pixels, 0);
      http.gates[1]!.complete();
      await settle(tester, 20);
      expect(card('BV1n0'), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-reload')), findsNothing);
      expect(http.asked, [1, 1]);
    });

    testWidgets('does nothing more during the first load or a refresh, from a tap or a pull', (tester) async {
      http.pages[1] = twenty();
      http.gates[1] = Completer<void>();
      await show(tester);
      await settle(tester, 2);
      await tapHome(tester);
      await settle(tester, 2);
      expect(http.asked, [1], reason: 'the first load is running');
      http.gates[1]!.complete();
      await settle(tester);

      http.gates[1] = Completer<void>();
      await tapHome(tester);
      await settle(tester, 10);
      await tapHome(tester);
      await settle(tester, 10);
      await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, 500));
      await settle(tester, 10);
      expect(http.asked, [1, 1]);
      http.gates[1]!.complete();
      await settle(tester, 20);
      expect(http.asked, [1, 1]);
      expect(find.byKey(const ValueKey('feed-reload')), findsNothing);

      await tapHome(tester);
      await settle(tester, 20);
      expect(http.asked, [1, 1, 1], reason: 'once the refresh is done a tap refreshes again');
    });

    testWidgets('during the refresh after a login, a tap or a pull waits on it instead of asking again', (
      tester,
    ) async {
      http.pages[1] = twenty();
      http.canned.routes[Canned.navPath] = (200, Canned.navLoggedOut);
      await show(tester, cookies: _loggedOutCookies);
      await settle(tester, 20);
      expect(environment.account, isA<LoggedOut>());
      expect(http.asked, [1]);

      http.pages[1] = fresh();
      http.gates[1] = Completer<void>();
      environment.cookies.set('SESSDATA', 's');
      http.canned.routes[Canned.navPath] = (200, Canned.navLoggedIn);
      await environment.refreshAccount();
      await settle(tester, 4);
      expect(environment.account, isA<LoggedIn>());
      expect(http.asked, [1, 1], reason: 'the login refresh, held');

      await tapHome(tester);
      await settle(tester, 10);
      expect(http.asked, [1, 1], reason: 'a tap');
      await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, 500));
      await settle(tester, 10);
      expect(http.asked, [1, 1], reason: 'a pull');

      http.gates[1]!.complete();
      await settle(tester, 20);
      expect(http.asked, [1, 1]);
      expect(card('BV1n0'), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-reload')), findsNothing);
    });

    testWidgets('with reduced motion jumps to the top and shows the TV at once, on its first face', (tester) async {
      http.pages[1] = twenty();
      await show(tester, still: true);
      await settle(tester);
      await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -1500));
      await settle(tester, 20);
      expect(feedScroll(tester).pixels, greaterThan(1000));
      http.gates[1] = Completer<void>();
      await tapHome(tester);
      await tester.pump();
      expect(feedScroll(tester).pixels, 0);
      expect(reloadTv(), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('feed-reload'))).height, 60, reason: 'already open');
      await tester.pump(LoadingTvTheme.frame * 2);
      expect(tvFace(tester), 0);
      http.gates[1]!.complete();
      await settle(tester, 4);
      expect(find.byKey(const ValueKey('feed-reload')), findsNothing);
    });

    testWidgets('a refresh that fails keeps the cards and says why in a toast', (tester) async {
      http.pages[1] = twenty();
      await show(tester);
      await settle(tester);
      http.failing.add(1);
      await tapHome(tester);
      await settle(tester, 20);
      expect(http.asked, [1, 1]);
      expect(find.text('网络请求失败（HTTP 500）'), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-error')), findsNothing);
      expect(find.byKey(const ValueKey('feed-reload')), findsNothing);
      expect(card('BV1c0'), findsOneWidget);
      await toastGone(tester);
    });
  });
}

/// The title the video page's title block shows; null before the video's detail arrives.
String? shownTitle(WidgetTester tester) {
  final blocks = find.byType(TitleBlock, skipOffstage: false);
  return blocks.evaluate().isEmpty ? null : tester.widget<TitleBlock>(blocks.first).detail.title;
}

/// The face the one loading TV on screen shows.
int tvFace(WidgetTester tester) {
  for (var face = 0; face < LoadingTv.frames.length; face++) {
    if (find.byKey(ValueKey('loading-tv-$face')).evaluate().isNotEmpty) return face;
  }
  fail('no loading TV');
}
