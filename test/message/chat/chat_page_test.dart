import 'dart:async';

import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/comments/emote_panel.dart';
import 'package:bilifast/comments/emote_store.dart';
import 'package:bilifast/message/chat/chat_emote_panel.dart';
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
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: bubble, matching: find.byType(DecoratedBox), matchRoot: true).first,
  );
  return (box.decoration as BoxDecoration).color;
}

Finder _inPanel(String text) => find.descendant(of: byKey('chat-emote-panel'), matching: find.text(text));

/// Answers each messages call with the next of [pages].
class _PagedApi extends FakeMessageApi {
  _PagedApi(this.pages) : super(selfMid: selfMid);

  final List<ChatMessagePage> pages;
  final asked = <int?>[];

  @override
  Future<ChatMessagePage> messages(ChatSession session, {int? beforeSeqno}) async {
    asked.add(beforeSeqno);
    return pages[asked.length < pages.length ? asked.length - 1 : pages.length - 1];
  }
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

    testWidgets('a push switch the api can\'t change (UnsupportedError, the fakes\' fallback) toasts 暂未开放', (
      tester,
    ) async {
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

    testWidgets('加关注 tapped twice while its call is out sends one follow', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      await openChat(tester, api, person());

      final hold = api.holds['follow'] = Completer<void>();
      await tester.tap(byKey('chat-follow'));
      await tester.pump();
      await tester.tap(byKey('chat-follow'));
      await tester.pump();
      api.holds.clear();
      hold.complete();
      await settle(tester);

      expect(api.calls.where((call) => call.startsWith('follow')), hasLength(1));
      expect(find.text('已关注'), findsOneWidget);
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

    testWidgets('a one-line bubble is as tall on their side as on yours (202: 35 pt)', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [text(1, '他们说的', at: demoTime), text(2, '我说的', sender: selfMid, at: demoTime)],
        },
      );
      await openChat(tester, api, person());

      Rect drawn(String key) =>
          tester.getRect(find.descendant(of: byKey(key), matching: find.byType(DecoratedBox), matchRoot: true).first);
      expect(drawn('chat-bubble-1').height, closeTo(drawn('chat-bubble-2').height, 0.01));
      expect(tester.getSize(byKey('chat-bubble-1')).height, closeTo(drawn('chat-bubble-1').height, 0.01));
    });

