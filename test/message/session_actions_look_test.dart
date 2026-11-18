import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../dynamic/follow_tab/follow_dark_test.dart' show pixelAt;
import '../dynamic/follow_tab/follow_fixtures.dart';
import '../support/look_alike.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

ChatSession _row(
  int id,
  String name,
  String last,
  DateTime time, {
  bool vipPink = false,
  bool bigVip = false,
  DynamicVerify verify = DynamicVerify.none,
}) => ChatSession(
  talkerId: id,
  name: name,
  face: '',
  lastText: last,
  time: time,
  vipPink: vipPink,
  bigVip: bigVip,
  verify: verify,
);

ChatSession _box(NoticeBox box, String last, DateTime time) =>
    ChatSession(talkerId: 9000 + box.index, box: box, name: box.label, face: '', lastText: last, time: time);

// Made-up rows shaped like 259's and 261's: the same dates, kinds of name and lengths of text.
final _recent = [
  _box(NoticeBox.service, '演示收藏集狂欢月第二周福利已送达，演示新增周边加码领取', DateTime(2026, 11, 13, 9)),
  _box(NoticeBox.community, '登录操作通知', DateTime(2026, 11, 12, 10)),
  _row(1, '演示小羊饱饱', '[自动回复] 演示关注 加投稿哦', DateTime(2026, 11, 12, 8)),
  _row(2, '演示dada', '[自动回复] 哈哈哈哈，恭喜你发现了宝藏噢！[tv_点赞]', DateTime(2026, 10, 21), vipPink: true),
  _row(3, '演示阿库玛', '[自动回复] 感谢你的关注，有什么演示欢迎私信投稿哦', DateTime(2026, 10, 8), vipPink: true, bigVip: true),
  _row(4, '演示小瑶TnT', '[自动回复] 感谢关注，爱你喵', DateTime(2026, 10, 4)),
  _row(5, '演示小姐姐', '第二波演示头像编号将于本周五晚20:00发放喵！ 记得来', DateTime(2026, 9, 17)),
  _row(6, '演示的lansir', '[自动回复] 非非非非常感谢你的关注，有什么想看的可以', DateTime(2026, 8, 13), vipPink: true),
  _row(7, '演示哔哩智能机', '登录操作通知', DateTime(2026, 7, 21), verify: DynamicVerify.personal),
  _row(8, '演示S', '演示消息', DateTime(2026, 6, 27), vipPink: true),
];

final _old = [
  _row(11, 'void演示殿下', '[自动回复] 谢谢关注！送你一张壁纸[tv_害羞] 链接在这里', DateTime(2023, 11, 22)),
  _row(12, '演示优俊少女', '全平台公测开启通知', DateTime(2023, 8, 30), vipPink: true),
  _row(13, '演示教主', '[自动回复] 感谢关注哇！你也想成为我的眷属嘛 演示', DateTime(2023, 8, 12), vipPink: true),
  _row(14, '画粉演示', '[自动回复] 好耶！！新的饲养员！！[眠眠兔_喜欢][眠眠兔]', DateTime(2023, 6, 21)),
  _row(15, '演示会员购', '魔晶过期提醒', DateTime(2023, 4, 27), vipPink: true),
  _row(16, '你的演示月', '[自动回复] 感谢关注 原神全收集攻略目录：cv13698000', DateTime(2023, 1, 18), vipPink: true),
  _row(17, '演示创作中心', '(゜-゜)つロYou have a benefit! Come and have a look', DateTime(2022, 6, 15), vipPink: true),
  _row(18, '演示某人', '[自动回复] 演示会越做越好！ 绝不辜负你的关注！！！', DateTime(2022, 4, 10), vipPink: true),
  _row(19, '体育课演示', '[图片]', DateTime(2021, 12, 16)),
  _row(20, '晚星演示', '[自动回复] 感谢关注，欢迎加入演示交流群： 1群：', DateTime(2021, 9, 6), vipPink: true),
];

