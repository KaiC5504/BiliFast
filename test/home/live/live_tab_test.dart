import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/zoom_back_route.dart';
import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/home/live/live_tab.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/following/live_following_page.dart';
import 'package:bilifast/live/room/live_room_page.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../autoplay_rules.dart';
import 'live_support.dart';

void main() {
  final list = find.byKey(const ValueKey('live-list'));

  Future<LiveHarness> show(WidgetTester tester, {FakeLiveApi? api, bool active = true, bool loggedIn = true}) async {
    final harness = LiveHarness(api: api)..active.value = active;
    await pumpLive(tester, await liveServices(api: harness.api, loggedIn: loggedIn), harness.tab());
    await settle(tester);
    return harness;
  }

  Future<void> pull(WidgetTester tester) async {
    final gesture = await tester.startGesture(tester.getTopLeft(list) + const Offset(220, 400));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
  }

  Finder area(LiveArea area) => find.byKey(ValueKey('live-area-${area.id}-${area.parentId}'));

  group('the page', () {
    setUp(() => LivePlayers());

    testWidgets('nothing is asked until it first shows; then the TV until the feed, then every section of 205', (
      tester,
    ) async {
      final api = FakeLiveApi(feedPages: [liveFeedPage()]);
      final hold = api.holds['feed'] = Completer<void>();
      final harness = await show(tester, api: api, active: false);
      expect(api.calls, isEmpty);

      harness.active.value = true;
      await settle(tester);
      expect(api.calls, ['feed page=1']);
      expect(find.byType(LoadingTvState), findsOneWidget);

      hold.complete();
      api.holds.clear();
      await settle(tester);
      expect(find.byType(LoadingTvState), findsNothing);
      expect(find.byKey(const ValueKey('live-carousel')), findsOneWidget);
      expect(find.text('大卡直播间 甲'), findsOneWidget, reason: "the middle card's title");
      expect(find.byKey(const ValueKey('live-big-tag')), findsWidgets, reason: '直播中');
      expect(find.byKey(const ValueKey('live-following')), findsOneWidget);
      expect(find.text('1人正在直播', findRichText: true), findsOneWidget);
      expect(find.text('查看全部'), findsOneWidget);
      expect(find.text('关注的主播'), findsOneWidget);
      for (final name in ['推荐', '聊天室', '颜值', '虚拟主播']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.byKey(const ValueKey('live-grid-9000')), findsOneWidget);
      expect(find.text('测试直播间 0'), findsOneWidget);
      expect(find.text('1.2万'), findsOneWidget, reason: '👁 on the cover');

      harness.active.value = false;
      await settle(tester);
      harness.active.value = true;
      await settle(tester);
      expect(api.tabCalls, ['feed page=1'], reason: 'loaded once');
    });

    testWidgets('the layout as 205 measures it: the carousel, the strip, the area row and the two columns', (
      tester,
    ) async {
      await show(tester);
      final listTop = tester.getTopLeft(list).dy;
      final carousel = tester.getRect(find.byKey(const ValueKey('live-carousel')));
      expect(carousel.top - listTop, moreOrLessEquals(LiveTabTheme.carouselTop));
      expect(carousel.height, moreOrLessEquals(384 * 9 / 16 + 38));
      final middle = tester.getRect(find.byKey(const ValueKey('live-big-open-9100')).hitTestable());
      expect(middle.left, moreOrLessEquals(28));
      expect(middle.width, moreOrLessEquals(384));

      final strip = tester.getRect(find.byKey(const ValueKey('live-following')));
      expect(strip.left, 5);
      expect(strip.width, 430);
      expect(strip.top - carousel.bottom, moreOrLessEquals(5));
      expect(strip.height, moreOrLessEquals(139));

      final row = tester.getRect(find.byKey(const ValueKey('live-areas')));
      expect(row.top, moreOrLessEquals(strip.bottom));
      expect(row.height, 42);

      final first = tester.getRect(find.byKey(const ValueKey('live-grid-9000')));
      final second = tester.getRect(find.byKey(const ValueKey('live-grid-9001')));
      expect(first.top, moreOrLessEquals(row.bottom));
      expect((first.left, first.width), (5, 212));
      expect(second.left, moreOrLessEquals(222));
      expect(second.right, moreOrLessEquals(434));
      expect(first.height, moreOrLessEquals(159 + 50.0));
    });

    testWidgets('a ranked big room shows its rank and 查看榜单 under the video, in place of its title', (tester) async {
      await show(tester);
      await tester.fling(find.byKey(const ValueKey('live-carousel')), const Offset(-300, 0), 1000);
      await settle(tester, 20);
      expect(find.text('人气榜TOP·2').hitTestable(), findsOneWidget);
      expect(find.text('2009助力值').hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-big-board')).hitTestable());
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('更多直播, the area icons and a card\'s ⋮ say 暂未开放 and ask nothing', (tester) async {
      final harness = await show(tester);
      for (final key in ['live-big-more', 'live-area-cover', 'live-area-all', 'live-card-more-9000']) {
        await tester.tap(find.byKey(ValueKey(key)).hitTestable());
        await tester.pump();
        expect(find.text('暂未开放'), findsOneWidget, reason: key);
        await toastGone(tester);
      }
      expect(harness.api.tabCalls, ['feed page=1']);
    });

    testWidgets('the strip is hidden when nobody followed is live', (tester) async {
      await show(tester, api: FakeLiveApi(feedPages: [liveFeedPage(following: false)]));
      expect(find.byKey(const ValueKey('live-following')), findsNothing);
      expect(find.byKey(const ValueKey('live-areas')), findsOneWidget);
    });

    testWidgets('logged out the page still loads, with no strip', (tester) async {
      final harness = await show(tester, loggedIn: false);
      expect(harness.api.tabCalls, ['feed page=1']);
      expect(find.byKey(const ValueKey('live-carousel')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-following')), findsNothing);
      expect(find.byKey(const ValueKey('live-grid-9000')), findsOneWidget);
    });

    testWidgets("choosing an area asks its first page once, drawn bold over the others; 推荐 shows the feed's again", (
      tester,
    ) async {
      final chat = liveAreas.first;
      final api = FakeLiveApi(
        feedPages: [liveFeedPage()],
        areaPages: {
          chat.id: [LiveCardPage(page: 1, cards: liveCards(4, from: 50), hasMore: false)],
        },
      );
      await show(tester, api: api);
      Text label(String name) => tester.widget<Text>(find.text(name));
      expect(label('推荐').style!.fontWeight, FontWeight.w600);
      expect(label('聊天室').style!.color, BiliColors.secondaryText);

      await tester.tap(area(chat));
      await settle(tester);
      expect(api.tabCalls, ['feed page=1', 'area 11 page=1']);
      expect(label('聊天室').style!.fontWeight, FontWeight.w600);
      expect(label('推荐').style!.color, BiliColors.secondaryText);
      expect(find.byKey(const ValueKey('live-grid-9050')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-grid-9000')), findsNothing);
      expect(find.byKey(const ValueKey('live-end')), findsOneWidget, reason: 'one page, the end');

      await tester.tap(area(LiveArea.recommend));
      await settle(tester);
      expect(find.byKey(const ValueKey('live-grid-9000')), findsOneWidget);
      await tester.tap(area(chat));
      await settle(tester);
      expect(api.tabCalls, ['feed page=1', 'area 11 page=1'], reason: 'kept');
    });

    testWidgets('an area that fails says why with 重试 in place of its rooms; 重试 asks it again', (tester) async {
      final chat = liveAreas.first;
      final api = FakeLiveApi(
        feedPages: [liveFeedPage()],
        areaPages: {
          chat.id: [LiveCardPage(page: 1, cards: liveCards(2, from: 50))],
        },
      );
      api.failures['area'] = Exception('offline');
      await show(tester, api: api);
      await tester.tap(area(chat));
      await settle(tester);
      expect(find.byKey(const ValueKey('live-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-carousel')), findsOneWidget, reason: 'the top stays');

      api.failures.clear();
      await tester.tap(find.byKey(const ValueKey('live-retry')));
      await settle(tester);
      expect(api.tabCalls, ['feed page=1', 'area 11 page=1', 'area 11 page=1']);
      expect(find.byKey(const ValueKey('live-grid-9050')), findsOneWidget);
    });

    testWidgets("a pull asks the feed's first page again, then the area chosen's; the others ask again when chosen", (
      tester,
    ) async {
      final api = FakeLiveApi(
        feedPages: [liveFeedPage()],
        areaPages: {
          11: [LiveCardPage(page: 1, cards: liveCards(2, from: 50))],
          12: [LiveCardPage(page: 1, cards: liveCards(2, from: 60))],
        },
      );
      await show(tester, api: api);
      await tester.tap(area(liveAreas[1]));
      await settle(tester);
      await tester.tap(area(liveAreas[0]));
      await settle(tester);
      expect(api.tabCalls, ['feed page=1', 'area 12 page=1', 'area 11 page=1']);

      await pull(tester);
      await settle(tester, 20);
      expect(api.tabCalls.skip(3), ['feed page=1', 'area 11 page=1'], reason: 'one pull, the top and the area shown');
      await tester.tap(area(liveAreas[1]));
      await settle(tester);
      expect(api.tabCalls.last, 'area 12 page=1', reason: 'dropped by the refresh');
    });

    testWidgets('a pull that fails with rooms on screen keeps them and says why in a toast', (tester) async {
      final harness = await show(tester);
      harness.api.failures['feed'] = Exception('offline');
      await pull(tester);
      await settle(tester, 20);
      expect(find.byKey(const ValueKey('live-grid-9000')), findsOneWidget);
      expect(find.text('加载失败，请稍后重试'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('near the end the next page is asked once, the small spinner under the rooms; the end says so', (
      tester,
    ) async {
      final api = FakeLiveApi(
        feedPages: [
          liveFeedPage(),
          LiveFeedPage(page: 2, cards: liveCards(20, from: 20), hasMore: true),
        ],
      );
      await show(tester, api: api);
      final hold = api.holds['feed page=2'] = Completer<void>();
      await tester.drag(list, const Offset(0, -2400));
      await settle(tester);
      expect(api.tabCalls, ['feed page=1', 'feed page=2']);
      expect(find.byKey(const ValueKey('live-more-spinner')), findsOneWidget);
      await tester.drag(list, const Offset(0, -50));
      await settle(tester);
      expect(api.tabCalls, ['feed page=1', 'feed page=2'], reason: 'one call out at a time');

      hold.complete();
      await settle(tester);
      await tester.drag(list, const Offset(0, -6000));
      await settle(tester);
      expect(api.tabCalls, ['feed page=1', 'feed page=2', 'feed page=3']);
      expect(find.byKey(const ValueKey('live-end')), findsOneWidget, reason: 'page 3 added nothing');
      await tester.drag(list, const Offset(0, -500));
      await settle(tester);
      expect(api.tabCalls.length, 3, reason: 'nothing loops');
    });

    testWidgets('a first load that fails says why with 重试, which asks again', (tester) async {
      final api = FakeLiveApi(feedPages: [liveFeedPage()]);
      api.failures['feed'] = Exception('offline');
      await show(tester, api: api);
      expect(find.byKey(const ValueKey('live-error')), findsOneWidget);
      api.failures.clear();
      await tester.tap(find.byKey(const ValueKey('live-retry')));
      await settle(tester);
      expect(api.tabCalls, ['feed page=1', 'feed page=1']);
      expect(find.byKey(const ValueKey('live-carousel')), findsOneWidget);
    });

    testWidgets('an empty feed says so', (tester) async {
      await show(tester, api: FakeLiveApi(feedPages: [const LiveFeedPage(page: 1)]));
      expect(find.byKey(const ValueKey('live-empty')), findsOneWidget);
      expect(find.text(LiveTab.emptyMessage), findsOneWidget);
    });

    testWidgets('scrolling folds the header by its offset; 首页 goes back to the top and refreshes once', (tester) async {
      final harness = await show(tester);
      await tester.drag(list, const Offset(0, -300));
      await settle(tester);
      expect(harness.offset.value, greaterThan(200));

      harness.tapHome();
      await settle(tester, 20);
      expect(harness.offset.value, 0);
      expect(harness.api.tabCalls, ['feed page=1', 'feed page=1']);
      harness.tapHome();
      harness.tapHome();
      await settle(tester, 20);
      expect(harness.api.tabCalls.length, 3, reason: 'a tap while one runs asks nothing more');
    });

    testWidgets('a tap on a room opens it, zooming from its card; 查看全部 opens 206', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('live-grid-9000')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LiveRoomPage), findsOneWidget);
      final route = ModalRoute.of(tester.element(find.byType(LiveRoomPage)))!;
      expect(route, isA<ZoomBackPageRoute<void>>());
      expect(tester.widget<LiveRoomPage>(find.byType(LiveRoomPage)).entry.roomId, 9000);
      expect(tester.widget<LiveRoomPage>(find.byType(LiveRoomPage)).entry.title, '测试直播间 0');
      Navigator.of(tester.element(find.byType(LiveRoomPage))).pop();
      await settle(tester, 20);

      await tester.tap(find.byKey(const ValueKey('live-big-open-9100')).hitTestable());
      await settle(tester, 10);
      expect(tester.widget<LiveRoomPage>(find.byType(LiveRoomPage)).entry.roomId, 9100);
      expect(ModalRoute.of(tester.element(find.byType(LiveRoomPage))), isA<ZoomBackPageRoute<void>>());
      Navigator.of(tester.element(find.byType(LiveRoomPage))).pop();
      await settle(tester, 20);

      await tester.tap(find.byKey(const ValueKey('live-following-room-9200')));
      await settle(tester, 10);
      expect(tester.widget<LiveRoomPage>(find.byType(LiveRoomPage)).entry.roomId, 9200);
      Navigator.of(tester.element(find.byType(LiveRoomPage))).pop();
      await settle(tester, 20);

      await tester.tap(find.byKey(const ValueKey('live-following-all')));
      await settle(tester, 10);
      expect(find.byType(LiveFollowingPage), findsOneWidget);
    });
  });

  group("the carousel's stream", () {
    late LivePlayers players;

    setUp(() {
      players = LivePlayers();
      autoplayRules();
    });

    Finder sound() => find.byKey(const ValueKey('live-big-sound'));

    /// The middle card's player reports its picture.
    Future<void> playing(WidgetTester tester) async {
      players.last.emit(const StatusChanged(PlayerStatus.playing));
      await settle(tester);
    }

    testWidgets('the middle card plays muted once the page shows; 🔇 and 弹 toggle the sound and the danmaku', (
      tester,
    ) async {
      final harness = await show(tester, active: false);
      expect(players.made, isEmpty);
      harness.active.value = true;
      await settle(tester, 20);
      expect(players.made, hasLength(1), reason: 'the middle card only');
      expect(players.last.calls, contains('muted true'));
      expect(find.byKey(const ValueKey('live-big-loading')), findsOneWidget);
      expect(harness.api.calls.where((call) => call.contains('9100')), [
        'playInfo 9100 qn=-',
        'channel 9100',
      ], reason: "the stream and its danmaku only: nothing of the room page's, no 历史记录 entry");

      await playing(tester);
      expect(find.byKey(const ValueKey('live-big-loading')), findsNothing);
      expect(find.byKey(const ValueKey('live-big-video')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-big-danmaku')), findsOneWidget);
      await tester.tap(sound());
      await tester.pump();
      expect(players.last.calls.last, 'muted false');
      expect(FeedInlineChoices.sound.value, isTrue);
      await tester.tap(find.byKey(const ValueKey('live-big-danmaku-toggle')));
      await tester.pump();
      expect(FeedInlineChoices.danmaku.value, isFalse);
    });

    testWidgets('a page over 首页 pauses it; back, it plays on; covered past 30 s its player goes', (tester) async {
      await show(tester);
      await settle(tester, 20);
      await playing(tester);
      final first = players.last;
      expect(sound(), findsOneWidget);

      final navigator = Navigator.of(tester.element(list));
      unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const SizedBox())));
      await settle(tester, 20);
      expect(first.calls, contains('pause'));
      navigator.pop();
      await settle(tester, 20);
      expect(sound(), findsOneWidget, reason: 'playing again');
      expect(players.made, hasLength(1), reason: 'the same player');

      unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const SizedBox())));
      await settle(tester, 20);
      await tester.pump(FeedBigCardTheme.releaseAfter);
      expect(first.disposed, isTrue);
      navigator.pop();
      await settle(tester, 20);
      expect(players.made, hasLength(2), reason: 'a fresh one back on 首页');
    });

    testWidgets('the page off screen stills it', (tester) async {
      final harness = await show(tester);
      await settle(tester, 20);
      await playing(tester);
      harness.active.value = false;
      await settle(tester);
      expect(players.last.calls, contains('pause'));
      expect(sound(), findsNothing);
    });

    testWidgets('首页自动播放 off holds it', (tester) async {
      PlayerPrefs.shared.homeAutoplay = AutoplayChoice.off;
      await show(tester);
      await settle(tester, 20);
      expect(players.made, isEmpty);
    });

    testWidgets('仅WiFi on mobile data holds it', (tester) async {
      autoplayRules(cellular: true).homeAutoplay = AutoplayChoice.wifiOnly;
      await show(tester);
      await settle(tester, 20);
      expect(players.made, isEmpty);
    });

    testWidgets('swiping the carousel lets the old card go and plays the new middle one', (tester) async {
      await show(tester);
      await settle(tester, 20);
      final first = players.last;
      await tester.fling(find.byKey(const ValueKey('live-carousel')), const Offset(-300, 0), 1000);
      await settle(tester, 20);
      expect(first.disposed, isTrue);
      expect(players.made, hasLength(2));
    });
  });
}
