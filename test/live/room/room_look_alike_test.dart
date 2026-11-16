import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/live.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/live/live_badges.dart';
import 'package:bilifast/live/room/live_chat_item.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:bilifast/live/room/live_room_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;
import 'room_support.dart';

const _screen = ValueKey('screen');

/// 207, 221, 224 and 228 as KaiC's iPhone draws them, under the system font. With BILIFAST_SHOTS naming a folder
/// outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  final shots = Platform.environment['BILIFAST_SHOTS'];

  LiveUser viewer(int i, String name, {int wealth = 0, LiveMedal? medal}) =>
      LiveUser(uid: 4000 + i, name: name, wealthLevel: wealth, medal: medal);
  const medal = LiveMedal(name: '演示', level: 21, colorStart: 0xFF2E759E, colorEnd: 0xFF2E759E);

  List<LiveChatItem> chat() => [
    const LiveChatNotice(LiveRoomModel.systemNotice),
    LiveChatDanmaku(
      LiveChatMessage(
        id: 'a',
        user: viewer(1, '演示鞋', wealth: 4, medal: medal),
        text: '演示文字 hhhhhhhhhhhh',
        time: roomNow,
      ),
    ),
    LiveChatInteraction(LiveInteraction.entered, viewer(2, 'Demo5504')),
    LiveChatRoomCard(
      title: '演示大赛 AQ vs LGD',
      description: 'valorant 解说 / 多赛季赋能 / 中奖在天选时刻填写 ZFB（不要微信）/ 日常 rank 比赛解说看动态班表',
      liveTime: roomNow.subtract(const Duration(hours: 5, minutes: 12, seconds: 37)),
    ),
    LiveChatDanmaku(
      LiveChatMessage(
        id: 'b',
        user: viewer(3, 'D1w_1', wealth: 6, medal: medal),
        text: '8k爆了',
        time: roomNow,
      ),
    ),
    LiveChatDanmaku(LiveChatMessage(id: 'c', user: viewer(4, '演示仓库'), text: '又欠你演示没沟通了', time: roomNow)),
  ];

  Future<TestRoomModel> show(WidgetTester tester, {List<LiveSuperChat> superChats = const []}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;
    final services = await roomServices();
    final model = TestRoomModel(
      info: const LiveRoomInfo(
        roomId: 1001,
        uid: 2001,
        title: '演示大赛',
        anchorName: '夜莲 Annbbers',
        verify: LiveVerify.personal,
        rankChips: ['热门榜', '网游人气第 28'],
      ),
    );
    model.chatList.value = chat();
    model.superChatList.value = superChats;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        navigatorKey: navigator,
        navigatorObservers: [pageRoutes],
        builder: (context, page) => RepaintBoundary(
          key: _screen,
          child: AppScope(services: services, child: page!),
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => LiveRoomPage(
            entry: roomEntry,
            createModel: (_, _) => model,
            createController: (services, room) => TestPlayerController(room: room, services: services),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.runAsync(() async {
      final context = tester.element(find.byType(LiveRoomPage));
      for (final asset in [
        'assets/images/live/room_gift.png',
        'assets/images/live/room_more_boost.png',
        'assets/images/live/room_share_qzone.png',
        'assets/images/home/hot_share_wechat.png',
        'assets/images/home/hot_share_moments.png',
        'assets/images/home/hot_share_qq.png',
        for (final name in ['pip', 'player', 'danmaku', 'quality', 'effects']) 'assets/images/live/room_more_$name.png',
      ]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await settle(tester);
    return model;
  }

  Future<void> save(WidgetTester tester, String name) async {
    if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/$name-ours.png');
  }

  testWidgets('207: the header, the chat and the bottom bar', (tester) async {
    await show(tester);
    await save(tester, 'live-207');
    expect(find.byKey(const ValueKey('live-chat-room-card')), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('221: the more sheet draws every icon', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('live-bar-more')));
    await settle(tester);
    await save(tester, 'live-221');
    final slot = find.byKey(const ValueKey('live-more-spending'));
    final paint = find.descendant(of: slot, matching: find.byType(CustomPaint)).last;
    expect(tester.getSize(paint), const Size.square(LiveRoomTheme.lineIcon));
  });

  testWidgets('228: the 醒目留言 card', (tester) async {
    await show(tester, superChats: [roomSuperChat(2, price: 500), roomSuperChat(1)]);
    await tester.tap(find.byKey(const ValueKey('live-sc-pill-2')));
    await settle(tester);
    await save(tester, 'live-228');
    final price = tester.getTopLeft(find.byKey(const ValueKey('live-sc-card-price')));
    expect(price.dx, closeTo(LiveRoomTheme.cardNameX, 0.01));
  });

  testWidgets('荣耀等级 chips on the chat and on a light sheet', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;
    const levels = [4, 12, 17, 25, 29, 31, 36];
    await tester.pumpWidget(
      RepaintBoundary(
        key: _screen,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              for (final light in [false, true])
                ColoredBox(
                  color: light ? const Color(0xFFFFFFFF) : LiveRoomTheme.page,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        for (final level in levels) ...[
                          LiveWealthChip(level: level, onDark: !light),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await save(tester, 'live-wealth');
    expect(LiveWealthChip.fill(4, onDark: true), isNot(LiveWealthChip.fill(31, onDark: true)));
  });
}
