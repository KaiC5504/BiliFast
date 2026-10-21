import 'package:bili_core/api.dart';
import 'package:bilifast/search/results/result_more_sheet.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home/fake_login_gate.dart';
import 'results_support.dart';

void main() {
  late FakePageApi api;
  late FakeLoginGate gate;
  late int closes;

  setUp(() {
    api = FakePageApi();
    gate = FakeLoginGate();
    closes = 0;
  });

  Future<void> show(WidgetTester tester, {bool loggedIn = true}) async {
    final services = await resultServices(loggedIn: loggedIn, api: api, gate: gate);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpInApp(
      tester,
      services,
      Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: BiliColors.card)),
          Positioned.fill(
            child: ResultMoreSheet(video: video(3), onClose: () => closes++),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  testWidgets('the sheet sits as 59 has it: 411.33 tall, its card and buttons 16 in', (tester) async {
    await show(tester);
    final sheet = tester.getRect(find.byKey(const ValueKey('search-sheet')));
    expect(sheet.top, closeTo(956 - 411.33, 0.01));
    final card = tester.getRect(find.byKey(const ValueKey('search-sheet-watch-later')));
    expect(card.left, 16);
    expect(card.top, closeTo(563.67, 0.01));
    expect(card.height, closeTo(45.67, 0.01));
    expect(tester.getRect(find.byKey(const ValueKey('search-sheet-不感兴趣'))).top, closeTo(666.67, 0.01));
    expect(tester.getRect(find.byKey(const ValueKey('search-sheet-与搜索词无关'))).left, 224);
    expect(tester.getRect(find.byKey(const ValueKey('search-sheet-相似过多'))).bottom, closeTo(916, 0.01));
    for (final label in ['匹配度反馈', '内容反馈', '内容质量差', '内容过时', '色情低俗', '内容不适', '其他']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('添加至稍后再看 adds it, toasts and closes', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('search-sheet-watch-later')));
    await settle(tester);
    expect(api.calls, ['addToWatchLater aid=1003']);
    expect(find.text('已添加至稍后再看'), findsOneWidget);
    expect(closes, 1);
    await toastGone(tester);
  });

  testWidgets('logged out, 添加至稍后再看 opens the login page and adds nothing', (tester) async {
    await show(tester, loggedIn: false);
    await tester.tap(find.byKey(const ValueKey('search-sheet-watch-later')));
    await settle(tester);
    expect(gate.requests, 1);
    expect(api.calls, isEmpty);
    expect(closes, 1);
  });

  testWidgets('a failed 添加至稍后再看 says why', (tester) async {
    api.failures['addToWatchLater'] = const BiliAPIError(code: 90001, message: '稍后再看已满');
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('search-sheet-watch-later')));
    await settle(tester);
    expect(find.text('稍后再看已满'), findsOneWidget);
    expect(closes, 1);
    await toastGone(tester);
  });

  testWidgets('a feedback button toasts 暂未开放 and closes', (tester) async {
    for (final label in ['不感兴趣', '其他']) {
      closes = 0;
      await show(tester);
      await tester.tap(find.byKey(ValueKey('search-sheet-$label')));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      await settle(tester);
      expect(closes, 1, reason: label);
      await toastGone(tester);
    }
  });

  testWidgets('the dim closes it', (tester) async {
    await show(tester);
    await tester.tapAt(const Offset(220, 200));
    await settle(tester);
    expect(closes, 1);
    expect(api.calls, isEmpty);
  });

  testWidgets('a drag down closes it; a short one springs back', (tester) async {
    await show(tester);
    await tester.drag(find.text('匹配度反馈'), const Offset(0, 40));
    await settle(tester);
    expect(closes, 0);
    expect(tester.getRect(find.byKey(const ValueKey('search-sheet'))).top, closeTo(956 - 411.33, 0.01));
    await tester.drag(find.text('匹配度反馈'), const Offset(0, 200));
    await settle(tester);
    expect(closes, 1);
  });

  testWidgets('every button answers accessibility presses', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    tester.semantics.tap(find.semantics.byLabel('内容过时'));
    await settle(tester);
    expect(closes, 1);
    await toastGone(tester);
    await show(tester);
    tester.semantics.tap(find.semantics.byLabel('添加至稍后再看'));
    await settle(tester);
    expect(api.calls, ['addToWatchLater aid=1003']);
    await toastGone(tester);
    await show(tester);
    tester.semantics.tap(find.semantics.byLabel('关闭'));
    await settle(tester);
    expect(closes, 3);
    semantics.dispose();
  });
}
