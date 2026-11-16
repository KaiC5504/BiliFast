import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/zoom_back_route.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/following/live_following_page.dart';
import 'package:bilifast/live/room/live_room_page.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home/live/live_support.dart';

void main() {
  final list = find.byKey(const ValueKey('live-following-list'));

  /// 206 pushed over a page, as 查看全部 opens it.
  Future<void> show(WidgetTester tester, FakeLiveApi api) async {
    final services = await liveServices(api: api);
    await pumpLive(
      tester,
      services,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const ValueKey('open'),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiveFollowingPage(api: api))),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await settle(tester, 20);
  }

  FakeLiveApi api({int total = 3, List<LiveCardPage>? pages}) => FakeLiveApi(
    followingPages: pages ?? [LiveCardPage(page: 1, cards: liveCards(3, from: 70), total: total)],
  );

  testWidgets('the title counts the rooms live; two to a row, 5.33 in, straight under the bar', (tester) async {
    final calls = api();
    final hold = calls.holds['following'] = Completer<void>();
    await show(tester, calls);
    expect(calls.calls, ['following page=1']);
    expect(find.byType(LoadingTvState), findsOneWidget);
    hold.complete();
    calls.holds.clear();
    await settle(tester);

    expect(find.text('3人正在直播'), findsOneWidget);
    final bar = tester.getRect(find.byKey(const ValueKey('live-following-bar')));
    final first = tester.getRect(find.byKey(const ValueKey('live-following-card-9070')));
    final second = tester.getRect(find.byKey(const ValueKey('live-following-card-9071')));
    final third = tester.getRect(find.byKey(const ValueKey('live-following-card-9072')));
    expect(first.top, moreOrLessEquals(bar.bottom));
    expect(first.left, moreOrLessEquals(LiveTabTheme.followingSide));
    expect(first.width, moreOrLessEquals(207.67, epsilon: 0.01));
    expect(second.top, first.top);
    expect(second.right, moreOrLessEquals(440 - LiveTabTheme.followingSide));
    expect(third.top, greaterThan(first.bottom));
    expect(first.height, moreOrLessEquals(129 + 176 / 3, epsilon: 0.2));
    expect(find.text('测试主播70'), findsOneWidget);
    expect(find.text('测试直播间 70'), findsOneWidget);
    expect(find.text('测试分区'), findsNWidgets(3), reason: 'the area on each cover');
  });

  testWidgets('全…注 says 暂未开放; ‹ goes back', (tester) async {
    await show(tester, api());
    await tester.tap(find.byKey(const ValueKey('live-following-filter')));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await toastGone(tester);
    await tester.tap(find.byKey(const ValueKey('live-following-back')));
    await settle(tester, 20);
    expect(find.byType(LiveFollowingPage), findsNothing);
  });

  testWidgets('a room opens zooming from its card', (tester) async {
    await show(tester, api());
    await tester.tap(find.byKey(const ValueKey('live-following-card-9071')));
    await settle(tester, 10);
    expect(tester.widget<LiveRoomPage>(find.byType(LiveRoomPage)).entry.roomId, 9071);
    expect(ModalRoute.of(tester.element(find.byType(LiveRoomPage))), isA<ZoomBackPageRoute<void>>());
  });

  testWidgets('pulled, page 1 again; near the end the next page once, then the end', (tester) async {
    final calls = api(
      pages: [
        LiveCardPage(page: 1, cards: liveCards(20, from: 100), total: 30, hasMore: true),
        LiveCardPage(page: 2, cards: liveCards(10, from: 120), hasMore: true),
      ],
    );
    await show(tester, calls);
    expect(find.text('30人正在直播'), findsOneWidget);

    final hold = calls.holds['following page=2'] = Completer<void>();
    await tester.drag(list, const Offset(0, -2000));
    await settle(tester);
    expect(calls.calls, ['following page=1', 'following page=2']);
    expect(find.byKey(const ValueKey('live-following-more')), findsOneWidget);
    hold.complete();
    await settle(tester);
    await tester.drag(list, const Offset(0, -4000));
    await settle(tester);
    expect(calls.calls, ['following page=1', 'following page=2', 'following page=3']);
    expect(find.byKey(const ValueKey('live-following-end')), findsOneWidget);

    await tester.drag(list, const Offset(0, 6000));
    await settle(tester);
    final gesture = await tester.startGesture(tester.getTopLeft(list) + const Offset(220, 300));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester, 20);
    expect(calls.calls.last, 'following page=1');
    expect(calls.calls.length, 4);
  });

  testWidgets('nobody live says so', (tester) async {
    await show(tester, api(pages: const []));
    expect(find.byKey(const ValueKey('live-following-empty')), findsOneWidget);
    expect(find.text('0人正在直播'), findsOneWidget);
  });

  testWidgets('a failure says why with 重试, which asks again', (tester) async {
    final failing = api();
    failing.failures['following'] = Exception('offline');
    await show(tester, failing);
    expect(find.byKey(const ValueKey('live-following-error')), findsOneWidget);
    failing.failures.clear();
    await tester.tap(find.byKey(const ValueKey('live-following-retry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('live-following-card-9070')), findsOneWidget);
  });
}
