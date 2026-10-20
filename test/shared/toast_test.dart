import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/shared/toast.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'text_lines.dart';

const screen = Size(440, 956);

Future<BuildContext> mount(WidgetTester tester, {double keyboard = 0}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (inner) {
          context = inner;
          return const SizedBox.expand();
        },
      ),
    ),
  );
  return context;
}

Future<void> runOut(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('low in the middle of the screen with no keyboard, then gone', (tester) async {
    final context = await mount(tester);
    showToast(context, '最多添加9张图片');
    await tester.pump(const Duration(milliseconds: 200));
    final toast = tester.getRect(find.byKey(const ValueKey('toast')));
    expect(toast.center.dx, screen.width / 2);
    expect(toast.center.dy, greaterThan(screen.height * 0.7));
    expect(toast.bottom, lessThan(screen.height));
    await runOut(tester);
    expect(find.byKey(const ValueKey('toast')), findsNothing);
  });

  testWidgets(
    'its text takes nothing from the root overlay (the monospace w900 of WidgetsApp), and the font fallback',
    (tester) async {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      for (final family in [null, BiliFonts.miSans]) {
        BiliFonts.family = family;
        final context = await mount(tester);
        showToast(context, '已复制');
        await tester.pump(const Duration(milliseconds: 200));
        final style = tester.renderObject<RenderParagraph>(find.text('已复制')).text.style!;
        expect(style.fontFamily, family);
        expect(style.fontFamilyFallback, BiliFonts.fallback);
        expect(style.fontWeight, anyOf(isNull, FontWeight.w400));
        expect(style.fontSize, BiliMetrics.bodyText);
        await runOut(tester);
      }
    },
  );

  testWidgets('above the keyboard when one is up, where it would otherwise be hidden', (tester) async {
    const keyboard = 336.0;
    var context = await mount(tester);
    showToast(context, '发布失败');
    await tester.pump(const Duration(milliseconds: 200));
    final without = tester.getRect(find.byKey(const ValueKey('toast')));
    expect(without.bottom, greaterThan(screen.height - keyboard), reason: 'behind a keyboard, were one up');
    await runOut(tester);

    context = await mount(tester, keyboard: keyboard);
    showToast(context, '发布失败');
    await tester.pump(const Duration(milliseconds: 200));
    final over = tester.getRect(find.byKey(const ValueKey('toast')));
    expect(over.bottom, lessThanOrEqualTo(screen.height - keyboard));
    expect(over.center.dx, screen.width / 2);
    await runOut(tester);
  });

  testWidgets('a new toast replaces the one showing', (tester) async {
    final context = await mount(tester);
    showToast(context, '第一条');
    await tester.pump(const Duration(milliseconds: 100));
    showToast(context, '第二条');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
    await runOut(tester);
  });

  // The toast's style sets no height, so each line already takes PingFang's ascent and descent, which exceed SF's.
  testWidgets('under the system font, a message mixing Latin and Chinese sits on a Chinese one\'s lines', (
    tester,
  ) async {
    await useSystemFont(tester);
    final context = await mount(tester);
    Future<(TextLines, Rect)> show(String message) async {
      showToast(context, message);
      await tester.pump(const Duration(milliseconds: 200));
      return (linesOf(tester, find.text(message)), tester.getRect(find.byKey(const ValueKey('toast'))));
    }

    final (chinese, chineseBox) = await show('评论发布失败请稍后再试评论发布失败请稍后再试评论发布失败请稍后再试');
    final (mixed, mixedBox) = await show('HTTP 412 评论发布失败 HTTP 412 评论发布失败 HTTP 412 评论发布失败');
    expect(chinese.lines.length, 2);
    expect(mixed.lines.length, 2);
    expect(mixedBox.height, chineseBox.height);
    expect(mixed.pitch, closeTo(chinese.pitch, 0.01));
    for (var line = 0; line < 2; line++) {
      expect(mixed.han[line] - mixedBox.top, closeTo(chinese.han[line] - chineseBox.top, 0.01));
    }
    await runOut(tester);
  });
}