/// 消息's row actions as KaiC's iPhone draws them, under the system font, against 259-262 (px / 3). The references
/// wear a 装扮 and were taken 3 pt down the list; the shots here keep the stock header and bar and scroll as far. With
/// BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<FakeMessageApi> openMessages(WidgetTester tester, List<ChatSession> sessions) async {
    final api = FakeMessageApi(sessionList: sessions, pageSize: 30);
    await showShell(
      tester,
      api: FakeDynamicApi(posts: posts(4), upList: faces),
      phone: true,
      messageApi: api,
    );
    await settle(tester, 20);
    await tester.runAsync(loadIconFonts);
    await tester.tap(_key('home-tab-${HomeTab.messages.name}'));
    await settle(tester, 30);
    // The asset glyphs and default faces decode off the test's clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await settle(tester);
    return api;
  }

  ScrollPosition list(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: _key('message-list'), matching: find.byType(Scrollable)).first)
      .position;

  Future<void> save(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(shellScreen), '$shots/$name-ours.png');
  }

  void near(Rect actual, Rect expected, {double within = 0.01}) {
    for (final (a, b) in [
      (actual.left, expected.left),
      (actual.top, expected.top),
      (actual.right, expected.right),
      (actual.bottom, expected.bottom),
    ]) {
      expect(a, closeTo(b, within), reason: '$actual against $expected');
    }
  }

  testWidgets('259: the third row swiped open, 置顶 and 删除 over px 876-1098 and 1098-1320, 1040-1253', (tester) async {
    await openMessages(tester, _recent);
    list(tester).jumpTo(3);
    await settle(tester);
    await tester.drag(_key('message-session-1'), const Offset(-200, 0));
    await settle(tester);
    near(tester.getRect(_key('message-session-top-1')), const Rect.fromLTRB(876 / 3, 1040 / 3, 1098 / 3, 1253 / 3));
    near(tester.getRect(_key('message-session-delete-1')), const Rect.fromLTRB(1098 / 3, 1040 / 3, 440, 1253 / 3));
    expect(await pixelAt(tester, const Offset(300, 350)), const Color(0xFFBBBBC1));
    expect(await pixelAt(tester, const Offset(430, 350)), const Color(0xFFFC2125));
    await save(tester, '259-message-row-swipe-actions');
  });

  testWidgets('260: 删除\'s alert over the open row', (tester) async {
    await openMessages(tester, _recent);
    list(tester).jumpTo(3);
    await settle(tester);
    await tester.drag(_key('message-session-3'), const Offset(-200, 0));
    await settle(tester);
    await tester.tap(_key('message-session-delete-3'));
    await settle(tester, 20);
    // 260's box, as 211's: px 240-1080 across, 1270-1683 down, centred between the status bar and the home indicator
    // half a pixel higher than 260.
    near(tester.getRect(_key('message-delete')), const Rect.fromLTRB(80, 1270 / 3, 360, 1683 / 3), within: 0.17);
    await save(tester, '260-message-delete-confirm');
  });

  testWidgets('262: the pinned row first on #F6F7F8 across px 614-827', (tester) async {
    await openMessages(tester, _recent);
    await tester.drag(_key('message-session-1'), const Offset(-200, 0));
    await settle(tester);
    await tester.tap(_key('message-session-top-1'));
    await settle(tester);
    list(tester).jumpTo(3);
    await settle(tester);
    near(tester.getRect(_key('message-session-1')), const Rect.fromLTRB(0, 614 / 3, 440, 827 / 3));
    expect(await pixelAt(tester, const Offset(5, 210)), const Color(0xFFF6F7F8));
    expect(await pixelAt(tester, const Offset(5, 280)), const Color(0xFFFFFFFF));
    await save(tester, '262-message-pinned-row');
  });

  testWidgets('261: the list\'s end, its last row ending px 2451 and the line\'s ink centred 841.67 down', (
    tester,
  ) async {
    await openMessages(tester, [..._recent, ..._old]);
    final position = list(tester);
    position.jumpTo(position.maxScrollExtent);
    await settle(tester);
    expect(tester.getRect(_key('message-session-20')).bottom, closeTo(2451 / 3, 0.01));
    final end = tester.getRect(find.text('我可是有底线的_(:3ゝ∠)_'));
    expect(end.center.dx, closeTo(220, 0.5));
    expect(end.center.dy, closeTo(841.67 - 1 / 3, 0.01));
    await save(tester, '261-message-list-end');
  });
}
