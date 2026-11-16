import 'package:bilifast/live/room/live_room_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'room_support.dart';

void main() {
  Finder key(String name) => find.byKey(ValueKey(name));

  Future<TestRoomModel> open(WidgetTester tester, {bool withSuperChats = true}) async {
    final model = TestRoomModel(info: roomInfo());
    if (withSuperChats) model.superChatList.value = [roomSuperChat(2, price: 500), roomSuperChat(1)];
    await pumpRoom(tester, await roomServices(), model: model);
    return model;
  }

  testWidgets('no 醒目留言, no strip: the chat starts under the box', (tester) async {
    await open(tester, withSuperChats: false);
    expect(key('live-sc-strip'), findsNothing);
    expect(tester.getRect(key('live-chat')).top, moreOrLessEquals(1342 / 3));
  });

  testWidgets('the strip under the box, newest first, the chat under it', (tester) async {
    await open(tester);
    final strip = tester.getRect(key('live-sc-strip'));
    expect(strip.top, moreOrLessEquals(1342 / 3 + LiveRoomTheme.stripGap));
    expect(strip.height, moreOrLessEquals(LiveRoomTheme.stripHeight));
    final newest = tester.getRect(key('live-sc-pill-2'));
    final older = tester.getRect(key('live-sc-pill-1'));
    expect(newest.left, LiveRoomTheme.chatLeft);
    expect(older.left - newest.right, moreOrLessEquals(LiveRoomTheme.pillGap));
    expect(find.text('5000'), findsOneWidget);
    expect(tester.getRect(key('live-chat')).top, moreOrLessEquals(strip.bottom));
  });

  testWidgets("a pill opens its card over the dimmed page; ⋮ opens 229, whose rows toast and 取消 closes", (
    tester,
  ) async {
    await open(tester);
    await tester.tap(key('live-sc-pill-2'));
    await settle(tester);
    expect(key('live-sc-dim'), findsOneWidget);
    final card = tester.getRect(key('live-sc-card-2'));
    expect(card.left, LiveRoomTheme.cardSide);
    expect(card.right, 440 - LiveRoomTheme.cardSide);
    expect(card.top, moreOrLessEquals(tester.getRect(key('live-sc-strip')).bottom + LiveRoomTheme.cardBelowStrip));
    expect(find.descendant(of: key('live-sc-card-2'), matching: find.text('5000 电池')), findsOneWidget);
    expect(find.descendant(of: key('live-sc-card-2'), matching: find.text('醒目留言2')), findsOneWidget);
    expect(key('live-face-guard-2'), findsWidgets);

    await tester.tap(key('live-sc-card-more'));
    await settle(tester);
    expect(key('live-sc-actions'), findsOneWidget);
    expect(find.text('管理本条醒目留言'), findsOneWidget);
    for (final row in ['live-sc-manage', 'live-sc-report']) {
      await tester.tap(key(row));
      await settle(tester);
      expect(find.text('暂未开放'), findsOneWidget, reason: row);
      await toastGone(tester);
    }
    await tester.tap(key('live-sc-cancel'));
    await settle(tester);
    expect(key('live-sc-actions'), findsNothing);
    expect(key('live-sc-card-2'), findsOneWidget);

    await tester.tapAt(const Offset(220, 900));
    await settle(tester);
    expect(key('live-sc-card-2'), findsNothing);
    expect(key('live-sc-dim'), findsNothing);
  });

  testWidgets('back closes 229 first, then the card, then leaves', (tester) async {
    await open(tester);
    await tester.tap(key('live-sc-pill-1'));
    await settle(tester);
    await tester.tap(key('live-sc-card-more'));
    await settle(tester);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(key('live-sc-actions'), findsNothing);
    expect(key('live-sc-card-1'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(key('live-sc-card-1'), findsNothing);
    expect(find.byType(LiveRoomPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(LiveRoomPage), findsNothing);
  });

  testWidgets('a card whose 醒目留言 leaves the strip closes', (tester) async {
    final model = await open(tester);
    await tester.tap(key('live-sc-pill-1'));
    await settle(tester);
    model.superChatList.value = [roomSuperChat(2, price: 500)];
    await settle(tester);
    expect(key('live-sc-card-1'), findsNothing);
    expect(key('live-sc-dim'), findsNothing);
  });
}
