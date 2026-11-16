import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import 'chat_support.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

final _day1 = DateTime(2025, 11, 26, 21, 51);
final _day2 = DateTime(2025, 11, 28, 14, 30);

// Made-up messages shaped like 202's: the same scripts, lengths and minutes.
final _chat = [
  tip(1, '对方主动回复或关注你前，最多发送1条消息', at: _day1),
  text(
    2,
    '你好，演示演示演示演示演示的演示\n演示演示演示演示演示演示。演示演\n演示演示演示，演示演示演示演示演\n演，演示演示演示。演示演示的',
    sender: selfMid,
    at: _day1.add(const Duration(minutes: 3)),
  ),
  text(3, '演示演示演示，演示。', at: _day2),
  text(4, '演示演示演示演示演示演示演示演，示演示演示演示', at: _day2),
  text(5, '演示演', at: _day2.add(const Duration(minutes: 1))),
  text(6, '好，演示', sender: selfMid, at: _day2.add(const Duration(hours: 2, minutes: 2))),
];

final _cards = [
  for (final (seqno, minute) in [(1, 0), (2, 0), (3, 0)])
    notice(
      seqno,
      title: '收到个性装扮演示成功通知',
      body: '亲爱的演示小伙伴，恭喜你获得演示演示演示演示装扮！快去我的个性装扮查看吧~更多精美个性装扮待您解锁，速戳查看>>',
      fields: const [(title: '有效期', detail: '永久有效')],
      links: const [(text: '立即查看', uri: 'bilibili://garb/demo'), (text: '更多个性装扮', uri: 'bilibili://garb')],
      at: DateTime(2026, 11, 1, 12, minute),
    ),
  text(
    4,
    'B站演示收藏集狂欢月开启，免费福利券待领取！领取请戳>>https://www.example.com/a',
    sender: 844424930131966,
    at: DateTime(2026, 11, 6, 22),
  ),
  text(
    5,
    '收藏集演示月第二周福利已送达，DEMO演示周边加码，领取>>【https://www.example.com/b】',
    sender: 844424930131966,
    at: DateTime(2026, 11, 13, 20),
  ),
];

/// A chat and a notice box as KaiC's iPhone draws them, under the system font, against 202, 200 and 219 (px / 3).
/// With BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<ChatHarness> show(WidgetTester tester, FakeMessageApi api, ChatSession session) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    final harness = await chatHarness(api);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    await pumpChatApp(tester, harness, ChatLauncher(harness: harness, session: session), sized: false);
    await tester.tap(byKey('open-chat'));
    await settle(tester, 20);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    return harness;
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  testWidgets('202: the bar, time lines, both sides\' bubbles and the composer', (tester) async {
    await show(tester, FakeMessageApi(selfMid: selfMid, chats: {777: _chat}), person(name: '演示演示在开牛高达'));
    await shoot(tester, '202-chat-ours');

    expect(tester.getRect(byKey('chat-settings-bar')), const Rect.fromLTRB(12, 111, 428, 157));
    expect(tester.getRect(byKey('chat-composer')), const Rect.fromLTRB(0, 870, 440, 922));
    // Yours: four lines from 277 to 369, 11 pt from your face.
    final yours = tester.getRect(byKey('chat-bubble-2'));
    expect(yours.top, closeTo(277, 0.5));
    expect(yours.bottom, closeTo(369, 0.5));
    expect(yours.right, 377);
    // Theirs: the second reply's row 15 under the first's face, at 478.33.
    expect(tester.getRect(byKey('chat-bubble-4')).top, closeTo(478.33, 0.5));
  });

  testWidgets('203: no bar for a person followed, an auto reply and a tip', (tester) async {
    final api = FakeMessageApi(
      selfMid: selfMid,
      chats: {
        777: [
          text(1, '演示关注\n演示投稿', autoReply: true, at: DateTime(2026, 11, 12, 15, 34)),
          tip(2, '对方主动回复或关注你前，最多发送1条消息', at: DateTime(2026, 11, 12, 18, 5)),
        ],
      },
      chatSettingsOf: {777: const ChatSettings(following: true)},
    );
    await show(tester, api, person(name: '演示演示'));
    await shoot(tester, '203-chat-auto-reply-ours');
  });

  testWidgets('219: the emote panel under the composer', (tester) async {
    await show(tester, FakeMessageApi(selfMid: selfMid, chats: {777: _chat}), person(name: '演示演示'));
    await tester.tap(byKey('chat-emotes'));
    await settle(tester);
    // The keyboard glyph is an asset, decoded off the test's clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    await shoot(tester, '219-chat-emotes-ours');

    expect(tester.getRect(byKey('chat-composer')).top, closeTo(956 - MessageChatTheme.emotePanel - 52, 0.01));
  });

  testWidgets('200: notice cards and a box\'s bubbles with 网页链接', (tester) async {
    await show(
      tester,
      FakeMessageApi(selfMid: selfMid, chats: {844424930131966: _cards}),
      boxSession(NoticeBox.service),
    );
    await shoot(tester, '200-notices-ours');

    // A card of two body lines, a field and two links, 16 pt from the next.
    final second = tester.getRect(byKey('chat-card-2'));
    final third = tester.getRect(byKey('chat-card-3'));
    expect(second.left, 20);
    expect(second.right, 420);
    expect(second.height, closeTo(200.67, 0.5));
    expect(third.top - second.bottom, closeTo(16, 0.01));
  });
}
