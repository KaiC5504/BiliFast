import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/vertical_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

class CountingChrome extends ChromeState {
  int shows = 0;

  @override
  void show() {
    shows += 1;
    super.show();
  }
}

/// 竖屏 on an upright iPhone 17 Pro Max (440 × 956 pt, 62 above for the island, 34 below), the size 09 was taken at.
final class Rig {
  final session = FakePlayerSession();
  final chrome = CountingChrome();
  final panels = PanelController();
  final orientation = OrientationController()..enterVertical();
  int backs = 0;

  late final ui = PlayerUi(
    session: session,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: orientation.controls,
    onBack: () => backs += 1,
  );

  Future<void> mount(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    addTearDown(() {
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
      session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ColoredBox(
          color: Colors.black,
          child: VerticalChrome(ui: ui),
        ),
      ),
    );
  }
}

Offset centre(WidgetTester tester, String key) => tester.getCenter(find.byKey(ValueKey(key)));

void main() {
  testWidgets('lays out as 09: back and ⋮ under the island, the title over the bar, the bottom row', (tester) async {
    final rig = Rig()..session.title = '【VIT赛后】我们接受了LOUD的回溯！！';
    await rig.mount(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('【VIT赛后】我们接受了LOUD的回溯！！'), findsOneWidget);
    expect(centre(tester, 'vertical-back'), within(distance: 1, from: const Offset(22, 76)));
    expect(centre(tester, 'vertical-more'), within(distance: 1, from: const Offset(418, 76)));
    expect(centre(tester, 'vertical-detail'), within(distance: 1, from: const Offset(368, 900)));
    expect(centre(tester, 'vertical-landscape'), within(distance: 1, from: const Offset(413, 900)));
    expect(centre(tester, 'vertical-danmaku'), within(distance: 1, from: const Offset(318, 900)));
    expect(centre(tester, 'vertical-bar').dy, closeTo(871, 1));
    expect(tester.getTopLeft(find.byKey(const ValueKey('vertical-bar'))).dx, 12);
    expect(tester.getTopRight(find.byKey(const ValueKey('vertical-bar'))).dx, 428);
    expect(tester.getTopLeft(find.byKey(const ValueKey('vertical-title'))).dx, 12);
    // The title stops short of where the action column goes.
    expect(tester.getTopRight(find.byKey(const ValueKey('vertical-title'))).dx, lessThanOrEqualTo(378));
    expect(find.text('详情页'), findsOneWidget);
  });

  testWidgets('back and ⋮', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('vertical-back')));
    expect(rig.backs, 1);
    await tester.tap(find.byKey(const ValueKey('vertical-more')));
    expect(rig.panels.value, PlayerPanel.more);
    expect(rig.chrome.shows, 1);
  });

  testWidgets('详情页 goes back to the page and 横屏全屏 to landscape', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('vertical-detail')));
    expect(rig.orientation.presentation, Presentation.inline);
    expect(rig.chrome.shows, 1);

    rig.orientation.enterVertical();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('vertical-landscape')));
    expect(rig.orientation.presentation, Presentation.landscape);
    expect(rig.chrome.shows, 2);
  });

  testWidgets('弹 turns danmaku off and on and says which way it will go', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.bySemanticsLabel('关闭弹幕'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('vertical-danmaku')));
    await tester.pumpAndSettle();
    expect(rig.session.calls, ['setDanmakuOn false']);
    expect(find.bySemanticsLabel('开启弹幕'), findsOneWidget);
  });

  testWidgets('the bar scrubs and seeks', (tester) async {
    final rig = Rig();
    rig.session.duration.value = 100;
    await rig.mount(tester);

    await tester.dragFrom(centre(tester, 'vertical-bar'), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(rig.session.calls.first, startsWith('scrub'));
    expect(rig.session.calls.last, startsWith('commitSeek'));
    expect(rig.chrome.shows, 1);
  });

  testWidgets('hidden controls fade out and take no touches; a panel hides them too', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    final root = find.byKey(const ValueKey('vertical-chrome'));

    rig.chrome.hide();
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isTrue);
    final fades = tester.widgetList<AnimatedOpacity>(find.descendant(of: root, matching: find.byType(AnimatedOpacity)));
    expect(fades.map((fade) => fade.opacity), everyElement(0));
    await tester.tap(find.byKey(const ValueKey('vertical-detail')), warnIfMissed: false);
    expect(rig.orientation.presentation, Presentation.vertical);

    rig.chrome.show();
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isFalse);

    rig.panels.open(PlayerPanel.more);
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isTrue);
  });
}
