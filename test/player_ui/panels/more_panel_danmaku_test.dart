import 'package:bilifast/player_ui/panels/more_panel.dart';
import 'package:bilifast/shared/custom_icons.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_player_session.dart';

void main() {
  late FakePlayerSession session;
  late int opens;

  setUp(() {
    session = FakePlayerSession();
    opens = 0;
  });

  tearDown(() => session.dispose());

  Future<void> mount(WidgetTester tester, {required bool danmaku}) => tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: MorePanel(
              session: session,
              toast: (_) {},
              close: () {},
              devTools: false,
              openDanmakuSettings: danmaku ? () => opens += 1 : null,
            ),
          ),
        ),
      ),
    ),
  );

  Finder row() => find.byKey(const ValueKey('more-danmaku-settings'));

  testWidgets('弹幕设置 › sits just above 镜像翻转, as on 42 and 43, with its glyph', (tester) async {
    await mount(tester, danmaku: true);

    expect(find.text('弹幕设置'), findsOneWidget);
    expect(find.descendant(of: row(), matching: find.byIcon(CustomIcons.danmakuSettings)), findsOneWidget);
    final settings = tester.getRect(row());
    expect(settings.height, BiliMetrics.panelRowHeight);
    expect(tester.getCenter(find.text('镜像翻转')).dy - settings.center.dy, closeTo(BiliMetrics.panelRowHeight, 0.5));
    expect(tester.getCenter(find.text('循环播放')).dy, lessThan(settings.top));
  });

  testWidgets('a tap or an accessibility press opens 弹幕设置', (tester) async {
    await mount(tester, danmaku: true);

    await tester.tap(row());
    tester.semantics.tap(find.semantics.byLabel('弹幕设置'));
    expect(opens, 2);
  });

  testWidgets('without the callback there is no row and the panel keeps its height', (tester) async {
    await mount(tester, danmaku: false);
    final without = tester.getSize(find.byType(MorePanel)).height;
    expect(row(), findsNothing);
    expect(find.text('弹幕设置'), findsNothing);

    await mount(tester, danmaku: true);
    expect(tester.getSize(find.byType(MorePanel)).height, without + BiliMetrics.panelRowHeight);
  });
}
