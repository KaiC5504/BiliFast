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
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/shared/menu.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/video/intro/title_block.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import 'fake_login_gate.dart';
import 'feed_fakes.dart';

const _watchLaterPath = '/x/v2/history/toview/add';

/// The fingerprint cookies alone: logged out, with no `spi` call.
const _loggedOutCookies = {'buvid3': 'b3', 'buvid4': 'b4'};

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
    controller = PlaybackController(
      client: environment.client,
      engine: FakeEngine(),
      player: player,
      clock: ManualClock(10000).clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    recents = await RecentStore.load(null, logger: logger);
    final playback = AppPlayback(() async => controller);
    addTearDown(playback.dispose);
    final services = AppServices(environment: environment, playback: playback, recents: recents, loginGate: gate);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: HomePage(developerPage: developer ? (context) => const Text('开发者页面') : null),
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

  testWidgets('a pasted link opens its part on the video page, lands in 最近打开, and back closes it', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('home-link')), 'https://www.bilibili.com/video/BV1GJ411x7h7?p=2');
    await settle(tester, 20);
    expect(controller.video?.title, '测试视频');
    expect(controller.page?.cid, 137649200);
    expect(shownTitle(tester), '测试视频', reason: 'the page shows the video it opened');
    expect(recents.items.single.id, 'BV1GJ411x7h7#137649200');
    final route = tester.widget<VideoPage>(find.byType(VideoPage)).route;
    expect(route.detail?.bvid, 'BV1GJ411x7h7', reason: 'the signed view that resolved the link, for its 合集');
    expect(http.canned.to(Canned.signedViewPath), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('video-back')));
    await settle(tester, 20);
    expect(find.text('推荐'), findsOneWidget);
    expect(controller.video, isNull, reason: 'the page gave the player back');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('home-link'))).controller!.text, isEmpty);
  });

  testWidgets('a link to a video in parts asks which part, with no spinner left behind the sheet', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('home-link')), 'BV1GJ411x7h7');
    await tester.testTextInput.receiveAction(TextInputAction.go);
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

  testWidgets("a card opens the page that swipes back into it, with the card's rect; a pasted link does not", (
    tester,
  ) async {
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
    await tester.enterText(find.byKey(const ValueKey('home-link')), 'https://www.bilibili.com/video/BV1GJ411x7h7?p=2');
    await settle(tester, 20);
    expect(tester.widget<VideoPage>(find.byType(VideoPage)).route.zoomSource, isNull);
    expect(ModalRoute.of(tester.element(find.byType(VideoPage))), isNot(isA<ZoomBackPageRoute<void>>()));
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

  testWidgets('⋮ opens a frosted menu beside it whose 稍后再看 adds the video', (tester) async {
    http.canned.routes[_watchLaterPath] = (200, '{"code":0,"message":"0","ttl":1}');
    await show(tester);
    await settle(tester);
    final more = find.descendant(of: card('BV1aaa'), matching: find.byKey(const ValueKey('card-more')));
    expect(tester.getSize(more), const Size.square(24), reason: "Swift's tap target");
    await tester.tap(more);
    await settle(tester);
    expect(find.byType(GlassPanel), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.descendant(of: find.byType(GlassPanel), matching: find.byType(InkWell)),
      findsNothing,
      reason: 'no Material ripple in the menu',
    );
    await tester.tap(find.byKey(const ValueKey('card-watch-later')));
    await settle(tester);
    expect(find.byType(GlassPanel), findsNothing);
    expect(find.text('已添加至稍后再看'), findsOneWidget);
    final sent = Uri.splitQueryString(utf8.decode(http.canned.to(_watchLaterPath).single.body!));
    expect(sent['aid'], '${'BV1aaa'.hashCode.abs()}');
    await toastGone(tester);

    await tester.tap(more);
    await settle(tester);
    await tester.tapAt(const Offset(220, 850));
    await settle(tester);
    expect(find.byType(GlassPanel), findsNothing, reason: 'a tap elsewhere closes it');
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
      await tester.tap(find.byKey(const ValueKey('card-watch-later')));
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
    await tester.tap(find.byKey(const ValueKey('card-watch-later')));
    await settle(tester);
    expect(http.canned.to(_watchLaterPath), hasLength(1));
    expect(gate.requests, 1);
    expect(find.text('需要登录'), findsNothing);
  });

  testWidgets('cards are buttons named by their title, with 稍后再看 as their action', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    await settle(tester);
    expect(
      tester.getSemantics(card('BV1aaa')),
      isSemantics(
        label: '视频 BV1aaa',
        isButton: true,
        hasTapAction: true,
        customActions: const [CustomSemanticsAction(label: '稍后再看')],
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

  testWidgets("on iOS the link field's edit menu is the system's, whose Paste asks nothing", (tester) async {
    tester.platformDispatcher.supportsShowingSystemContextMenu = true;
    addTearDown(tester.platformDispatcher.resetSupportsShowingSystemContextMenu);
    await show(tester);
    await settle(tester);
    expect(await editMenu(tester), isA<SystemContextMenu>());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets("elsewhere the link field's edit menu is Flutter's own", (tester) async {
    await show(tester);
    await settle(tester);
    expect(await editMenu(tester), isA<AdaptiveTextSelectionToolbar>());
  });
}

/// What the link field shows as its edit menu once focused.
Future<Widget> editMenu(WidgetTester tester) async {
  final field = find.byKey(const ValueKey('home-link'));
  await tester.tap(field);
  await tester.pump();
  final editable = find.descendant(of: field, matching: find.byType(EditableText));
  final state = tester.state<EditableTextState>(editable);
  return tester.widget<TextField>(field).contextMenuBuilder!(tester.element(editable), state);
}

/// The title the video page's title block shows; null before the video's detail arrives.
String? shownTitle(WidgetTester tester) {
  final blocks = find.byType(TitleBlock, skipOffstage: false);
  return blocks.evaluate().isEmpty ? null : tester.widget<TitleBlock>(blocks.first).detail.title;
}
