import 'package:bili_core/api.dart' show QualityOption;
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'landscape_chrome_test.dart' show Rig;

final _hiRes = find.byKey(const ValueKey('landscape-hi-res'));
final _tag = find.byKey(const ValueKey('landscape-hi-res-tag'));
final _speed = find.byKey(const ValueKey('landscape-speed'));
final _quality = find.byKey(const ValueKey('landscape-quality'));
final _words = find.descendant(of: _hiRes, matching: find.byType(Text)).first;

Future<Rig> mount(WidgetTester tester, {bool offered = true, bool on = false}) async {
  final rig = Rig();
  rig.session
    ..qualities = const [QualityOption(id: 120, name: '4K 超清')]
    ..quality = 120
    ..hiResOffered = offered
    ..hiResOn = on;
  await rig.mount(tester);
  return rig;
}

Color? colorOf(WidgetTester tester) => tester.widget<Text>(_words).style!.color;

void main() {
  testWidgets('Hi-Res无损 shows only while the part offers it, between 倍速 and the quality as on 274', (tester) async {
    final rig = await mount(tester, offered: false);
    expect(_hiRes, findsNothing);

    rig.session
      ..hiResOffered = true
      ..changed();
    await tester.pump();
    expect(find.descendant(of: _hiRes, matching: find.text('Hi-Res无损')), findsOne);
    final speed = tester.getRect(_speed), hiRes = tester.getRect(_hiRes), quality = tester.getRect(_quality);
    expect(hiRes.left - speed.right, closeTo(HiResButtonTheme.gap, 0.01));
    expect(quality.left - hiRes.right, closeTo(HiResButtonTheme.qualityGap, 0.01));
    expect(hiRes.center.dy, closeTo(quality.center.dy, 0.01));
  });

  testWidgets("without it the row keeps 04's spacing, and with it the quality stays put and 倍速 moves over", (
    tester,
  ) async {
    final rig = await mount(tester, offered: false);
    final speed = tester.getRect(_speed), quality = tester.getRect(_quality);
    expect(quality.left - speed.right, closeTo(BiliMetrics.chromeQualityGap, 0.01));

    rig.session
      ..hiResOffered = true
      ..changed();
    await tester.pump();
    expect(tester.getRect(_quality), quality);
    expect(tester.getRect(_speed).width, speed.width);
    expect(
      speed.left - tester.getRect(_speed).left,
      closeTo(
        tester.getRect(_hiRes).width + HiResButtonTheme.gap + HiResButtonTheme.qualityGap - BiliMetrics.chromeQualityGap,
        0.01,
      ),
    );

    rig.session
      ..hiResOffered = false
      ..changed();
    await tester.pump();
    expect(tester.getRect(_speed), speed, reason: "04's row comes back as it was");
    expect(tester.getRect(_quality), quality);
  });

  testWidgets('white while off and #FB7299 while on, its 大会员 tag in the same colour, outlined to match', (
    tester,
  ) async {
    final rig = await mount(tester);
    expect(colorOf(tester), BiliColors.onVideo);
    var tag = tester.widget<QualityTag>(_tag);
    expect(tag.text, '大会员');
    expect(tag.color, BiliColors.onVideo);
    expect(tag.line, BiliMetrics.chromeTagLine);

    rig.session
      ..hiResOn = true
      ..changed();
    await tester.pump();
    expect(colorOf(tester), HiResButtonTheme.on);
    expect(HiResButtonTheme.on, BiliColors.verticalPink);
    tag = tester.widget<QualityTag>(_tag);
    expect(tag.color, HiResButtonTheme.on);
    expect(tag.line, HiResButtonTheme.tagLineOn);
    expect(tag.pad, HiResButtonTheme.tagPad);
  });

  testWidgets('a tap turns it on and off through the session and keeps the controls up', (tester) async {
    final rig = await mount(tester);

    await tester.tap(_hiRes);
    await tester.pump();
    expect(rig.session.calls, ['setHiRes true']);
    expect(colorOf(tester), HiResButtonTheme.on);
    expect(rig.chrome.shows, greaterThan(0));

    await tester.tap(_hiRes);
    await tester.pump();
    expect(rig.session.calls, ['setHiRes true', 'setHiRes false']);
    expect(colorOf(tester), BiliColors.onVideo);
  });

  testWidgets("a failure's text is toasted", (tester) async {
    final rig = await mount(tester);
    rig.session.failure = '切换失败，请稍后重试';

    await tester.tap(_hiRes);
    await tester.pump();
    await tester.pump();
    expect(find.text('切换失败，请稍后重试'), findsOne);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('it presses through accessibility by its name, and VoiceOver hears it on or off', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await mount(tester);
    final node = find.semantics.byLabel('Hi-Res无损');
    Matcher state(bool on) =>
        isSemantics(label: 'Hi-Res无损', isButton: true, hasToggledState: true, isToggled: on, hasTapAction: true);
    expect(tester.getSemantics(_hiRes), state(false));

    tester.semantics.tap(node);
    expect(rig.session.calls, ['setHiRes true']);
    await tester.pump();
    expect(tester.getSemantics(_hiRes), state(true));

    tester.semantics.tap(node);
    expect(rig.session.calls, ['setHiRes true', 'setHiRes false']);
    semantics.dispose();
  });

  testWidgets('the tag sits as 60帧 does over 1080P: its right 8.8 pt past the words, its middle 15.2 pt above; the '
      'words keep their 8 pt pads', (tester) async {
    await mount(tester, on: true);

    final cell = tester.getRect(_hiRes);
    final words = tester.getRect(_words);
    final pill = tester.getRect(_tag);
    expect(words.left - cell.left, closeTo(BiliMetrics.chromeTextPad, 0.01));
    expect(cell.right - words.right, closeTo(BiliMetrics.chromeTextPad, 0.01));
    expect(pill.right - words.right, closeTo(8.8, 0.01));
    expect(words.center.dy - pill.center.dy, closeTo(15.2, 0.01));
    expect(pill.height, BiliMetrics.chromeTagHeight);
  });

  test("a Latin letter running into Chinese stands 1.67 pt off it, as iOS sets 274's Hi-Res无损; digits don't", () {
    final spaced = latinSpacedFromChinese('Hi-Res无损音质已开启');
    expect(spaced.toPlainText(), 'Hi-Res无损音质已开启');
    final parts = spaced.children!.cast<TextSpan>();
    expect([for (final part in parts) part.text], ['Hi-Re', 's', '无损音质已开启']);
    expect(parts[1].style!.letterSpacing, HiResButtonTheme.latinGap);
    expect(parts[0].style, isNull);

    expect(latinSpacedFromChinese('23人正在看').children!.cast<TextSpan>().map((part) => part.text), ['23人正在看']);
    expect(latinSpacedFromChinese('倍速').toPlainText(), '倍速');
  });
}
