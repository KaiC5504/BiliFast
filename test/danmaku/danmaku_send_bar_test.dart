import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilifast/danmaku/send/danmaku_send_bar.dart';
import 'package:bilifast/danmaku/send/danmaku_send_model.dart';
import 'package:bilifast/danmaku/send/danmaku_style_panel.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart' show MaterialApp, TextField, ThemeData;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/text_lines.dart';

void main() {
  late DanmakuSendModel model;
  late PlayerPrefs prefs;
  late FocusNode focus;
  late int styles;
  late int sends;

  setUp(() {
    prefs = PlayerPrefs.memory();
    model = DanmakuSendModel((text, style) async => null, prefs: prefs);
    focus = FocusNode();
    styles = 0;
    sends = 0;
  });

  tearDown(() {
    model.dispose();
    focus.dispose();
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    Presentation presentation = Presentation.inline,
    bool styleShown = false,
    bool closed = false,
    ThemeData? theme,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Align(
        alignment: Alignment.bottomCenter,
        child: RepaintBoundary(
          key: const ValueKey('danmaku-send-shot'),
          child: DanmakuSendBar(
            model: model,
            presentation: presentation,
            focusNode: focus,
            styleShown: styleShown,
            closed: closed,
            onStyle: () => styles++,
            onSend: () => sends++,
          ),
        ),
      ),
    ),
  );

  final input = find.byKey(const ValueKey('danmaku-send-input'));
  final send = find.byKey(const ValueKey('danmaku-send-button'));
  final clear = find.byKey(const ValueKey('danmaku-send-clear'));
  final hint = find.byKey(const ValueKey('danmaku-send-hint'));

  group('the bar', () {
    testWidgets('says 发个友善的弹幕见证当下, and 42 pt tall in every presentation', (tester) async {
      for (final presentation in Presentation.values) {
        await pumpBar(tester, presentation: presentation);
        expect(find.text('发个友善的弹幕见证当下'), findsOneWidget);
        expect(tester.getSize(find.byKey(const ValueKey('danmaku-send-bar'))).height, 42);
      }
    });

    testWidgets('typing reaches the draft, which caps it at 100 characters, and the draft fills the field', (
      tester,
    ) async {
      model.text = '留着的草稿';
      await pumpBar(tester);
      expect(find.text('留着的草稿'), findsOneWidget);

      await tester.enterText(input, '字' * 120);
      expect(model.text, '字' * 100);
    });

    testWidgets('the send arrow works only with text, and answers an accessibility press', (tester) async {
      await pumpBar(tester);
      expect(tester.getSemantics(send), matchesSemantics(label: '发送', isButton: true, hasEnabledState: true));
      await tester.tap(send);
      expect(sends, 0);

      await tester.enterText(input, '前方高能');
      await tester.pump();
      expect(
        tester.getSemantics(send),
        matchesSemantics(label: '发送', isButton: true, hasEnabledState: true, isEnabled: true, hasTapAction: true),
      );
      await tester.tap(send);
      expect(sends, 1);
    });

    testWidgets('the keyboard\'s send key sends too', (tester) async {
      await pumpBar(tester);
      await tester.enterText(input, '前方高能');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(sends, 1);
    });

    testWidgets('ⓧ shows in the light bars while there is text, and clears it', (tester) async {
      for (final presentation in [Presentation.inline, Presentation.vertical]) {
        model.text = '';
        await pumpBar(tester, presentation: presentation);
        expect(clear, findsNothing);
        await tester.enterText(input, 'Hello');
        await tester.pump();
        expect(clear, findsOneWidget);
        await tester.tap(clear);
        await tester.pump();
        expect(model.text, isEmpty);
        expect(clear, findsNothing);
      }

      await pumpBar(tester, presentation: Presentation.landscape);
      await tester.enterText(input, 'Hello');
      await tester.pump();
      expect(clear, findsNothing, reason: "22's dark bar has none");
    });

    testWidgets('A has its red dot until the hint is seen, none while the panel shows, and calls onStyle', (
      tester,
    ) async {
      await pumpBar(tester);
      expect(hint, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('danmaku-send-style')));
      expect(styles, 1);

      await pumpBar(tester, styleShown: true);
      expect(hint, findsNothing);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('danmaku-send-style'))),
        matchesSemantics(label: '弹幕样式', isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true),
      );

      model.sawStyleHint();
      await pumpBar(tester);
      expect(hint, findsNothing);
    });

    testWidgets('closed by the uploader, the field says so and takes no text; a press is left to onSend to refuse', (
      tester,
    ) async {
      model.text = '发不出去';
      await pumpBar(tester, closed: true);
      model.text = '';
      await tester.pump();
      expect(find.text('UP主已关闭弹幕'), findsOneWidget);
      expect(tester.widget<TextField>(input).readOnly, isTrue);
      model.text = '发不出去';
      await tester.pump();
      expect(clear, findsNothing);
      await tester.tap(send);
      expect(sends, 1);
    });

    testWidgets('under the system font, UP主已关闭弹幕 and typed text with Latin sit on the Chinese placeholder\'s line', (
      tester,
    ) async {
      await useSystemFont(tester);
      double han(Finder finder) => linesOf(tester, finder).han.first;
      final field = find.descendant(of: input, matching: find.byType(EditableText));
      await pumpBar(tester, theme: appTheme());
      final placeholder = han(find.text('发个友善的弹幕见证当下'));
      await tester.enterText(input, '设置版本');
      await tester.pump();
      expect(han(field), closeTo(placeholder, 0.01));
      await tester.enterText(input, 'KaiC 设置');
      await tester.pump();
      expect(han(field), closeTo(placeholder, 0.01));
      await tester.enterText(input, '');
      await pumpBar(tester, theme: appTheme(), closed: true);
      await tester.pump();
      expect(han(find.text('UP主已关闭弹幕')), closeTo(placeholder, 0.01));
    });
  });

  group('typing pinyin', () {
    TextEditingValue composing(String committed, String pinyin) => TextEditingValue(
      text: committed + pinyin,
      composing: TextRange(start: committed.length, end: committed.length + pinyin.length),
      selection: TextSelection.collapsed(offset: committed.length + pinyin.length),
    );

    TextEditingValue committed(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

    TextEditingValue field(WidgetTester tester) => tester.widget<TextField>(input).controller!.value;

    bool sendEnabled(WidgetTester tester) =>
        isSemantics(isEnabled: true).matches(tester.getSemantics(send), <dynamic, dynamic>{});

    testWidgets('past the cap keeps its candidates, and the cut comes once it is committed', (tester) async {
      model.text = '字' * 97;
      await pumpBar(tester);
      await tester.showKeyboard(input);

      tester.testTextInput.updateEditingValue(composing('字' * 97, 'zhongwenzi'));
      await tester.pump();
      expect(model.text, '字' * 97, reason: 'the composition stays out of the draft');
      expect(field(tester).text, '${'字' * 97}zhongwenzi');
      expect(field(tester).composing.isValid, isTrue, reason: 'the candidates stay');

      tester.testTextInput.updateEditingValue(committed('${'字' * 97}中文字词'));
      await tester.pump();
      expect(model.text, '${'字' * 97}中文字');
      expect(field(tester).text, '${'字' * 97}中文字');
    });

    testWidgets('below the cap stays out of the draft and cannot be sent until it is committed', (tester) async {
      await pumpBar(tester);
      await tester.showKeyboard(input);

      tester.testTextInput.updateEditingValue(composing('', 'ni'));
      await tester.pump();
      expect(model.text, isEmpty);
      expect(sendEnabled(tester), isFalse);
      await tester.tap(send);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(sends, 0);

      tester.testTextInput.updateEditingValue(committed('你'));
      await tester.pump();
      expect(model.text, '你');
      expect(sendEnabled(tester), isTrue);
      await tester.tap(send);
      expect(sends, 1);
    });

    testWidgets('after committed text, keeps send off and outlasts the draft notifying', (tester) async {
      model.text = '前方';
      await pumpBar(tester);
      await tester.showKeyboard(input);

      tester.testTextInput.updateEditingValue(composing('前方', 'gao'));
      await tester.pump();
      expect(sendEnabled(tester), isFalse);
      model.style = model.style.copyWith(size: DanmakuSize.small);
      await tester.pump();
      expect(field(tester).text, '前方gao');
      expect(field(tester).composing.isValid, isTrue);

      await tester.tap(clear);
      await tester.pump();
      expect(field(tester).text, isEmpty, reason: 'ⓧ clears the composition too');
      expect(model.text, isEmpty);
    });
  });

  group('the placeholder in MiSans', () {
    setUpAll(() async {
      final bytes = File('assets/fonts/MiSans-Regular.ttf').readAsBytesSync();
      await (FontLoader(BiliFonts.miSans)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });

    /// Where the placeholder's ink ends, in points, read off the bar drawn at 3x.
    Future<double> inkEnd(WidgetTester tester, Presentation presentation, Size size, {double left = 0}) async {
      tester.view
        ..physicalSize = size * 3
        ..devicePixelRatio = 3
        ..padding = FakeViewPadding(left: left * 3);
      addTearDown(tester.view.reset);
      await pumpBar(tester, presentation: presentation);
      final shot = find.byKey(const ValueKey('danmaku-send-shot'));
      final pixels = await tester.runAsync(() async {
        final image = await tester.renderObject<RenderRepaintBoundary>(shot).toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return (image.width, data!);
      });
      final (width, data) = pixels!;
      final origin = tester.getTopLeft(shot);
      final field = tester.getRect(find.byKey(const ValueKey('danmaku-send-field'))).shift(-origin);
      final threshold = presentation == Presentation.vertical ? 200 : 225;
      // The pill's straight run short of where the ⓧ would be, so neither its round ends nor the bar count.
      final top = (field.top * 3).round() + 6;
      final bottom = (field.bottom * 3).round() - 6;
      final from = ((field.left + field.height / 2) * 3).round();
      final to = ((field.right - field.height) * 3).round();
      var end = -1;
      for (var y = top; y < bottom; y++) {
        for (var x = from; x < to; x++) {
          final i = (y * width + x) * 4;
          final grey = (data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2)) / 3;
          if (grey < threshold && x > end) end = x;
        }
      }
      return origin.dx + (end + 1) / 3;
    }

    testWidgets("ends where 22's does in landscape", (tester) async {
      expect(await inkEnd(tester, Presentation.landscape, const Size(956, 440), left: 62), closeTo(274.3, 0.5));
    });

    testWidgets("ends where 36's does in 竖屏", (tester) async {
      expect(await inkEnd(tester, Presentation.vertical, const Size(440, 956)), closeTo(200.7, 0.5));
    });
  });

  group('the style panel', () {
    late List<String> refused;

    Future<void> pumpPanel(WidgetTester tester, {bool dark = true, bool offerBottom = true, bool vip = false}) {
      refused = [];
      return tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 347,
              child: DanmakuStylePanel(
                model: model,
                dark: dark,
                offerBottom: offerBottom,
                isVip: vip,
                onVipOnly: () => refused.add('开通大会员后可使用'),
              ),
            ),
          ),
        ),
      );
    }

    Finder key(String name) => find.byKey(ValueKey('danmaku-style-$name'));

    bool selected(WidgetTester tester, String name) =>
        isSemantics(isSelected: true).matches(tester.getSemantics(key(name)), {});

    testWidgets('starts on 默认, 滚动 and white, marked as chosen', (tester) async {
      await pumpPanel(tester);
      expect(selected(tester, 'size-normal'), isTrue);
      expect(selected(tester, 'size-small'), isFalse);
      expect(selected(tester, 'position-scroll'), isTrue);
      expect(selected(tester, 'colour-0'), isTrue);
      expect(find.byKey(const ValueKey('danmaku-style-tick')), findsOneWidget);
      for (final label in ['弹幕字号', '弹幕类型', '弹幕颜色', '默认', '较小', '滚动', '置顶', '置底']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('each option sets the style', (tester) async {
      await pumpPanel(tester);
      await tester.tap(key('size-small'));
      await tester.pump();
      expect(model.style.size, DanmakuSize.small);
      expect(selected(tester, 'size-small'), isTrue);
      await tester.tap(key('size-normal'));
      expect(model.style.size, DanmakuSize.normal);

      for (final position in [DanmakuPosition.top, DanmakuPosition.bottom, DanmakuPosition.scroll]) {
        await tester.tap(key('position-${position.name}'));
        await tester.pump();
        expect(model.style.position, position);
        expect(selected(tester, 'position-${position.name}'), isTrue);
      }

      for (var index = 0; index < DanmakuStyle.colors.length; index++) {
        await tester.tap(key('colour-$index'));
        await tester.pump();
        expect(model.style.color, DanmakuStyle.colors[index]);
        expect(selected(tester, 'colour-$index'), isTrue);
        expect(find.byKey(const ValueKey('danmaku-style-tick')), findsOneWidget);
      }
    });

    testWidgets('portrait has no 置底, and shows the colours in two rows', (tester) async {
      tester.view
        ..physicalSize = const Size(440, 956) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpPanel(tester, dark: false, offerBottom: false);
      expect(key('position-bottom'), findsNothing);
      expect(find.text('置底'), findsNothing);
      final white = tester.getCenter(key('colour-0'));
      final firstOfSecondRow = tester.getCenter(key('colour-6'));
      expect(firstOfSecondRow.dx, moreOrLessEquals(white.dx, epsilon: 0.01));
      expect(firstOfSecondRow.dy - white.dy, moreOrLessEquals(44, epsilon: 0.01));
    });

    testWidgets('landscape keeps the colours on one row', (tester) async {
      tester.view
        ..physicalSize = const Size(956, 440) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpPanel(tester);
      final ys = {
        for (var index = 0; index < DanmakuStyle.colors.length; index++) tester.getCenter(key('colour-$index')).dy,
      };
      expect(ys, hasLength(1));
    });

    testWidgets('会员 is refused without 大会员, and the colour stays', (tester) async {
      await pumpPanel(tester);
      await tester.tap(key('colour-3'));
      await tester.tap(key('vip'));
      await tester.pump();
      expect(refused, ['开通大会员后可使用']);
      expect(model.style.gradient, isFalse);
      expect(model.style.color, DanmakuStyle.colors[3]);
      expect(selected(tester, 'colour-3'), isTrue);
    });

    testWidgets('会员 picks the gradient for 大会员, on white', (tester) async {
      await pumpPanel(tester, vip: true);
      await tester.tap(key('colour-3'));
      await tester.tap(key('vip'));
      await tester.pump();
      expect(refused, isEmpty);
      expect(model.style.gradient, isTrue);
      expect(model.style.color, 0xFFFFFF);
      expect(selected(tester, 'vip'), isTrue);
      expect(selected(tester, 'colour-0'), isFalse);
    });
  });
}
