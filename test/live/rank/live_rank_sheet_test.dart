import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/live/live_badges.dart';
import 'package:bilifast/live/live_entry.dart';
import 'package:bilifast/live/rank/rank_parts.dart';
import 'package:bilifast/live/room/live_overlays.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rank_support.dart';

void main() {
  final weekly = LiveGuardPage(
    entries: [
      for (var rank = 1; rank <= 6; rank++)
        LiveRankEntry(
          rank: rank,
          user: viewer(100 + rank, name: '舰长$rank', guard: 3, medal: testMedal),
        ),
    ],
    total: 3351,
    topText: '上周TOP1',
    topUser: viewer(99, name: '上周第一', guard: 1),
    hasMore: true,
  );
  final monthly = LiveGuardPage(
    entries: [LiveRankEntry(rank: 1, user: viewer(201, name: '月榜第一', guard: 2))],
    total: 3351,
  );
  final companion = LiveGuardPage(
    entries: [LiveRankEntry(rank: 1, user: viewer(301, name: '陪伴第一', guard: 3))],
  );

  PagedLiveApi api({
    LiveRankPage? rank,
    List<LiveRankPage> moreRank = const [],
    Map<LiveGuardTab, List<LiveGuardPage>> moreGuards = const {},
  }) => PagedLiveApi(
    rankPage: rank ?? LiveRankPage(entries: rankEntries(8), hasMore: false),
    guardPages: {LiveGuardTab.weekly: weekly, LiveGuardTab.monthly: monthly, LiveGuardTab.companion: companion},
    moreRank: moreRank,
    moreGuards: moreGuards,
  );

  Future<RankHarness> open(
    WidgetTester tester,
    PagedLiveApi api, {
    bool loggedIn = true,
    bool landscape = false,
  }) async {
    final services = await rankServices(loggedIn: loggedIn);
    final harness = RankHarness(api: api, loggedIn: loggedIn);
    await pumpRank(tester, services, harness, landscape: landscape);
    return harness;
  }

  Future<void> showGuards(WidgetTester tester) async {
    await tester.tap(byKey('rank-tab-guard'));
    await settle(tester);
  }

  group('portrait (230, 231)', () {
    testWidgets('a sheet over the lower 70% asks 在线榜 and 周榜 once, for the room and its anchor', (tester) async {
      final fake = api();
      await open(tester, fake);
      expect(fake.calls, ['rank $roomId page=1', 'guards $roomId weekly page=1']);
      expect(fake.anchors, [anchorUid, anchorUid]);
      final sheet = tester.getRect(byKey('rank-sheet'));
      expect(sheet.top, moreOrLessEquals(956 * 0.3, epsilon: 0.01));
      expect((sheet.left, sheet.width, sheet.bottom), (0, 440, 956));
      expect(find.text('房间观众'), findsOneWidget);
      expect(find.text('大航海 (3351)'), findsOneWidget, reason: "周榜's total names the tab");
      expect(find.text('在线榜'), findsOneWidget);
      expect(find.text('投喂、点赞、发弹幕均可获得贡献值'), findsOneWidget);
      expect(find.text('贡献值'), findsOneWidget);
    });

    testWidgets('rows: 榜1-3 tags, then numbers; face, name, chips and 贡献值', (tester) async {
      await open(tester, api());
      for (var rank = 1; rank <= 3; rank++) {
        final tag = find.byWidgetPredicate(
          (widget) => widget is Image && (widget.image as AssetImage).assetName.endsWith('rank_tag_$rank.png'),
        );
        expect(tag, findsOneWidget);
      }
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1'), findsNothing, reason: '1-3 are tags');
      final row = byKey('rank-audience-1-1');
      expect(tester.getRect(row).top, moreOrLessEquals(956 * 0.3 + 50 + 56, epsilon: 0.01));
      expect(tester.getSize(row).height, 65);
      expect(find.descendant(of: row, matching: find.text('测试观众1')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('8999')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.byType(LiveWealthChip)), findsOneWidget);
      expect(find.descendant(of: row, matching: find.byType(LiveMedalChip)), findsOneWidget);
      final face = tester.widget<LiveFace>(find.descendant(of: row, matching: find.byType(LiveFace)));
      expect(face.size, 36);
      expect(tester.getRect(find.descendant(of: row, matching: find.byType(LiveFace))).left, 52);
    });

    testWidgets("logged in, the viewer's own row: -, their face, 贡献值 0 and 去投喂", (tester) async {
      await open(tester, api());
      final own = byKey('rank-own');
      expect(own, findsOneWidget);
      expect(find.descendant(of: own, matching: find.text('-')), findsOneWidget);
      expect(find.descendant(of: own, matching: find.text('贡献值 0')), findsOneWidget);
      expect(find.descendant(of: own, matching: find.text('快来投喂吧～')), findsOneWidget);
      expect(find.descendant(of: own, matching: find.text('去投喂')), findsOneWidget);
      final face = tester.widget<LiveFace>(find.descendant(of: own, matching: find.byType(LiveFace)));
      expect(face.url, 'https://i0.hdslb.com/bfs/face/test.jpg', reason: "the account's face");
      expect(tester.getRect(own).bottom, 956);
      expect(tester.getSize(own).height, 1 + 56 + 34);
    });

    testWidgets('the own row takes its rank and score from the answer', (tester) async {
      final own = LiveRankEntry(rank: 12, user: viewer(5), score: 30);
      await open(
        tester,
        api(
          rank: LiveRankPage(entries: rankEntries(3), own: own),
        ),
      );
      final row = byKey('rank-own');
      expect(find.descendant(of: row, matching: find.text('12')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('贡献值 30')), findsOneWidget);
    });

    testWidgets('logged out, no own row', (tester) async {
      await open(tester, api(), loggedIn: false);
      expect(byKey('rank-own'), findsNothing);
      expect(find.text('去投喂'), findsNothing);
      expect(find.text('测试观众1'), findsOneWidget);
    });

    testWidgets('the next 在线榜 page near the end, once; a page that says no more ends it', (tester) async {
      final fake = api(
        rank: LiveRankPage(entries: rankEntries(20), hasMore: true),
        moreRank: [LiveRankPage(entries: rankEntries(20, from: 21), hasMore: false)],
      );
      await open(tester, fake);
      expect(fake.count('rank'), 1, reason: 'the first page fills the list; its end is far');
      await tester.drag(byKey('rank-audience-list'), const Offset(0, -2000));
      await settle(tester);
      expect(fake.count('rank $roomId page=2'), 1);
      await tester.drag(byKey('rank-audience-list'), const Offset(0, -2000));
      await settle(tester);
      expect(find.text('测试观众40'), findsOneWidget);
      expect(fake.count('rank'), 2, reason: 'page 2 said no more');
    });

    testWidgets('a page that adds nobody ends the list, so nothing is asked again', (tester) async {
      final fake = api(
        rank: LiveRankPage(entries: rankEntries(3), hasMore: true),
        moreRank: [LiveRankPage(entries: rankEntries(3), hasMore: true)],
      );
      await open(tester, fake);
      await settle(tester);
      expect(fake.count('rank'), 2, reason: 'a short page leaves its end on screen');
      await tester.drag(byKey('rank-audience-list'), const Offset(0, -400));
      await settle(tester);
      expect(fake.count('rank'), 2);
    });

    testWidgets('the TV while the first page is out; a failure offers 重试, which asks once more', (tester) async {
      final fake = api();
      final hold = fake.holds['rank'] = Completer<void>();
      fake.failures['rank'] = const BiliError.api(code: -1, message: '出错了');
      await open(tester, fake);
      expect(find.byType(LoadingTvState), findsWidgets);
      hold.complete();
      await settle(tester);
      expect(find.text('B 站返回错误 -1：出错了'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      fake.failures.remove('rank');
      fake.holds.remove('rank');
      await tester.tap(find.text('重试'));
      await settle(tester);
      expect(fake.count('rank $roomId page=1'), 2);
      expect(find.text('测试观众1'), findsOneWidget);
    });

    testWidgets("a failed next page shows 重试 under the rows and isn't asked again until pressed", (tester) async {
      final fake = api(
        rank: LiveRankPage(entries: rankEntries(20), hasMore: true),
        moreRank: [LiveRankPage(entries: rankEntries(5, from: 21))],
      );
      fake.failures['rank $roomId page=2'] = const BiliError.api(code: -1, message: '下一页失败');
      await open(tester, fake);
      await tester.drag(byKey('rank-audience-list'), const Offset(0, -2000));
      await settle(tester);
      await tester.drag(byKey('rank-audience-list'), const Offset(0, -400));
      await settle(tester);
      expect(fake.count('rank $roomId page=2'), 1);
      expect(find.text('B 站返回错误 -1：下一页失败'), findsOneWidget);
      fake.failures.clear();
      await tester.tap(find.text('重试'));
      await settle(tester);
      expect(fake.count('rank $roomId page=2'), 2);
      await tester.drag(byKey('rank-audience-list'), const Offset(0, -2000));
      await settle(tester);
      expect(find.text('测试观众25'), findsOneWidget);
    });

    for (final (label, name) in [('贡献值说明', 'ⓘ'), ('贡献值排序', '贡献值 ⇌'), ('去投喂', '去投喂')]) {
      testWidgets('$name toasts 暂未开放', (tester) async {
        final fake = api();
        await open(tester, fake);
        final calls = fake.calls.length;
        await tester.tap(find.bySemanticsLabel(label));
        await tester.pump();
        expect(find.text('暂未开放'), findsOneWidget);
        expect(fake.calls, hasLength(calls));
        await toastGone(tester);
      });
    }

    testWidgets('tapping the room above closes it through the overlays', (tester) async {
      final harness = await open(tester, api());
      await tester.tapAt(const Offset(220, 100));
      await settle(tester);
      expect(harness.overlays.value, LiveOverlay.none);
      expect(byKey('rank-sheet'), findsNothing);
    });

    testWidgets("a tap on the sheet stays on it", (tester) async {
      final harness = await open(tester, api());
      await tester.tapAt(const Offset(300, 380));
      await settle(tester);
      expect(harness.overlays.value, LiveOverlay.rank);
    });

    testWidgets('大航海: the tab, 上周TOP1, the line, italic 1-3 then numbers, medals, the bar', (tester) async {
      await open(tester, api());
      await showGuards(tester);
      for (final name in ['周榜', '月榜', '陪伴榜']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(byKey('rank-top-card'), findsOneWidget);
      expect(find.text('上周TOP1 上周第一', findRichText: true), findsOneWidget);
      expect(find.text('榜单每周更新，统计周大航海亲密度'), findsOneWidget);
      for (var rank = 1; rank <= 3; rank++) {
        final numeral = find.byWidgetPredicate(
          (widget) => widget is Image && (widget.image as AssetImage).assetName.endsWith('rank_guard_$rank.png'),
        );
        expect(numeral, findsOneWidget);
      }
      expect(find.text('舰长1'), findsOneWidget);
      expect(find.descendant(of: byKey('rank-guard-weekly-101'), matching: find.byType(LiveMedalChip)), findsOneWidget);
      expect(find.text('千舰'), findsOneWidget);
      expect(find.text('头号粉丝大航海，等你来上船'), findsOneWidget);
      expect(find.text('立即上船'), findsOneWidget);
      final segment = tester.getRect(byKey('rank-segment-weekly'));
      expect(segment.left, 26);
      expect(segment.height, 25);
      expect(segment.top, moreOrLessEquals(956 * 0.3 + 50 + 47 / 3, epsilon: 0.01));
      final bar = tester.getRect(byKey('rank-board'));
      expect(bar.right, moreOrLessEquals(440 - 43 / 3, epsilon: 0.01));
    });

    testWidgets('each 大航海 tab is asked once, when first shown; 上周TOP1 only where the answer has one', (tester) async {
      final fake = api();
      await open(tester, fake);
      await showGuards(tester);
      expect(fake.count('guards'), 1);
      await tester.tap(byKey('rank-segment-monthly'));
      await settle(tester);
      expect(fake.calls.last, 'guards $roomId monthly page=1');
      expect(find.text('月榜第一'), findsOneWidget);
      expect(byKey('rank-top-card'), findsNothing);
      expect(find.text('榜单每月更新，统计月大航海亲密度'), findsOneWidget);
      await tester.tap(byKey('rank-segment-companion'));
      await settle(tester);
      expect(find.text('陪伴第一'), findsOneWidget);
      await tester.tap(byKey('rank-segment-weekly'));
      await settle(tester);
      await tester.tap(byKey('rank-segment-monthly'));
      await settle(tester);
      await tester.tap(byKey('rank-segment-companion'));
      await settle(tester);
      expect(fake.count('guards $roomId weekly'), 1);
      expect(fake.count('guards $roomId monthly'), 1);
      expect(fake.count('guards $roomId companion'), 1);
      expect(fake.count('rank'), 1);
    });

    testWidgets('a 大航海 tab loads its next page near the end', (tester) async {
      final many = LiveGuardPage(
        entries: [for (var i = 1; i <= 15; i++) LiveRankEntry(rank: i, user: viewer(400 + i, guard: 3))],
        total: 40,
        hasMore: true,
      );
      final fake = PagedLiveApi(
        guardPages: {LiveGuardTab.weekly: many},
        moreGuards: {
          LiveGuardTab.weekly: [
            LiveGuardPage(
              entries: [for (var i = 16; i <= 20; i++) LiveRankEntry(rank: i, user: viewer(400 + i))],
            ),
          ],
        },
      );
      await open(tester, fake);
      await showGuards(tester);
      await tester.drag(byKey('rank-guard-list-weekly'), const Offset(0, -2000));
      await settle(tester);
      expect(fake.count('guards $roomId weekly page=2'), 1);
      expect(find.text('测试观众420'), findsOneWidget);
      expect(find.text('千舰'), findsNothing, reason: '40 ships is no fleet badge');
    });

    testWidgets("立即上船 and the line's ⓘ toast 暂未开放", (tester) async {
      await open(tester, api());
      await showGuards(tester);
      await tester.tap(find.bySemanticsLabel('立即上船'));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      await toastGone(tester);
      await tester.tap(find.bySemanticsLabel('大航海说明'));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('a swipe moves between the two tabs', (tester) async {
      await open(tester, api());
      await tester.fling(byKey('rank-audience-list'), const Offset(-300, 0), 1500);
      await settle(tester, 30);
      expect(tester.getRect(byKey('rank-segment-weekly')).left, 26);
      await tester.fling(byKey('rank-guard-list-weekly'), const Offset(300, 0), 1500);
      await settle(tester, 30);
      expect(tester.getRect(find.text('在线榜')).left, greaterThanOrEqualTo(12));
      expect(tester.getRect(find.text('在线榜')).right, lessThan(100));
    });

    testWidgets('tapping 房间观众 goes back', (tester) async {
      await open(tester, api());
      await showGuards(tester);
      await tester.tap(byKey('rank-tab-audience'));
      await settle(tester);
      expect(tester.getRect(find.text('在线榜')).left, greaterThanOrEqualTo(12));
      expect(tester.getRect(find.text('在线榜')).right, lessThan(100));
    });

    testWidgets("with no anchor known yet, nothing is asked until the room's info names one", (tester) async {
      final fake = api();
      final services = await rankServices();
      final room = TestRoom(
        api: fake,
        entry: const LiveRoomEntry(roomId: roomId),
        loggedIn: () => true,
      );
      final harness = RankHarness(api: fake, room: room);
      await pumpRank(tester, services, harness);
      expect(fake.calls, isEmpty);
      expect(find.byType(LoadingTvState), findsWidgets);
      room.info = const LiveRoomInfo(roomId: roomId, uid: 42, title: '');
      await settle(tester);
      expect(fake.calls, ['rank $roomId page=1', 'guards $roomId weekly page=1']);
      expect(fake.anchors, [42, 42]);
      room.info = const LiveRoomInfo(roomId: roomId, uid: 42, title: '');
      await settle(tester);
      expect(fake.calls, hasLength(2));
    });
  });

  group('landscape (232, 233)', () {
    testWidgets('a 375 pt panel at the right, the whole height, the same content', (tester) async {
      await open(tester, api(), landscape: true);
      final panel = tester.getRect(byKey('rank-sheet'));
      expect((panel.left, panel.top, panel.width, panel.height), (956 - 375, 0, 375, 440));
      expect(find.text('在线榜'), findsOneWidget);
      expect(tester.getRect(byKey('rank-audience-1-1')).top, 50 + 56);
      final own = byKey('rank-own');
      expect(tester.getSize(own).height, 1 + 56 + 21);
      expect(tester.getRect(find.text('去投喂')).right, lessThanOrEqualTo(956 - 43 / 3));
      await showGuards(tester);
      expect(tester.getRect(byKey('rank-segment-weekly')).left, 956 - 375 + 26);
      expect(find.text('立即上船'), findsOneWidget);
    });

    testWidgets('tapping the video at the left closes it', (tester) async {
      final harness = await open(tester, api(), landscape: true);
      await tester.tapAt(const Offset(300, 220));
      await settle(tester);
      expect(harness.overlays.value, LiveOverlay.none);
    });
  });

  test('RankArt names the APK art for 1-3 only', () {
    expect(RankArt.tag(1), 'assets/images/live/rank_tag_1.png');
    expect(RankArt.tag(4), isNull);
    expect(RankArt.guardNumeral(3), 'assets/images/live/rank_guard_3.png');
    expect(RankArt.guardNumeral(0), isNull);
  });
}
