import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/page_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PageTabsController tabs;
  late List<String> calls;

  setUp(() {
    tabs = PageTabsController();
    calls = [];
  });

  tearDown(() => tabs.dispose());

  Future<void> host(WidgetTester tester, {bool on = true, bool inputOpen = false, bool closed = false}) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(440, 956), disableAnimations: true),
          child: Scaffold(
            body: PageTabRow(
              controller: tabs,
              replyCount: 1835,
              danmakuOn: on,
              onToggleDanmaku: () => calls.add('toggle'),
              onSendDanmaku: () => calls.add('send'),
              danmakuInputOpen: inputOpen,
              danmakuClosed: closed,
            ),
          ),
        ),
      ),
    );
  }

  Finder send() => find.byKey(const ValueKey('danmaku-send'));

  testWidgets('点我发弹幕 opens the send bar, by a tap or an accessibility press', (tester) async {
    await host(tester);
    expect(find.text('点我发弹幕'), findsOneWidget);

    await tester.tap(send());
    tester.semantics.tap(find.semantics.byLabel('点我发弹幕'));
    expect(calls, ['send', 'send']);
  });

  testWidgets('while the send bar is up it reads 弹幕输入中 in the same place, as on 39', (tester) async {
    await host(tester);
    final idle = tester.getCenter(find.text('点我发弹幕'));

    await host(tester, inputOpen: true);
    await tester.pumpAndSettle();
    expect(find.text('弹幕输入中'), findsOneWidget);
    expect(find.text('点我发弹幕'), findsNothing);
    expect(tester.getCenter(find.text('弹幕输入中')), idle);
    expect(
      tester.getRect(find.byKey(const ValueKey('danmaku-capsule'))).width,
      PageTheme.danmakuFieldWidth + PageTheme.danmakuToggleOn,
    );
  });

  testWidgets('with the uploader\'s danmaku closed it reads UP主已关闭弹幕, fits the field and sends nothing', (
    tester,
  ) async {
    await host(tester, closed: true);
    final text = find.text('UP主已关闭弹幕');
    expect(text, findsOneWidget);
    expect(tester.getSize(text).width, lessThanOrEqualTo(PageTheme.danmakuFieldWidth));

    await tester.tap(send(), warnIfMissed: false);
    expect(calls, isEmpty);
    expect(tester.getSemantics(send()), isSemantics(label: 'UP主已关闭弹幕', isButton: false));
  });

  testWidgets('with danmaku off the field is gone whatever it would read', (tester) async {
    await host(tester, on: false, inputOpen: true);
    expect(find.bySemanticsLabel('弹幕输入中'), findsNothing);
    await tester.tap(send(), warnIfMissed: false);
    expect(calls, isEmpty);
  });
}
