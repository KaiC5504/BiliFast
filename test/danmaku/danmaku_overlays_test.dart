import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_overlays.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/danmaku/send/danmaku_send_model.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';

/// A real session whose post answers as the test says, so these tests hold whatever the server side does.
class _Session extends DanmakuSession {
  _Session({required super.feed, required super.rules, required super.api, required this.post})
    : super(
        settings: DanmakuSettingsStore.memory(),
        target: () => (bvid: 'BV1xx411c7mD', cid: 42),
        position: () => 12.5,
        isLoggedIn: () => true,
        isVip: () => false,
        accountMid: () => 7,
        toast: (_) {},
        requestLogin: () {},
      );

  Future<String?> Function(String text, DanmakuStyle style) post;

  @override
  Future<String?> send(String text, DanmakuStyle style) => post(text, style);
}

const landscape = Size(956, 440);
const portrait = Size(440, 956);
const playerBottom = 309.67;

void main() {
  late _Session session;
  late List<String> toasts;
  late List<String> posted;
  late ValueNotifier<double> keyboard;

  setUp(() {
    PlayerPrefs.shared = PlayerPrefs.memory();
    DanmakuOverlays.debugForgetKeyboard();
    final logger = Logger(session: 'test');
    final api = FakePageApi();
    toasts = [];
    posted = [];
    keyboard = ValueNotifier(0);
    session = _Session(
      feed: DanmakuFeed(
        client: BiliClient(transport: Canned.http(), cookies: CookieJar(Canned.cookies), logger: logger),
        logger: logger,
      ),
      rules: BlockRuleStore(api: api, isLoggedIn: () => true),
      api: api,
      post: (text, style) async {
        posted.add(text);
        return null;
      },
    );
  });

  tearDown(() {
    session.dispose();
    keyboard.dispose();
  });

  Future<void> pumpLayer(WidgetTester tester, {Presentation presentation = Presentation.inline}) async {
    final size = presentation == Presentation.landscape ? landscape : portrait;
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: keyboard,
          builder: (context, inset, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
            child: child!,
          ),
          child: DanmakuOverlays(
            session: session,
            presentation: presentation,
            playerBottom: playerBottom,
            toast: toasts.add,
          ),
        ),
      ),
    );
  }

  /// Opens the bar, and the keyboard rises to [height] as the field takes focus.
  Future<void> open(WidgetTester tester, {double height = 336}) async {
    session.openSend();
    await tester.pump();
    await tester.pump();
    keyboard.value = height;
    await tester.pump();
  }

  final bar = find.byKey(const ValueKey('danmaku-send-bar'));
  final input = find.byKey(const ValueKey('danmaku-send-input'));
  final style = find.byKey(const ValueKey('danmaku-send-style'));
  final panel = find.byKey(const ValueKey('danmaku-style-panel'));
  final dim = find.byKey(const ValueKey('danmaku-send-dim'));
  final send = find.byKey(const ValueKey('danmaku-send-button'));
  final hint = find.byKey(const ValueKey('danmaku-send-hint'));

  bool focused(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

  testWidgets('nothing shows, and touches pass, until the bar opens', (tester) async {
    await pumpLayer(tester);
    expect(bar, findsNothing);
    expect(dim, findsNothing);

    await open(tester);
    expect(bar, findsOneWidget);
    expect(focused(tester), isTrue, reason: 'the field takes focus at once, bringing the keyboard');
  });

  testWidgets('the bar rides on the keyboard', (tester) async {
    await pumpLayer(tester);
    await open(tester, height: 336);
    expect(tester.getRect(bar).bottom, moreOrLessEquals(portrait.height - 336));

    keyboard.value = 200;
    await tester.pump();
    expect(tester.getRect(bar).bottom, moreOrLessEquals(portrait.height - 200));
  });

  testWidgets('with no keyboard (Windows) the bar sits at the bottom', (tester) async {
    await pumpLayer(tester, presentation: Presentation.landscape);
    session.openSend();
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(bar).bottom, landscape.height);
  });

  testWidgets("A swaps the keyboard for the style panel at the keyboard's height, and back", (tester) async {
    await pumpLayer(tester);
    await open(tester, height: 336);

    await tester.tap(style);
    await tester.pump();
    expect(focused(tester), isFalse);
    keyboard.value = 0;
    await tester.pump();
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).height, 336);
    expect(tester.getRect(bar).bottom, moreOrLessEquals(portrait.height - 336), reason: 'the bar stays put');

    await tester.tap(style);
    await tester.pump();
    expect(focused(tester), isTrue);
    expect(panel, findsOneWidget, reason: 'the panel waits for the keyboard to cover it');
    keyboard.value = 336;
    await tester.pump();
    await tester.pump();
    expect(panel, findsNothing);
    expect(tester.getRect(bar).bottom, moreOrLessEquals(portrait.height - 336));
  });

  testWidgets('tapping the field brings the keyboard back over the panel', (tester) async {
    await pumpLayer(tester, presentation: Presentation.landscape);
    await open(tester, height: 224);
    await tester.tap(style);
    await tester.pump();
    keyboard.value = 0;
    await tester.pump();
    expect(panel, findsOneWidget);

    await tester.tap(input);
    await tester.pump();
    expect(focused(tester), isTrue);
    keyboard.value = 224;
    await tester.pump();
    await tester.pump();
    expect(panel, findsNothing);
  });

  testWidgets('with a hardware keyboard the panel gives way after a while', (tester) async {
    await pumpLayer(tester);
    await open(tester, height: 336);
    await tester.tap(style);
    await tester.pump();
    keyboard.value = 0;
    await tester.pump();

    await tester.tap(style);
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();
    expect(panel, findsNothing);
  });

  testWidgets('before any keyboard, the panel takes the official height', (tester) async {
    await pumpLayer(tester, presentation: Presentation.landscape);
    session.openSend();
    await tester.pump();
    await tester.pump();
    await tester.tap(style);
    await tester.pump();
    expect(tester.getSize(panel).height, 224);
  });

  testWidgets('the panel offers 置底 in landscape only', (tester) async {
    await pumpLayer(tester, presentation: Presentation.landscape);
    await open(tester, height: 224);
    await tester.tap(style);
    await tester.pump();
    keyboard.value = 0;
    await tester.pump();
    expect(find.text('置底'), findsOneWidget);
  });

  for (final presentation in [Presentation.inline, Presentation.vertical]) {
    testWidgets('no 置底 in the ${presentation.name} panel', (tester) async {
      await pumpLayer(tester, presentation: presentation);
      await open(tester);
      await tester.tap(style);
      await tester.pump();
      keyboard.value = 0;
      await tester.pump();
      expect(panel, findsOneWidget);
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('置底'), findsNothing);
    });
  }

  testWidgets("A's red dot goes for good once A is pressed", (tester) async {
    await pumpLayer(tester);
    await open(tester);
    expect(hint, findsOneWidget);
    await tester.tap(style);
    await tester.pump();
    expect(PlayerPrefs.shared.danmakuStyleHintSeen, isTrue);

    session.closeSend();
    await tester.pump();
    await open(tester);
    expect(hint, findsNothing);
  });

  testWidgets('会员 without 大会员 toasts and keeps the colour', (tester) async {
    await pumpLayer(tester);
    await open(tester);
    await tester.tap(style);
    await tester.pump();
    keyboard.value = 0;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('danmaku-style-vip')));
    expect(toasts, ['开通大会员后可使用']);
    expect(session.sender.style.gradient, isFalse);
  });

  testWidgets('on the small player the page under the player dims, and a tap there closes, keeping the draft', (
    tester,
  ) async {
    await pumpLayer(tester);
    await open(tester);
    await tester.enterText(input, '还没写完');
    await tester.pump();
    expect(tester.getRect(dim).top, playerBottom);

    await tester.tapAt(const Offset(220, playerBottom - 20));
    await tester.pump();
    expect(session.sendOpen.value, isTrue, reason: 'the player above the dim is not part of it');

    await tester.tapAt(const Offset(220, playerBottom + 40));
    await tester.pump();
    expect(session.sendOpen.value, isFalse);
    expect(bar, findsNothing);

    await open(tester);
    expect(find.text('还没写完'), findsOneWidget);
  });

  for (final presentation in [Presentation.landscape, Presentation.vertical]) {
    testWidgets('in ${presentation.name} a tap above the bar closes', (tester) async {
      await pumpLayer(tester, presentation: presentation);
      await open(tester, height: 224);
      await tester.tapAt(const Offset(200, 40));
      await tester.pump();
      expect(session.sendOpen.value, isFalse);
    });
  }

  testWidgets('the dim answers an accessibility press to close', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLayer(tester);
    await open(tester);
    expect(tester.getSemantics(dim), isSemantics(label: '关闭', isButton: true, hasTapAction: true));
    tester.semantics.tap(find.semantics.byLabel('关闭'));
    await tester.pump();
    expect(session.sendOpen.value, isFalse);
    semantics.dispose();
  });

  testWidgets('a sent danmaku closes the bar and clears the draft', (tester) async {
    await pumpLayer(tester);
    await open(tester);
    await tester.enterText(input, '  前方高能 ');
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
    expect(posted, ['前方高能']);
    expect(toasts, isEmpty);
    expect(session.sendOpen.value, isFalse);
    expect(session.sender.text, isEmpty);
  });

  testWidgets("a refusal is toasted, and the bar stays with the draft", (tester) async {
    session.post = (text, style) async => '弹幕发送过于频繁';
    await pumpLayer(tester);
    await open(tester);
    await tester.enterText(input, '再来');
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
    expect(toasts, ['弹幕发送过于频繁']);
    expect(session.sendOpen.value, isTrue);
    expect(find.text('再来'), findsOneWidget);
  });

  testWidgets('a second press while it is out sends nothing more', (tester) async {
    final answer = Completer<String?>();
    var calls = 0;
    session.post = (text, style) {
      calls++;
      return answer.future;
    };
    await pumpLayer(tester);
    await open(tester);
    await tester.enterText(input, '一条');
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
    await tester.tap(send);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(calls, 1);

    answer.complete(null);
    await tester.pump();
    expect(session.sendOpen.value, isFalse);
  });
}
