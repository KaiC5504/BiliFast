import 'dart:math' as math;

import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stand_in_fonts.dart';

/// A line holding Latin and Chinese, and one of Chinese alone, each a single short line.
const mixedLine = 'KaiC5504 设置';
const chineseLine = '设置版本设置';

/// Long enough to wrap to at least two lines anywhere they are shown.
final mixedLines = 'KaiC 设置 Wi-Fi 版本 ' * 12;
final chineseLines = '设置版本设置版本' * 12;

/// The app's theme (main.dart's): the page's Material gives text its height and the system font's fallback.
ThemeData appTheme() =>
    ThemeData(fontFamily: BiliFonts.family, fontFamilyFallback: BiliFonts.fallback, textTheme: BiliFonts.untracked);

/// [child] on a Material page in the app's theme.
Widget appHost(Widget child) => MaterialApp(
  theme: appTheme(),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(440, 956), disableAnimations: true),
    child: Material(child: child),
  ),
);

/// The system font for this test, with the stand-ins for SF and PingFang loaded and the view the phone's size.
Future<void> useSystemFont(WidgetTester tester) async {
  final saved = BiliFonts.family;
  addTearDown(() => BiliFonts.family = saved);
  BiliFonts.family = BiliFonts.system;
  await tester.runAsync(loadSystemFontStandIns);
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Each line's baseline on screen for the text [text] finds, laid out as drawn: the same text, constraints and strut
/// (none for [strut] false) as the paragraph, or the field for an [EditableText].
List<double> baselinesOf(WidgetTester tester, Finder text, {bool strut = true}) {
  final RenderBox box;
  final TextPainter painter;
  if (tester.widget(text) is EditableText) {
    final editable = tester.state<EditableTextState>(text).renderEditable;
    box = editable;
    painter = TextPainter(
      text: editable.text,
      strutStyle: strut ? editable.strutStyle : null,
      textScaler: editable.textScaler,
      maxLines: editable.maxLines,
      textAlign: editable.textAlign,
      textDirection: editable.textDirection,
      locale: editable.locale,
      textHeightBehavior: editable.textHeightBehavior,
      textWidthBasis: editable.textWidthBasis,
    )..layout(maxWidth: editable.maxLines == 1 ? double.infinity : editable.constraints.maxWidth);
  } else {
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final ellipsis = paragraph.overflow == TextOverflow.ellipsis;
    box = paragraph;
    painter = TextPainter(
      text: paragraph.text,
      strutStyle: strut ? paragraph.strutStyle : null,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      ellipsis: ellipsis ? '…' : null,
      textAlign: paragraph.textAlign,
      textDirection: paragraph.textDirection,
      locale: paragraph.locale,
      textHeightBehavior: paragraph.textHeightBehavior,
      textWidthBasis: paragraph.textWidthBasis,
    )..layout(maxWidth: paragraph.softWrap || ellipsis ? paragraph.constraints.maxWidth : double.infinity);
  }
  final top = box.localToGlobal(Offset.zero).dy;
  final baselines = [for (final line in painter.computeLineMetrics()) top + line.baseline];
  painter.dispose();
  return baselines;
}

/// The mixed text's lines sit where the Chinese text's did, line for line (as many as both have, and both wrap or
/// neither does); without its strut the first would be off it.
void expectOnChineseLines(WidgetTester tester, Finder mixed, List<double> chinese) {
  final lines = baselinesOf(tester, mixed);
  expect(lines.length > 1, chinese.length > 1, reason: 'both wrap or neither does: $lines $chinese');
  for (var i = 0; i < math.min(lines.length, chinese.length); i++) {
    expect(lines[i], closeTo(chinese[i], 0.01), reason: 'line ${i + 1}');
  }
  expect((baselinesOf(tester, mixed, strut: false).first - chinese.first).abs(), greaterThan(0.01));
}

/// The text [text] finds, which mixes scripts, sits where Chinese in its style would in its place: one line, or as
/// many as it wraps to.
void expectOnChineseLine(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final wraps = baselinesOf(tester, text).length > 1;
  final painter = TextPainter(
    text: TextSpan(text: wraps ? chineseLines : chineseLine, style: paragraph.text.style),
    textScaler: paragraph.textScaler,
    maxLines: paragraph.maxLines,
    textDirection: TextDirection.ltr,
    textHeightBehavior: paragraph.textHeightBehavior,
  )..layout(maxWidth: wraps ? paragraph.constraints.maxWidth : double.infinity);
  final top = paragraph.localToGlobal(Offset.zero).dy;
  final chinese = [for (final line in painter.computeLineMetrics()) top + line.baseline];
  painter.dispose();
  expectOnChineseLines(tester, text, chinese);
}

/// Shows [chinese] then [mixed] through [show] and expects the mixed text on the Chinese text's lines.
Future<void> expectMixedOnChineseLines(
  WidgetTester tester, {
  required Future<void> Function(String text) show,
  String chinese = chineseLine,
  String mixed = mixedLine,
  Finder Function(String text)? finder,
}) async {
  final locate = finder ?? find.text;
  await show(chinese);
  final lines = baselinesOf(tester, locate(chinese), strut: false);
  await show(mixed);
  expectOnChineseLines(tester, locate(mixed), lines);
}
