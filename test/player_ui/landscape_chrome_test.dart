import 'package:bili_core/api.dart' show QualityOption;
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/video/player_session.dart';
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

/// The landscape chrome on an iPhone 17 Pro Max turned sideways (956 × 440 pt, the island's 62 pt each side, the
/// home indicator's 21 below), the size 04 was taken at.
final class Rig {
  final session = FakePlayerSession();
  final chrome = CountingChrome();
  final panels = PanelController();
  final orientation = OrientationController()..enterLandscape();
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
        home: ColoredBox(
          color: Colors.black,
          child: LandscapeChrome(ui: ui),
        ),
      ),
    );
  }
}

Offset centre(WidgetTester tester, String key) => tester.getCenter(find.byKey(ValueKey(key)));

void main() {
  testWidgets('lays out as 04: back and ⋮ level at the top, 截图 and the lock on the right, the bottom row', (
    tester,
  ) async {
    final rig = Rig()..session.title = 'Dolby Vision 8K HDR 120FPS';
    await rig.mount(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Dolby Vision 8K HDR 120FPS'), findsOneWidget);
    expect(centre(tester, 'landscape-back').dx, closeTo(89, 1));
    expect(centre(tester, 'landscape-back').dy, closeTo(42, 1));
    expect(centre(tester, 'landscape-more'), within(distance: 1, from: const Offset(867, 42)));
    expect(centre(tester, 'landscape-capture'), within(distance: 1.5, from: const Offset(873, 178.5)));
    expect(centre(tester, 'landscape-lock'), within(distance: 1.5, from: const Offset(873, 231.5)));
    expect(centre(tester, 'landscape-play'), within(distance: 1, from: const Offset(84, 397)));
    expect(centre(tester, 'landscape-danmaku'), within(distance: 1, from: const Offset(133, 397)));
    expect(centre(tester, 'landscape-bar').dy, closeTo(359, 1));
    expect(tester.getTopLeft(find.byKey(const ValueKey('landscape-bar'))).dx, 62);
    expect(tester.getTopRight(find.byKey(const ValueKey('landscape-bar'))).dx, 894);
    expect(tester.getTopLeft(find.byKey(const ValueKey('landscape-time'))).dx, 63);
    // The title stops short of where 点赞…分享 go.
    expect(tester.getTopRight(find.byKey(const ValueKey('landscape-title'))).dx, lessThanOrEqualTo(509));
  });

  testWidgets('back, ⋮, play and the bar do what they say and keep the controls up', (tester) async {
    final rig = Rig();
    rig.session.duration.value = 100;
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('landscape-back')));
    expect(rig.backs, 1);

    await tester.tap(find.byKey(const ValueKey('landscape-play')));
    expect(rig.session.calls, ['togglePlay']);
    expect(rig.chrome.shows, 1);

    await tester.tap(find.byKey(const ValueKey('landscape-more')));
    expect(rig.panels.value, PlayerPanel.more);
    expect(rig.chrome.shows, 2);

    rig.panels.close();
    await tester.pumpAndSettle();
    final bar = find.byKey(const ValueKey('landscape-bar'));
    await tester.dragFrom(tester.getCenter(bar), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(rig.session.calls.where((call) => call.startsWith('scrub')), isNotEmpty);
    expect(rig.session.calls.last, startsWith('commitSeek'));
    expect(rig.chrome.shows, 3);
  });

  testWidgets('the play glyph follows the player and turns to play once the video has ended', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.bySemanticsLabel('播放'), findsOneWidget);

    rig.session.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('暂停'), findsOneWidget);

    rig.session
      ..ended = true
      ..changed();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('播放'), findsOneWidget);
  });

  testWidgets('截图 saves the frame and toasts what came of it; it is gone where frames cannot be captured', (
    tester,
  ) async {
    final rig = Rig()..session.captureResult = const ActionResult('已保存到相册', ok: true);
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('landscape-capture')));
    await tester.pump();
    expect(rig.session.calls, ['captureFrame']);
    expect(find.text('已保存到相册'), findsOneWidget);
    expect(rig.chrome.shows, 1);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('已保存到相册'), findsNothing);

    rig.session
      ..canCaptureFrame = false
      ..changed();
    await tester.pump();
    expect(find.byKey(const ValueKey('landscape-capture')), findsNothing);
    expect(find.byKey(const ValueKey('landscape-lock')), findsOneWidget);
  });

  testWidgets('the lock toggles the rotation lock and says which way it will go; the other controls stay', (
    tester,
  ) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.bySemanticsLabel('锁定屏幕方向'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('landscape-lock')));
    await tester.pumpAndSettle();
    expect(rig.orientation.locked, isTrue);
    expect(find.bySemanticsLabel('解锁屏幕方向'), findsOneWidget);
    expect(rig.chrome.shows, 1);
    for (final key in ['landscape-back', 'landscape-play', 'landscape-bar', 'landscape-speed']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget, reason: key);
    }

    await tester.tap(find.byKey(const ValueKey('landscape-lock')));
    await tester.pumpAndSettle();
    expect(rig.orientation.locked, isFalse);
    expect(find.bySemanticsLabel('锁定屏幕方向'), findsOneWidget);
  });

  testWidgets('弹 turns danmaku off and on', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.bySemanticsLabel('关闭弹幕'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('landscape-danmaku')));
    await tester.pumpAndSettle();
    expect(rig.session.calls, ['setDanmakuOn false']);
    expect(find.bySemanticsLabel('开启弹幕'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('landscape-danmaku')));
    expect(rig.session.calls.last, 'setDanmakuOn true');
  });

  testWidgets('倍速 reads 倍速 at 1× and the rate otherwise, and opens the speed panel', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    final speed = find.byKey(const ValueKey('landscape-speed'));
    expect(find.descendant(of: speed, matching: find.text('倍速')), findsOneWidget);

    for (final (rate, label) in [(1.5, '1.5X'), (1.25, '1.25X'), (2.0, '2.0X'), (0.75, '0.75X')]) {
      await rig.session.setRate(rate);
      await tester.pump();
      expect(
        find.descendant(of: speed, matching: find.text(label)),
        findsOneWidget,
        reason: '$rate',
      );
    }

    await tester.tap(speed);
    expect(rig.panels.value, PlayerPanel.speed);
  });

  testWidgets('the quality button names the quality playing as 04 does, and opens the quality panel', (tester) async {
    final rig = Rig();
    rig.session
      ..qualities = const [QualityOption(id: 120, name: '4K 超清'), QualityOption(id: 80, name: '1080P 高清')]
      ..quality = 120;
    await rig.mount(tester);
    final quality = find.byKey(const ValueKey('landscape-quality'));

    expect(find.descendant(of: quality, matching: find.text('4K')), findsOne);
    // The video tops out below the quality asked for.
    rig.session
      ..playing = 80
      ..changed();
    await tester.pump();
    expect(find.descendant(of: quality, matching: find.text('1080P')), findsOne);

    await tester.tap(quality);
    expect(rig.panels.value, PlayerPanel.quality);
  });

  testWidgets('sizes as 04: the title at 16, 倍速 and the quality at 14, back a full 44 pt target', (tester) async {
    final rig = Rig()..session.title = 'Dolby Vision 8K HDR 120FPS';
    await rig.mount(tester);

    TextStyle styleOf(Finder text) => tester.widget<Text>(text).style!;
    expect(styleOf(find.byKey(const ValueKey('landscape-title'))).fontSize, 16);
    final speed = find.descendant(of: find.byKey(const ValueKey('landscape-speed')), matching: find.byType(Text));
    expect(styleOf(speed).fontSize, 14);
    final quality = find.descendant(of: find.byKey(const ValueKey('landscape-quality')), matching: find.byType(Text));
    expect(styleOf(quality).fontSize, 14);
    expect(tester.getSize(find.byKey(const ValueKey('landscape-back'))), const Size(44, 44));
    // The triangle sits 2.2 pt right of its button's centre, where 04 has it.
    final glyph = find.descendant(of: find.byKey(const ValueKey('landscape-play')), matching: find.byType(CustomPaint));
    expect(tester.getCenter(glyph.last).dx - centre(tester, 'landscape-play').dx, closeTo(2.2, 0.01));
  });

  testWidgets('选集 shows only with episodes, and opens the episodes panel', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('landscape-episodes')), findsNothing);

    rig.session
      ..episodes = const [
        Episode(bvid: 'BV1', cid: 1, title: 'P1', current: true),
        Episode(bvid: 'BV1', cid: 2, title: 'P2', current: false),
      ]
      ..changed();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('landscape-episodes')));
    expect(rig.panels.value, PlayerPanel.episodes);
  });

  testWidgets('the time shows the position against the duration', (tester) async {
    final rig = Rig();
    rig.session.duration.value = 794;
    await rig.mount(tester);
    rig.session.scrub(7);
    await tester.pump();
    expect(find.text('00:07/13:14'), findsOneWidget);
  });

  testWidgets('hidden controls fade out and take no touches; a panel hides them too', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    rig.chrome.hide();
    await tester.pumpAndSettle();
    final root = find.byKey(const ValueKey('landscape-chrome'));
    expect(tester.widget<IgnorePointer>(root).ignoring, isTrue);
    final fades = tester.widgetList<AnimatedOpacity>(find.descendant(of: root, matching: find.byType(AnimatedOpacity)));
    expect(fades.map((fade) => fade.opacity), everyElement(0));
    await tester.tap(find.byKey(const ValueKey('landscape-play')), warnIfMissed: false);
    expect(rig.session.calls, isEmpty);

    rig.chrome.show();
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isFalse);

    rig.panels.open(PlayerPanel.quality);
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isTrue);
  });

  test('speedLabel', () {
    expect(speedLabel(1), '倍速');
    expect(speedLabel(3), '3.0X');
    expect(speedLabel(0.5), '0.5X');
  });
}
