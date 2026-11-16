import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/live/danmaku/live_recent_emotes.dart';
import 'package:bilifast/live/danmaku/live_send_input.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/room/live_overlays.dart';
import 'package:bilifast/live/room/live_room_model.dart' show LiveNotLoggedIn;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_send_support.dart';

const _portrait = Size(440, 956);
const _landscape = Size(956, 440);

/// The keyboard's height on KaiC's phone, upright (226) and turned (223).
const _keyboardUpright = 348.0;
const _keyboardTurned = 224.0;

void main() {
  late LiveHarness harness;
  late FakeRoom room;
  late LiveOverlays overlays;
  late LiveRecentEmotes recents;

  setUp(() {
    room = FakeRoom(api: demoApi());
    overlays = LiveOverlays()..open(LiveOverlay.send);
    recents = LiveRecentEmotes.memory();
    LiveRecentEmotes.use(recents);
  });

  tearDown(() {
    room.dispose();
    overlays.dispose();
  });

  Future<void> open(WidgetTester tester, {Size size = _portrait, bool keyboard = true}) async {
    harness = await liveHarness();
    final landscape = size.width > size.height;
    if (keyboard) {
      tester.view.viewInsets = FakeViewPadding(bottom: landscape ? _keyboardTurned : _keyboardUpright);
      addTearDown(tester.view.resetViewInsets);
    }
    await pumpLive(
      tester,
      harness,
      ValueListenableBuilder<LiveOverlay>(
        valueListenable: overlays,
        builder: (context, overlay, _) => overlay == LiveOverlay.send
            ? LiveSendInput(room: room, overlays: overlays, landscape: landscape)
            : const SizedBox.expand(key: ValueKey('room')),
      ),
      size: size,
    );
    await tester.pump();
    await tester.pump();
  }

  TextEditingController field(WidgetTester tester) => tester.widget<TextField>(byKey('live-send-field')).controller!;

  Color sendFill(WidgetTester tester) {
    final box = tester.widget<Container>(
      find.descendant(of: byKey('live-send-button'), matching: find.byType(Container)),
    );
    return (box.decoration! as ShapeDecoration).color!;
  }

  group('226 upright', () {
    testWidgets('lies on the keyboard as 226 measures it, the field focused', (tester) async {
      await open(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.widget<TextField>(byKey('live-send-field')).focusNode!.hasFocus, isTrue);
      expect(find.text('弹幕支持下～'), findsOneWidget);

      final fieldBox = tester.getRect(
        find.ancestor(of: byKey('live-send-field'), matching: find.byType(Container)).first,
      );
      expect(fieldBox, const Rect.fromLTRB(12, 532, 358, 560));
      expect(tester.getRect(byKey('live-send-button')), const Rect.fromLTRB(370, 532, 428, 560));
      final pill = tester.getRect(byKey('live-send-sc'));
      expect(pill.left, 12);
      expect(pill.top, 488);
      expect(pill.height, 32);
      // The glyphs centred 320.67 / 368 / 416 in, the band's middle 24 under the field.
      expect(tester.getCenter(byKey('live-send-face')), const Offset(368, 584));
      expect(tester.getCenter(byKey('live-send-style')).dx, 416);
      // Seven emotes before the glyphs, the first centred 26 in.
      expect(tester.getCenter(byKey('live-recent-emoji_0')), const Offset(26, 584));
      expect(tester.getCenter(byKey('live-recent-emoji_6')).dx, 266);
    });

    testWidgets('发送 is dim until there is something to send', (tester) async {
      await open(tester);
      expect(sendFill(tester), const Color(0x66FF6699));
      await tester.enterText(byKey('live-send-field'), '   ');
      await tester.pump();
      expect(sendFill(tester), const Color(0x66FF6699));
      await tester.tap(byKey('live-send-button'));
      await tester.pump();
      expect(room.sent, isEmpty);

      await tester.enterText(byKey('live-send-field'), ' 主播好 ');
      await tester.pump();
      expect(sendFill(tester), const Color(0xFFFF6699));
    });

    testWidgets('a send that lands closes the input and clears it, trimmed', (tester) async {
      await open(tester);
      await tester.enterText(byKey('live-send-field'), '  主播好  ');
      await tester.pump();
      await tester.tap(byKey('live-send-button'));
      await tester.pump();
      expect(room.sent, ['主播好']);
      expect(overlays.value, LiveOverlay.none);
      expect(byKey('live-send-input'), findsNothing);
    });

    testWidgets('a second tap while the first send is out sends nothing more', (tester) async {
      await open(tester);
      room.hold = Completer<void>();
      await tester.enterText(byKey('live-send-field'), '一条');
      await tester.pump();
      await tester.tap(byKey('live-send-button'));
      await tester.pump();
      expect(sendFill(tester), const Color(0x66FF6699));
      await tester.tap(byKey('live-send-button'));
      await tester.pump();
      room.hold!.complete();
      await tester.pump();
      expect(room.sent, ['一条']);
    });

    testWidgets('the keyboard\'s 发送 sends too', (tester) async {
      await open(tester);
      await tester.enterText(byKey('live-send-field'), '晚上好');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(room.sent, ['晚上好']);
      expect(overlays.value, LiveOverlay.none);
    });

    testWidgets('a failed send keeps the text and toasts Bilibili\'s words', (tester) async {
      await open(tester);
      room.failure = const BiliError.api(code: 10031, message: '发送频率过快');
      await tester.enterText(byKey('live-send-field'), '再来一条');
      await tester.pump();
      await tester.tap(byKey('live-send-button'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('发送频率过快'), findsOneWidget);
      expect(field(tester).text, '再来一条');
      expect(overlays.value, LiveOverlay.send);
      expect(room.sent, isEmpty);
      await toastGone(tester);

      room.failure = StateError('anything else');
      await tester.tap(byKey('live-send-button'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('发送失败，请稍后重试'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('the field stops at 40 characters', (tester) async {
      await open(tester);
      await tester.enterText(byKey('live-send-field'), '弹' * 50);
      await tester.pump();
      expect(field(tester).text, '弹' * 40);
    });

    testWidgets('logged out, 发送 goes to the login and sends nothing', (tester) async {
      await open(tester);
      room.signedIn = false;
      await tester.enterText(byKey('live-send-field'), '你好');
      await tester.pump();
      await tester.tap(byKey('live-send-button'));
      await tester.pump();
      expect(harness.loginGate.requests, 1);
      expect(room.sent, isEmpty);
      expect(field(tester).text, '你好');
    });

    testWidgets('a send Bilibili answers -101 goes to the login', (tester) async {
      await open(tester);
      room.failure = const BiliError.api(code: -101, message: '账号未登录');
      await tester.enterText(byKey('live-send-field'), '你好');
      await tester.pump();
      await tester.tap(byKey('live-send-button'));
      await tester.pump();
      expect(harness.loginGate.requests, 1);
      expect(find.text('需要登录'), findsNothing);
      expect(field(tester).text, '你好');
    });

    testWidgets("the room's own logged-out refusal goes to the login too", (tester) async {
      await open(tester);
      room.failure = const LiveNotLoggedIn();
      await tester.enterText(byKey('live-send-field'), '你好');
      await tester.pump();
      await tester.tap(byKey('live-send-button'));
      await tester.pump();
      expect(harness.loginGate.requests, 1);
      expect(field(tester).text, '你好');
    });

    testWidgets('a tap above the input closes it', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(220, 200));
      await tester.pump();
      expect(overlays.value, LiveOverlay.none);
    });

    testWidgets('a tap beside the 醒目留言 pill closes it too, the pill itself toasts', (tester) async {
      await open(tester);
      await tester.tap(byKey('live-send-sc'));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      expect(overlays.value, LiveOverlay.send);
      await toastGone(tester);
      await tester.tapAt(const Offset(300, 500));
      await tester.pump();
      expect(overlays.value, LiveOverlay.none);
    });

    for (final key in ['live-send-translate', 'live-send-style']) {
      testWidgets('$key toasts 暂未开放', (tester) async {
        await open(tester);
        await tester.tap(byKey(key));
        await tester.pump();
        expect(find.text('暂未开放'), findsOneWidget);
        expect(overlays.value, LiveOverlay.send);
        await toastGone(tester);
      });
    }

    testWidgets('😊 swaps the keyboard for 227\'s panel and back; the packages choose the grid', (tester) async {
      await open(tester);
      await tester.tap(byKey('live-send-face'));
      await tester.pump();
      await tester.pump();
      expect(byKey('live-emote-panel'), findsOneWidget);
      expect(tester.widget<TextField>(byKey('live-send-field')).readOnly, isTrue);
      expect(tester.widget<Text>(byKey('live-emote-title')).data, '全部表情');
      // The panel takes the keyboard's place: 227's input lies where 226's did.
      expect(tester.getRect(byKey('live-send-button')).top, 532);
      expect(tester.getRect(byKey('live-emote-panel')), const Rect.fromLTRB(0, 600, 440, 956));
      // Eight to a row, centred 52 apart from 38 in; rows 50 apart.
      expect(tester.getCenter(byKey('live-emote-emoji_0')), const Offset(38, 650));
      expect(tester.getCenter(byKey('live-emote-emoji_7')).dx, 402);
      expect(tester.getCenter(byKey('live-emote-emoji_8')), const Offset(38, 700));
      expect(byKey('live-emote-delete'), findsOneWidget);
      expect(tester.getRect(byKey('live-emote-package-1')).top, 891);

      await tester.tap(byKey('live-emote-package-2'));
      await tester.pump();
      expect(tester.widget<Text>(byKey('live-emote-title')).data, '房间专属');
      expect(byKey('live-emote-room_zan'), findsOneWidget);
      expect(byKey('live-emote-emoji_0'), findsNothing);
      expect(byKey('live-emote-delete'), findsNothing, reason: 'nothing of this package goes into the field');

      await tester.tap(byKey('live-send-face'));
      await tester.pump();
      expect(byKey('live-emote-panel'), findsNothing);
      expect(tester.widget<TextField>(byKey('live-send-field')).readOnly, isFalse);
    });

    testWidgets('a tap on the field under the panel brings the keyboard back', (tester) async {
      await open(tester);
      await tester.tap(byKey('live-send-face'));
      await tester.pump();
      await tester.tap(byKey('live-send-field'));
      await tester.pump();
      expect(byKey('live-emote-panel'), findsNothing);
    });

    testWidgets('an inline emote goes into the field, ⌫ takes it out whole', (tester) async {
      await open(tester);
      await tester.enterText(byKey('live-send-field'), '好');
      await tester.tap(byKey('live-send-face'));
      await tester.pump();
      await tester.tap(byKey('live-emote-emoji_3'));
      await tester.pump();
      expect(field(tester).text, '好[表情3]');
      expect(room.sentEmotes, isEmpty);
      expect(sendFill(tester), const Color(0xFFFF6699));

      await tester.tap(byKey('live-emote-delete'));
      await tester.pump();
      expect(field(tester).text, '好');
      await tester.tap(byKey('live-emote-delete'));
      await tester.pump();
      expect(field(tester).text, '');
      await tester.tap(byKey('live-emote-delete'));
      await tester.pump();
      expect(field(tester).text, '');

      // Never past the limit: an emote that would cross it stays out.
      await tester.tap(byKey('live-send-field'));
      await tester.pump();
      await tester.enterText(byKey('live-send-field'), '弹' * 38);
      await tester.tap(byKey('live-recent-emoji_1'));
      await tester.pump();
      expect(field(tester).text, '弹' * 38);
    });

    testWidgets('a whole-message emote is sent at once, the panel staying', (tester) async {
      await open(tester);
      await tester.tap(byKey('live-send-face'));
      await tester.pump();
      await tester.tap(byKey('live-emote-package-2'));
      await tester.pump();
      await tester.tap(byKey('live-emote-room_zan'));
      await tester.pump();
      expect(room.sentEmotes.map((emote) => emote.unique), ['room_zan']);
      expect(byKey('live-emote-panel'), findsOneWidget);

      room.failure = const BiliError.api(code: 10031, message: '发送频率过快');
      await tester.tap(byKey('live-emote-room_chong'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('发送频率过快'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('logged out, a whole-message emote goes to the login', (tester) async {
      await open(tester);
      room.signedIn = false;
      await tester.tap(byKey('live-send-face'));
      await tester.pump();
      await tester.tap(byKey('live-emote-package-2'));
      await tester.pump();
      await tester.tap(byKey('live-emote-room_zan'));
      await tester.pump();
      expect(harness.loginGate.requests, 1);
      expect(room.sentEmotes, isEmpty);
    });

    testWidgets('the emotes used are kept and lead the band next time', (tester) async {
      await open(tester);
      await tester.tap(byKey('live-send-face'));
      await tester.pump();
      await tester.tap(byKey('live-emote-emoji_5'));
      await tester.tap(byKey('live-emote-package-2'));
      await tester.pump();
      await tester.tap(byKey('live-emote-room_zan'));
      await tester.pump();
      expect(recents.list.map((emote) => emote.unique), ['room_zan', 'emoji_5']);

      overlays.close();
      await tester.pump();
      overlays.open(LiveOverlay.send);
      await tester.pump();
      await tester.pump();
      expect(tester.getCenter(byKey('live-recent-room_zan')).dx, 26);
      expect(tester.getCenter(byKey('live-recent-emoji_5')).dx, 66);
      expect(tester.getCenter(byKey('live-recent-emoji_0')).dx, 106);
      // The room's emotes are asked once while it stays open.
      expect((room.api as FakeLiveApi).calls.where((call) => call.startsWith('emotes')), hasLength(1));
    });

    testWidgets('emotes that failed to load are asked again from the panel', (tester) async {
      final api = demoApi()..failures['emotes'] = const BiliError.network('timeout');
      room = FakeRoom(api: api);
      await open(tester);
      expect(byKey('live-recent-emoji_0'), findsNothing);
      await tester.tap(byKey('live-send-face'));
      await tester.pump();
      expect(find.text('加载失败，点击重试'), findsOneWidget);

      api.failures.clear();
      await tester.tap(byKey('live-emote-retry'));
      await tester.pump();
      await tester.pump();
      expect(byKey('live-emote-emoji_0'), findsOneWidget);
      expect(byKey('live-recent-emoji_0'), findsOneWidget);
      // At the open, as the panel opened after the failure, and the retry.
      expect(api.calls.where((call) => call.startsWith('emotes')), hasLength(3));
    });

    testWidgets('a recent emote this room lacks stays out of its band', (tester) async {
      recents.record(const LiveEmote(text: '别的房间', url: '', unique: 'other_room'));
      await open(tester);
      expect(byKey('live-recent-other_room'), findsNothing);
      expect(tester.getCenter(byKey('live-recent-emoji_0')).dx, 26);
    });
  });

  group('223 turned', () {
    testWidgets('the bar runs across the top of the keyboard as 223 measures it', (tester) async {
      await open(tester, size: _landscape);
      final fieldBox = tester.getRect(
        find.ancestor(of: byKey('live-send-field'), matching: find.byType(Container)).first,
      );
      // Panel top at 132: the field 8 under it, 106 from either side with 发送.
      expect(fieldBox.left, 106);
      expect(fieldBox.right, closeTo(672.67, 0.34));
      expect(fieldBox.top, 140);
      expect(fieldBox.height, 28);
      expect(tester.getRect(byKey('live-send-button')), rectMoreOrLessEquals(const Rect.fromLTRB(792, 140, 850, 168)));
      expect(tester.getCenter(byKey('live-send-translate')).dx, closeTo(696.67, 0.34));
      expect(tester.getCenter(byKey('live-send-face')).dx, closeTo(732, 0.34));
      expect(tester.getCenter(byKey('live-send-face')).dy, 154);
      expect(tester.getCenter(byKey('live-send-style')).dx, closeTo(768, 0.34));
      expect(tester.getCenter(byKey('live-recent-emoji_0')), const Offset(88, 192));
      expect(tester.getCenter(byKey('live-recent-emoji_1')).dx, 128);
      final pill = tester.getRect(byKey('live-send-sc'));
      expect(pill.left, 44);
      expect(pill.bottom, 128);
    });

    testWidgets('sends, toasts and opens the emote panel as upright', (tester) async {
      await open(tester, size: _landscape);
      expect(sendFill(tester), const Color(0x66FF6699));
      await tester.tap(byKey('live-send-style'));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      await toastGone(tester);

      await tester.tap(byKey('live-send-face'));
      await tester.pump();
      expect(byKey('live-emote-panel'), findsOneWidget);
      expect(tester.getRect(byKey('live-emote-panel')).height, 224);
      await tester.tap(byKey('live-emote-emoji_2'));
      await tester.pump();
      expect(field(tester).text, '[表情2]');

      await tester.tap(byKey('live-send-button'));
      await tester.pump();
      expect(room.sent, ['[表情2]']);
      expect(overlays.value, LiveOverlay.none);
    });
  });
}
