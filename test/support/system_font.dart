import 'package:bilifast/shared/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const systemFallback = ['Apple Color Emoji', 'PingFang SC'];

/// The fallback the first paragraph [text] finds is laid out with.
List<String>? fallbackOf(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(text.first).text.style?.fontFamilyFallback;

/// The fallback of the default style around the first [text].
List<String>? defaultFallbackOf(WidgetTester tester, Finder text) =>
    DefaultTextStyle.of(tester.element(text.first)).style.fontFamilyFallback;

/// Shows the widget under the system font, then afresh under MiSans: [text] and the default style around it fall back
/// to emoji, then PingFang SC, only under the system font. The test's theme names no fallback, so the widget has to.
Future<void> expectSystemFallback(WidgetTester tester, Future<void> Function() show, Finder text) async {
  final saved = BiliFonts.family;
  addTearDown(() => BiliFonts.family = saved);
  BiliFonts.family = BiliFonts.system;
  await tester.pumpWidget(const SizedBox.shrink());
  await show();
  expect(fallbackOf(tester, text), systemFallback);
  expect(defaultFallbackOf(tester, text), systemFallback);
  await tester.pumpWidget(const SizedBox.shrink());
  BiliFonts.family = BiliFonts.miSans;
  await show();
  expect(fallbackOf(tester, text), isNull);
  expect(defaultFallbackOf(tester, text), isNull);
}
