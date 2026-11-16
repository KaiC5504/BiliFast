import 'package:bili_core/api.dart';
import 'package:bili_core/live.dart';
import 'package:bilifast/live/room/live_chat_item.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'room_support.dart';

void main() {
  Finder key(String name) => find.byKey(ValueKey(name));

  Future<TestRoomModel> open(WidgetTester tester, List<LiveChatItem> chat) async {
    final model = TestRoomModel(info: roomInfo());
    model.chatList.value = chat;
    await pumpRoom(tester, await roomServices(), model: model);
    return model;
  }

  String plain(WidgetTester tester, Finder finder) => tester.widget<Text>(finder).textSpan!.toPlainText();

  testWidgets('系统提示, the room card with its live time ticking, and the pink tip', (tester) async {
    await open(tester, [
      const LiveChatNotice('系统提示：测试'),
      LiveChatRoomCard(
        title: '测试比赛 A vs B',
        description: '测试公告',
        liveTime: roomNow.subtract(const Duration(hours: 5, minutes: 12, seconds: 37)),
      ),
      const LiveChatTip('试试双击点赞，让主播被更多人看到吧～'),
    ]);
    expect(find.text('系统提示：测试'), findsOneWidget);
    expect(find.text('测试比赛 A vs B'), findsOneWidget);
    expect(find.text('测试公告'), findsOneWidget);
    expect(find.text('05:12:37'), findsOneWidget);
    final tip = tester.widget<Text>(key('live-chat-tip'));
    expect(tip.style!.color, LiveRoomTheme.tipInk);
  });

  testWidgets('a danmaku: 荣耀 and the medal, the name and colon in light blue, the words in white', (tester) async {
    const medal = LiveMedal(name: '测试', level: 21, colorStart: 0xFF2E759E, colorEnd: 0xFF2E759E);
    await open(tester, [
      roomDanmaku(
        1,
        user: roomUser(1, wealth: 4, medal: medal),
        text: '你好',
      ),
    ]);
    final row = key('live-chat-danmaku-m1');
    expect(plain(tester, row), contains('观众1: 你好'));
    expect(find.descendant(of: row, matching: key('live-wealth')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('4')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('21')), findsOneWidget);
    final name = (tester.widget<Text>(row).textSpan! as TextSpan).children!.whereType<TextSpan>().first;
    expect(name.text, '观众1: ');
    expect(name.style!.color, LiveRoomTheme.nameBlue);
    final capsule = tester.getRect(find.ancestor(of: row, matching: find.byType(Container)).first);
    expect(capsule.left, LiveRoomTheme.chatLeft);
    expect(capsule.height, moreOrLessEquals(LiveRoomTheme.rowMinHeight));
  });

  testWidgets("a guard's medal carries its anchor; a name colour of its own is kept", (tester) async {
    const medal = LiveMedal(name: '测试', level: 21, guardLevel: 3);
    await open(tester, [roomDanmaku(2, user: roomUser(2, medal: medal, nameColor: 0xFFFF6699))]);
    expect(key('live-medal-guard'), findsOneWidget);
    final name = (tester.widget<Text>(key('live-chat-danmaku-m2')).textSpan! as TextSpan).children!
        .whereType<TextSpan>()
        .first;
    expect(name.style!.color, const Color(0xFFFF6699));
  });

  testWidgets('inline emotes draw as pictures in the words; a whole-message emote as one picture', (tester) async {
    const doge = LiveEmote(text: '[doge]', url: '');
    await open(tester, [
      roomDanmaku(3, text: '好[doge]啊', emotes: const {'[doge]': doge}),
      roomDanmaku(
        4,
        text: '赞',
        big: const LiveEmote(text: '赞', url: '', width: 120, height: 60),
      ),
    ]);
    expect(plain(tester, key('live-chat-danmaku-m3')), isNot(contains('[doge]')));
    final big = tester.getSize(key('live-chat-big-emote'));
    expect(big, const Size(LiveRoomTheme.emoteBig * 2, LiveRoomTheme.emoteBig));
  });

  testWidgets('interactions: 进入直播间, 关注了主播, 分享了直播间, 为主播点赞了', (tester) async {
    await open(tester, [
      for (final (i, kind) in LiveInteraction.values.indexed) LiveChatInteraction(kind, roomUser(10 + i)),
    ]);
    expect(plain(tester, key('live-chat-interaction-entered')), contains('观众10 进入直播间'));
    expect(plain(tester, key('live-chat-interaction-followed')), contains('观众11 关注了主播'));
    expect(plain(tester, key('live-chat-interaction-shared')), contains('观众12 分享了直播间'));
    expect(plain(tester, key('live-chat-interaction-liked')), contains('观众13 为主播点赞了'));
  });

  testWidgets('a 醒目留言 row: the name and its 电池 on the header band, the message under it', (tester) async {
    await open(tester, [LiveChatSuperChat(roomSuperChat(7, price: 2))]);
    final row = key('live-chat-sc-7');
    expect(find.descendant(of: row, matching: find.text('观众7')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('20 电池')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('醒目留言7')), findsOneWidget);
    expect(
      tester.getRect(find.descendant(of: row, matching: find.text('20 电池'))).right,
      lessThanOrEqualTo(tester.getRect(row).right - LiveRoomTheme.scRowPriceRight + 1),
    );
  });

  testWidgets('the newest row sits on the chat\'s bottom; a few rows stay down there', (tester) async {
    await open(tester, [roomDanmaku(1), roomDanmaku(2)]);
    final chat = tester.getRect(key('live-chat'));
    final last = tester.getRect(find.ancestor(of: key('live-chat-danmaku-m2'), matching: find.byType(Container)).first);
    expect(last.bottom, moreOrLessEquals(chat.bottom));
    final first = tester.getRect(
      find.ancestor(of: key('live-chat-danmaku-m1'), matching: find.byType(Container)).first,
    );
    expect(last.top - first.bottom, moreOrLessEquals(LiveRoomTheme.rowGap));
  });

  testWidgets('stuck to the bottom as rows arrive; scrolled up it stays, and back down it sticks again', (
    tester,
  ) async {
    final model = await open(tester, [for (var i = 0; i < 40; i++) roomDanmaku(i)]);
    expect(key('live-chat-danmaku-m39'), findsOneWidget);

    model.chatList.value = [...model.chatList.value, roomDanmaku(40)];
    await settle(tester);
    expect(key('live-chat-danmaku-m40'), findsOneWidget);
    final chat = tester.getRect(key('live-chat'));
    expect(
      tester.getRect(find.ancestor(of: key('live-chat-danmaku-m40'), matching: find.byType(Container)).first).bottom,
      moreOrLessEquals(chat.bottom),
    );

    await tester.drag(key('live-chat'), const Offset(0, 200));
    await settle(tester);
    final held = tester.getRect(key('live-chat-danmaku-m30'));
    model.chatList.value = [...model.chatList.value, roomDanmaku(41)];
    await settle(tester);
    expect(key('live-chat-danmaku-m41'), findsNothing);
    expect(tester.getRect(key('live-chat-danmaku-m30')), held);

    await tester.drag(key('live-chat'), const Offset(0, -600));
    await settle(tester);
    expect(key('live-chat-danmaku-m41'), findsOneWidget);
    model.chatList.value = [...model.chatList.value, roomDanmaku(42)];
    await settle(tester);
    expect(key('live-chat-danmaku-m42'), findsOneWidget);
  });
}