    testWidgets('a short chat whose older page repeats what is shown asks for it once', (tester) async {
      final api = _PagedApi([
        ChatMessagePage(messages: [text(8, '八'), text(9, '九')], hasMore: true, minSeqno: 8, maxSeqno: 9),
        ChatMessagePage(messages: [text(8, '八')], hasMore: true, minSeqno: 8, maxSeqno: 8),
      ]);
      await openChat(tester, api, person());
      await settle(tester, 30);

      expect(api.asked, [null, 8]);
      expect(find.text('八'), findsOneWidget);
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

    testWidgets('a picture of no given size is a square of its own token; the page is 202\'s #F6F7F8', (tester) async {
      final api = FakeMessageApi(
        selfMid: selfMid,
        chats: {
          777: [
            ChatMessage(
              seqno: 1,
              senderMid: 777,
              kind: ChatMessageKind.picture,
              picture: 'https://i0.hdslb.com/bfs/im/demo.png',
              time: demoTime,
            ),
          ],
        },
      );
      await openChat(tester, api, person());

      expect(tester.getSize(byKey('chat-picture-1')), const Size.square(MessageChatTheme.pictureUnsized));
      expect(MessageChatTheme.page, const Color(0xFFF6F7F8));
      final page = tester.widget<ColoredBox>(
        find.descendant(of: find.byType(ChatPage), matching: find.byType(ColoredBox)).first,
      );
      expect(page.color, MessageChatTheme.page);
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
    testWidgets(
      'the keyboard shows its plain ⏎ (218), whose return sends: the message shows at once, the field empties',
      (tester) async {
        final api = FakeMessageApi(
          selfMid: selfMid,
          chats: {
            777: [text(1, '在吗')],
          },
        );
        final hold = api.holds['send'] = Completer<void>();
        await openChat(tester, api, person());

        expect(tester.widget<TextField>(byKey('chat-field')).textInputAction, TextInputAction.newline);
        await tester.enterText(byKey('chat-field'), '  演示的消息  ');
        await pressReturn(tester);
        await tester.pump();

        expect(find.text('演示的消息'), findsOneWidget);
        expect(chatField(tester).text, isEmpty);
        hold.complete();
        await settle(tester);
        expect(api.sent, [(talkerId: 777, text: '演示的消息')]);
        expect(find.text('演示的消息'), findsOneWidget);
      },
    );

    testWidgets('a pasted text keeps its line breaks and sends nothing', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      await openChat(tester, api, person());

      await tester.enterText(byKey('chat-field'), '第一行\n第二行');
      await tester.pump();
      expect(chatField(tester).text, '第一行\n第二行');
      expect(api.calls.where((call) => call.startsWith('send')), isEmpty);
    });

    testWidgets('a failed send takes the message away, keeps the text and toasts why', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid)
        ..failures['send'] = const BiliError.api(code: 21046, message: '发送过于频繁，请稍后再试');
      await openChat(tester, api, person());

      await tester.enterText(byKey('chat-field'), '演示的消息');
      await pressReturn(tester);
      await settle(tester);

      expect(chatField(tester).text, '演示的消息');
      expect(find.text('发送过于频繁，请稍后再试'), findsOneWidget);
      expect(find.byType(ChatBubbleRow), findsNothing);
      await toastGone(tester);
    });

    testWidgets('a send that fails after more was typed puts its text back in front of the new', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid)
        ..failures['send'] = const BiliError.api(code: 21046, message: '发送过于频繁，请稍后再试');
      final hold = api.holds['send'] = Completer<void>();
      await openChat(tester, api, person());

      await tester.enterText(byKey('chat-field'), '演示的消息');
      await pressReturn(tester);
      await tester.pump();
      expect(chatField(tester).text, isEmpty);
      await tester.enterText(byKey('chat-field'), '又一句');
      hold.complete();
      await settle(tester);

      expect(chatField(tester).text, '演示的消息又一句');
      expect(chatField(tester).selection, const TextSelection.collapsed(offset: 8));
      await toastGone(tester);
    });

    testWidgets('empty text sends nothing', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      await openChat(tester, api, person());

      await tester.enterText(byKey('chat-field'), '   ');
      await pressReturn(tester);
      await settle(tester);
      expect(api.calls.where((call) => call.startsWith('send')), isEmpty);
      expect(chatField(tester).text, '   ');
    });

    testWidgets('logged out, sending asks for the login and sends nothing without one', (tester) async {
      final api = FakeMessageApi(selfMid: selfMid);
      final harness = await openChat(tester, api, person(), loggedIn: false);

      await tester.enterText(byKey('chat-field'), '演示的消息');
      await pressReturn(tester);
      await settle(tester);
      expect(harness.loginGate.requests, 1);
      expect(api.sent, isEmpty);
      expect(chatField(tester).text, '演示的消息');
    });

    testWidgets('the face opens the chat\'s own emote panel in the keyboard\'s place, the field keeping its caret', (
      tester,
    ) async {
      final api = FakeMessageApi(selfMid: selfMid);
      await openChat(tester, api, person());
      await tester.tap(byKey('chat-field'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      expect(byKey('chat-emote-panel'), findsNothing);
      await tester.tap(byKey('chat-emotes'));
      await settle(tester);
      expect(find.byType(ChatEmotePanel), findsOneWidget);
      expect(find.byType(EmotePanel), findsNothing);
      expect(tester.getSize(byKey('chat-emote-panel')).height, MessageChatTheme.emotePanel);
      expect(find.text('所有表情'), findsNothing);
      expect(find.text('最近使用'), findsNothing);
      Finder glyph(String asset) => find.byWidgetPredicate((widget) => widget is ChatGlyph && widget.asset == asset);
      expect(glyph(ChatArt.keyboard), findsOneWidget);
      expect(glyph(ChatArt.emote), findsNothing);
      // The field keeps its focus and caret, with no keyboard under the panel.
      final field = tester.widget<TextField>(byKey('chat-field'));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.readOnly, isTrue);
      expect(tester.widget<EditableText>(find.byType(EditableText)).showCursor, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(_inPanel('[大笑]'));
      await tester.pump();
      expect(chatField(tester).text, '[大笑]');
      expect(chatField(tester).selection, const TextSelection.collapsed(offset: 4));

      await tester.tap(byKey('chat-emotes'));
      await settle(tester);
      expect(byKey('chat-emote-panel'), findsNothing);
      expect(glyph(ChatArt.emote), findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('the face with the field idle opens the panel and focuses the field, still with no keyboard', (
      tester,
    ) async {
      final api = FakeMessageApi(selfMid: selfMid);
      await openChat(tester, api, person());

      await tester.tap(byKey('chat-emotes'));
      await settle(tester);
      expect(tester.widget<TextField>(byKey('chat-field')).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);

      // A tap on the field brings the keyboard back in the panel's place.
      await tester.tap(byKey('chat-field'));
      await settle(tester);
      expect(byKey('chat-emote-panel'), findsNothing);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('the panel\'s bar: 🕒 shows the emotes used last, ⚙ 🔍 ★ toast 暂未开放, a package shows its own', (
      tester,
    ) async {
      final shared = RecentEmotes.shared;
      RecentEmotes.shared = RecentEmotes.memory();
      addTearDown(() => RecentEmotes.shared = shared);
      final api = FakeMessageApi(selfMid: selfMid);
      final harness = await openChat(tester, api, person());
      harness.pageApi.emotes = [
        ...harness.pageApi.emotes,
        const EmotePackage(
          id: 2,
          name: '颜文字',
          icon: '',
          isText: true,
          emotes: [Emote(token: '(⌒▽⌒)', url: '', large: false)],
        ),
      ];

      await tester.tap(byKey('chat-emotes'));
      await settle(tester);
      expect(find.text('NEW'), findsOneWidget);
      await tester.tap(_inPanel('[演示]'));
      await tester.pump();

      await tester.tap(byKey('chat-emote-recent'));
      await tester.pump();
      expect(byKey('chat-emote-grid-recent'), findsOneWidget);
      expect(_inPanel('[演示]'), findsOneWidget);
      expect(_inPanel('[微笑]'), findsNothing);

      for (final key in ['chat-emote-settings', 'chat-emote-search', 'chat-emote-favourites']) {
        await tester.tap(byKey(key));
        await tester.pump();
        expect(find.text('暂未开放'), findsOneWidget, reason: key);
        await toastGone(tester);
      }

      await tester.tap(byKey('chat-emote-tab-2'));
      await tester.pump();
      expect(byKey('chat-emote-grid-2'), findsOneWidget);
      expect(find.text('(⌒▽⌒)'), findsNWidgets(2));
      await tester.tap(byKey('chat-emote-tab-1'));
      await tester.pump();
      expect(_inPanel('[微笑]'), findsOneWidget);
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
