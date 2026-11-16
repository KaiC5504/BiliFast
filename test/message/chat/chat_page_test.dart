import 'dart:async';

import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/comments/emote_panel.dart';
import 'package:bilifast/message/chat/chat_glyphs.dart';
import 'package:bilifast/message/chat/chat_page.dart';
import 'package:bilifast/message/chat/chat_rows.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/message_dates.dart';
import 'package:bilifast/message/notice_box_icon.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_support.dart';

Color? _fill(WidgetTester tester, Finder bubble) {
  final box = tester.widget<DecoratedBox>(find.descendant(of: bubble, matching: find.byType(DecoratedBox)).first);
  return (box.decoration as BoxDecoration).color;
}

void main() {
  group('the bar (202)', () {
    testWidgets('不接受推送 turns the push off through setChatPush and reads 接受推送', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [text(1, '你好')],
        },
      );
      await openChat(tester, api, person());

      expect(byKey('chat-settings-bar'), findsOneWidget);
      expect(find.text('不接受推送'), findsOneWidget);
      expect(find.text('通知正常接收'), findsOneWidget);
      await tester.tap(byKey('chat-push'));
      await settle(tester);

      expect(api.pushes, [(talkerId: 777, on: false)]);
      expect(find.text('接受推送'), findsOneWidget);
      await tester.tap(byKey('chat-push'));
      await settle(tester);
      expect(api.pushes.last, (talkerId: 777, on: true));
      expect(find.text('不接受推送'), findsOneWidget);
    });

    testWidgets('a push switch with no known call toasts 暂未开放', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid)..failures['setChatPush'] = UnsupportedError('no call');
      await openChat(tester, api, person());

      await tester.tap(byKey('chat-push'));
      await settle(tester);
      expect(find.text('暂未开放'), findsOneWidget);
      expect(find.text('不接受推送'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('加关注 follows, reads 已关注 and tells the other pages', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      final harness = await openChat(tester, api, person());

      await tester.tap(byKey('chat-follow'));
      await settle(tester);

      expect(api.follows, [(mid: 777, on: true)]);
      expect(find.text('已关注'), findsOneWidget);
      expect(find.text('加关注'), findsNothing);
      expect(harness.services.follows.following(777), isTrue);
      // 已关注 is no button.
      await tester.tap(byKey('chat-follow'));
      await settle(tester);
      expect(api.follows, hasLength(1));
    });

    testWidgets('a failed 加关注 toasts the reason and keeps 加关注', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid)
        ..failures['follow'] = const BiliError.api(code: 22009, message: '关注已达上限');
      await openChat(tester, api, person());

      await tester.tap(byKey('chat-follow'));
      await settle(tester);
      expect(find.text('关注已达上限'), findsOneWidget);
      expect(find.text('加关注'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('a person already followed has no bar (203)', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid, chatSettingsOf: {777: const ChatSettings(following: true)});
      await openChat(tester, api, person());

      expect(api.calls, contains('chatSettings 777'));
      expect(byKey('chat-settings-bar'), findsNothing);
      expect(byKey('chat-composer'), findsOneWidget);
    });

    testWidgets('without the push switch only 加关注 shows', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid, chatSettingsOf: {777: const ChatSettings(showPush: false)});
      await openChat(tester, api, person());

      expect(byKey('chat-push'), findsNothing);
      expect(byKey('chat-follow'), findsOneWidget);
    });

    testWidgets('‹ goes back and the gear toasts 暂未开放', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      await openChat(tester, api, person());

      expect(find.text('演示好友'), findsOneWidget);
      await tester.tap(byKey('chat-settings'));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      await toastGone(tester);

      await tester.tap(byKey('chat-back'));
      await settle(tester);
      expect(find.byType(ChatPage), findsNothing);
    });
  });

  group('messages', () {
    testWidgets('a time line goes before a message whose minute differs from the one before', (tester) async {
      final first = DateTime(2025, 11, 26, 21, 51);
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [
            tip(1, '对方主动回复或关注你前，最多发送1条消息', at: first),
            text(2, '演示的第一句', sender: selfMid, at: first.add(const Duration(minutes: 3))),
            text(3, '演示的回复', at: DateTime(2025, 11, 28, 14, 30, 5)),
            text(4, '同一分钟的第二句', at: DateTime(2025, 11, 28, 14, 30, 50)),
            text(5, '下一分钟', at: DateTime(2025, 11, 28, 14, 31)),
          ],
        },
      );
      await openChat(tester, api, person());

      expect(find.text(chatStamp(first)), findsOneWidget);
      expect(find.text('2025年11月26日 21:54'), findsOneWidget);
      expect(find.text('2025年11月28日 14:30'), findsOneWidget);
      expect(find.text('2025年11月28日 14:31'), findsOneWidget);
      expect(find.byType(ChatTimeLine), findsNWidgets(4));
      expect(find.byType(ChatTip), findsOneWidget);
    });

    testWidgets('their bubbles sit at the left on white, yours at the right on cyan with your face', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [text(1, '他们说的', at: demoTime), text(2, '我说的', sender: selfMid, at: demoTime)],
        },
      );
      await openChat(tester, api, person());

      final theirs = tester.getRect(byKey('chat-bubble-1'));
      final yours = tester.getRect(byKey('chat-bubble-2'));
      expect(theirs.left, MessageChatTheme.side + MessageChatTheme.face + MessageChatTheme.faceGap);
      expect(yours.right, 440 - MessageChatTheme.side - MessageChatTheme.face - MessageChatTheme.faceGap);
      expect(_fill(tester, byKey('chat-bubble-1')), MessageChatTheme.theirs);
      expect(_fill(tester, byKey('chat-bubble-2')), MessageChatTheme.yours);
      expect(byKey('chat-face-1'), findsOneWidget);
      expect(byKey('chat-face-2'), findsNothing);
      expect(byKey('chat-own-face'), findsOneWidget);
      expect(tester.getRect(byKey('chat-own-face')).right, 440 - MessageChatTheme.side);
      // The account is a 大会员 with the 大 on its face.
      expect(byKey('chat-own-vip'), findsOneWidget);
    });

    testWidgets('a tap on their face opens their space', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [text(1, '你好')],
        },
      );
      await openChat(tester, api, person());

      await tester.tap(byKey('chat-face-1'));
      await settle(tester);
      expect(find.byType(SpacePage), findsOneWidget);
    });

    testWidgets('emote codes draw as their pictures and an unknown one stays words', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [
            text(1, '早上好[微笑][未知]', emotes: const {'[微笑]': 'https://i0.hdslb.com/bfs/emote/demo.png'}),
          ],
        },
      );
      await openChat(tester, api, person());

      expect(
        find.byWidgetPredicate(
          (widget) => widget is RemoteImage && widget.url == 'https://i0.hdslb.com/bfs/emote/demo.png',
        ),
        findsOneWidget,
      );
      final words = tester.widget<RichText>(
        find.descendant(of: byKey('chat-bubble-1'), matching: find.byType(RichText)).first,
      );
      expect(words.text.toPlainText(), contains('早上好'));
      expect(words.text.toPlainText(), contains('[未知]'));
      expect(words.text.toPlainText(), isNot(contains('[微笑]')));
    });

    testWidgets('a web address draws as 网页链接 and opens in Safari', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [text(1, '领取请戳>>https://www.example.com/demo?a=1】')],
        },
      );
      final harness = await openChat(tester, api, person());

      expect(find.text('网页链接'), findsOneWidget);
      expect(find.textContaining('example.com'), findsNothing);
      await tester.tap(byKey('chat-web-link'));
      await settle(tester);
      expect(harness.webOpened, [Uri.parse('https://www.example.com/demo?a=1')]);
    });

    testWidgets('a video address opens in the app, and an address nothing opens toasts', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [text(1, '看这个 https://www.bilibili.com/video/BV1GJ411x7h7 好看')],
        },
      );
      final harness = await openChat(tester, api, person());

      await tester.tap(byKey('chat-web-link'));
      await settle(tester);
      expect(harness.videosOpened, ['https://www.bilibili.com/video/BV1GJ411x7h7']);
      expect(harness.webOpened, isEmpty);
    });

    testWidgets('an address Safari doesn\'t take toasts', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [text(1, 'https://www.example.com/x')],
        },
      );
      final harness = await openChat(tester, api, person());
      harness.webAnswer = false;

      await tester.tap(byKey('chat-web-link'));
      await settle(tester);
      expect(harness.webOpened, hasLength(1));
      expect(find.text('无法打开链接'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('a picture message is drawn as a rounded picture of its shape', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [
            ChatMessage(
              seqno: 1,
              senderMid: 777,
              kind: ChatMessageKind.picture,
              picture: 'https://i0.hdslb.com/bfs/im/demo.png',
              pictureWidth: 400,
              pictureHeight: 200,
              time: demoTime,
            ),
          ],
        },
      );
      await openChat(tester, api, person());

      expect(tester.getSize(byKey('chat-picture-1')), const Size(200, 100));
    });

    testWidgets('withdrawn messages and tips are grey lines; 此条消息为自动回复 goes under an auto reply', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [
            text(1, '谢谢关注\n加投稿哦', autoReply: true),
            ChatMessage(seqno: 2, senderMid: 777, kind: ChatMessageKind.withdrawn, time: demoTime),
            ChatMessage(seqno: 3, senderMid: selfMid, kind: ChatMessageKind.withdrawn, time: demoTime),
          ],
        },
      );
      await openChat(tester, api, person());

      expect(find.text('此条消息为自动回复'), findsOneWidget);
      expect(find.text('对方撤回了一条消息'), findsOneWidget);
      expect(find.text('你撤回了一条消息'), findsOneWidget);
    });

    testWidgets('older pages load as the list nears its top, one call at a time', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        pageSize: 30,
        chats: {
          777: [for (var seqno = 1; seqno <= 80; seqno++) text(seqno, '第$seqno条')],
        },
      );
      Iterable<String> asked() => api.calls.where((call) => call.startsWith('messages'));
      await openChat(tester, api, person());
      expect(asked(), ['messages 777 0']);
      expect(find.text('第80条'), findsOneWidget);

      final hold = api.holds['messages'] = Completer<void>();
      await tester.drag(byKey('chat-list'), const Offset(0, 3000));
      await tester.pump();
      await tester.drag(byKey('chat-list'), const Offset(0, 3000));
      await tester.pump();
      expect(asked(), ['messages 777 0', 'messages 777 51']);
      expect(byKey('chat-older-loading'), findsOneWidget);

      api.holds.remove('messages');
      hold.complete();
      await settle(tester);
      expect(find.text('第50条'), findsOneWidget);
      await tester.drag(byKey('chat-list'), const Offset(0, 3000));
      await settle(tester);
      await tester.drag(byKey('chat-list'), const Offset(0, 3000));
      await settle(tester);
      expect(asked(), ['messages 777 0', 'messages 777 51', 'messages 777 21']);
      expect(find.text('第1条'), findsOneWidget);
    });

    testWidgets('the first page acks the session up to its newest message', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [text(4, '一'), text(9, '二')],
        },
      );
      final harness = await openChat(tester, api, person(maxSeqno: 3));

      expect(harness.messages.opened, hasLength(1));
      expect(harness.messages.opened.single.talkerId, 777);
      expect(harness.messages.opened.single.maxSeqno, 9);
    });

    testWidgets('a failed first page offers a retry', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [text(1, '回来了')],
        },
      )..failures['messages'] = const BiliError.http(500);
      final harness = await openChat(tester, api, person());

      expect(byKey('chat-failed'), findsOneWidget);
      expect(harness.messages.opened, isEmpty);
      api.failures.clear();
      await tester.tap(byKey('chat-failed'));
      await settle(tester);
      expect(find.text('回来了'), findsOneWidget);
      expect(harness.messages.opened, hasLength(1));
    });
  });

  group('the composer (202, 218, 219)', () {
    testWidgets('the send key sends, the message shows at once and the field empties', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [text(1, '在吗')],
        },
      );
      final hold = api.holds['send'] = Completer<void>();
      await openChat(tester, api, person());

      await tester.enterText(byKey('chat-field'), '  演示的消息  ');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(find.text('演示的消息'), findsOneWidget);
      expect(tester.widget<TextField>(byKey('chat-field')).controller!.text, isEmpty);
      hold.complete();
      await settle(tester);
      expect(api.sent, [(talkerId: 777, text: '演示的消息')]);
      expect(find.text('演示的消息'), findsOneWidget);
    });

    testWidgets('a failed send takes the message away, keeps the text and toasts why', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid)
        ..failures['send'] = const BiliError.api(code: 21046, message: '发送过于频繁，请稍后再试');
      await openChat(tester, api, person());

      await tester.enterText(byKey('chat-field'), '演示的消息');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      expect(tester.widget<TextField>(byKey('chat-field')).controller!.text, '演示的消息');
      expect(find.text('发送过于频繁，请稍后再试'), findsOneWidget);
      expect(find.byType(ChatBubbleRow), findsNothing);
      await toastGone(tester);
    });

    testWidgets('empty text sends nothing', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      await openChat(tester, api, person());

      await tester.enterText(byKey('chat-field'), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      expect(api.calls.where((call) => call.startsWith('send')), isEmpty);
    });

    testWidgets('logged out, sending asks for the login and sends nothing without one', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      final harness = await openChat(tester, api, person(), loggedIn: false);

      await tester.enterText(byKey('chat-field'), '演示的消息');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      expect(harness.loginGate.requests, 1);
      expect(api.sent, isEmpty);
      expect(tester.widget<TextField>(byKey('chat-field')).controller!.text, '演示的消息');
    });

    testWidgets('the face opens the emote panel in the keyboard\'s place; an emote goes into the field', (
      tester,
    ) async {
      final api = FakeMessageApi(selfMid: selfMid);
      await openChat(tester, api, person());

      expect(find.byType(EmotePanel), findsNothing);
      await tester.tap(byKey('chat-emotes'));
      await settle(tester);
      expect(find.byType(EmotePanel), findsOneWidget);
      expect(tester.getSize(find.byType(EmotePanel)).height, MessageChatTheme.emotePanel);
      Finder glyph(String asset) => find.byWidgetPredicate((widget) => widget is ChatGlyph && widget.asset == asset);
      expect(glyph(ChatArt.keyboard), findsOneWidget);
      expect(glyph(ChatArt.emote), findsNothing);

      await tester.tap(find.text('[大笑]'));
      await tester.pump();
      expect(tester.widget<TextField>(byKey('chat-field')).controller!.text, '[大笑]');

      await tester.tap(byKey('chat-emotes'));
      await settle(tester);
      expect(find.byType(EmotePanel), findsNothing);
      expect(glyph(ChatArt.emote), findsOneWidget);
    });

    testWidgets('the picture button toasts 暂未开放', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      await openChat(tester, api, person());

      await tester.tap(byKey('chat-picture'));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('the composer rides the keyboard', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      final harness = await chatHarness(api);
      await pumpChatApp(tester, harness, ChatLauncher(harness: harness, session: person()));
      await tester.tap(byKey('open-chat'));
      await settle(tester);
      final resting = tester.getRect(byKey('chat-composer'));
      expect(resting.bottom, 956);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      expect(tester.getRect(byKey('chat-composer')).bottom, 956 - 300);
    });
  });

  group('notice boxes (200, 201)', () {
    testWidgets('cards show their title, body, fields and links; there is no bar and no composer', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          844424930131966: [
            notice(
              1,
              title: '登录操作通知',
              body: '你的账号在新设备登录成功（演示）',
              fields: const [(title: '有效期', detail: '演示设备'), (title: '参考登录地', detail: '演示地区')],
              links: const [(text: '查看详情', uri: 'https://www.example.com/detail')],
            ),
            text(2, '演示福利已送达，领取>>https://www.example.com/gift', sender: 844424930131966),
          ],
        },
      );
      final harness = await openChat(tester, api, boxSession(NoticeBox.community));

      expect(find.text('社区中心'), findsOneWidget);
      expect(find.text('登录操作通知'), findsOneWidget);
      expect(find.text('你的账号在新设备登录成功（演示）'), findsOneWidget);
      expect(find.text('有效期'), findsOneWidget);
      expect(find.text('演示地区'), findsOneWidget);
      expect(find.text('查看详情'), findsOneWidget);
      expect(byKey('chat-settings-bar'), findsNothing);
      expect(byKey('chat-composer'), findsNothing);
      expect(api.calls.where((call) => call.startsWith('chatSettings')), isEmpty);
      expect(find.byType(NoticeBoxIcon), findsOneWidget);
      // A value starts 68.33 in from the card's words, or 12 after a longer label.
      const words = MessageChatTheme.cardMargin + MessageChatTheme.cardInset;
      expect(tester.getTopLeft(find.text('演示设备')).dx, closeTo(words + 68.33, 0.01));
      expect(tester.getTopLeft(find.text('演示地区')).dx, closeTo(words + 5 * 13 + 12, 0.01));

      await tester.tap(byKey('chat-card-link-0'));
      await settle(tester);
      expect(harness.webOpened, [Uri.parse('https://www.example.com/detail')]);
      expect(harness.messages.opened.single.talkerId, 844424930131966);
    });

    testWidgets('a card link to a space opens it in the app, and an app link nothing knows toasts', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          0: [
            notice(
              1,
              title: '收到个性装扮成功通知',
              body: '演示装扮已到账',
              fields: const [(title: '有效期', detail: '永久有效')],
              links: const [
                (text: '立即查看', uri: 'bilibili://garb/demo'),
                (text: '去空间看看', uri: 'https://space.bilibili.com/2'),
              ],
            ),
          ],
        },
      );
      await openChat(tester, api, boxSession(NoticeBox.system, talkerId: 0));

      await tester.tap(byKey('chat-card-link-0'));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      await toastGone(tester);

      await tester.tap(byKey('chat-card-link-1'));
      await settle(tester);
      expect(find.byType(SpacePage), findsOneWidget);
    });

    testWidgets('a box opened by its route draws the box\'s name', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      await openChatByRoute(tester, api, boxSession(NoticeBox.service));

      expect(find.byType(ChatPage), findsOneWidget);
      expect(find.text('服务通知'), findsOneWidget);
    });
  });
}
