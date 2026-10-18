import 'package:bili_core/api.dart' show VideoCard;
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/end_screen_landscape.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

VideoCard card(int n) => VideoCard(
  aid: n,
  bvid: 'BV$n',
  cid: n,
  title: '推荐 $n',
  cover: '',
  duration: 48,
  ownerMid: n,
  ownerName: 'UP $n',
  views: 1357000,
  danmaku: 284,
  likes: 0,
);

/// The end screen at 27's size: 956 × 440 pt, 62 each side, 21 below.
final class Rig {
  final session = FakePlayerSession()..shareLink = Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD');
  final chrome = ChromeState();
  final panels = PanelController();
  final orientation = OrientationController()..enterLandscape();
  final shared = <Uri>[];
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
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(left: 62, right: 62, bottom: 21);
    addTearDown(tester.view.reset);
    addTearDown(() {
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
      session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EndScreenLandscape(ui: ui, share: (link) async => shared.add(link)),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Offset centre(WidgetTester tester, String key) => tester.getCenter(find.byKey(ValueKey(key)));

void main() {
  testWidgets('lays out as 27: back, 重播 | 分享 at the right, then 推荐视频 in a row', (tester) async {
    final rig = Rig()..session.related = [card(1), card(2), card(3), card(4), card(5)];
    await rig.mount(tester);

    expect(tester.takeException(), isNull);
    expect(centre(tester, 'end-back'), within(distance: 1, from: const Offset(83, 22)));
    expect(centre(tester, 'end-replay').dx, closeTo(604, 2));
    expect(centre(tester, 'end-share').dx, closeTo(864.5, 2));
    expect(find.text('推荐视频'), findsOneWidget);
    expect(tester.getTopLeft(find.text('推荐 1')).dx, closeTo(75, 1));
    expect(find.text('0:48'), findsWidgets);
    expect(find.text('135.7万'), findsWidgets);
  });

  testWidgets('重播 replays, back goes back', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-replay')));
    expect(rig.session.calls, ['replay']);
    await tester.tap(find.byKey(const ValueKey('end-back')));
    expect(rig.backs, 1);
  });

  testWidgets('分享 hands the link to the share seam, and is gone without a link', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-share')));
    expect(rig.shared, [Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD')]);

    rig.session
      ..shareLink = null
      ..changed();
    await tester.pump();
    expect(find.byKey(const ValueKey('end-share')), findsNothing);
    expect(centre(tester, 'end-replay').dx, closeTo(604, 2));
  });

  testWidgets('a related video plays on tap; without any, 推荐视频 is not shown', (tester) async {
    final rig = Rig()..session.related = [card(1), card(2)];
    await rig.mount(tester);

    await tester.tap(find.text('推荐 2'));
    expect(rig.session.calls, ['playRelated BV2']);

    rig.session
      ..related = const []
      ..changed();
    await tester.pump();
    expect(find.text('推荐视频'), findsNothing);
  });

  testWidgets('the cards rise in one after another', (tester) async {
    final rig = Rig()..session.related = [card(1), card(2), card(3)];
    tester.view
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() {
      rig.chrome.dispose();
      rig.panels.dispose();
      rig.orientation.dispose();
      rig.session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EndScreenLandscape(ui: rig.ui, share: (_) async {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    double opacityOf(String title) =>
        tester.widget<Opacity>(find.ancestor(of: find.text(title), matching: find.byType(Opacity)).first).opacity;
    expect(opacityOf('推荐 1'), greaterThan(opacityOf('推荐 3')));
    await tester.pumpAndSettle();
    expect(opacityOf('推荐 3'), 1);
  });
}
