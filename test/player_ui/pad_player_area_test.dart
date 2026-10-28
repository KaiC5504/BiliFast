import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/end_screen_landscape.dart';
import 'package:bilifast/player_ui/end_screen_portrait.dart';
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/player_ui/pad/pad_end_fullscreen.dart';
import 'package:bilifast/player_ui/pad/pad_end_inline.dart';
import 'package:bilifast/player_ui/pad/pad_fullscreen_chrome.dart';
import 'package:bilifast/player_ui/pad/pad_inline_controls.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/portrait_controls.dart';
import 'package:bilifast/video/video_player_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

/// The page's player area picks the iPad's controls and end screens on the iPad, by the screen's size, and the
/// iPhone's everywhere else.
void main() {
  late FakePlayerSession session;
  late PlayerUi ui;

  setUp(() {
    session = FakePlayerSession();
    final chrome = ChromeState();
    final panels = PanelController();
    final orientation = OrientationController();
    addTearDown(() {
      session.dispose();
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
    });
    ui = PlayerUi(
      session: session,
      chrome: chrome,
      panels: panels,
      orientation: orientation,
      device: NoDeviceControls(),
      onBack: () {},
    );
  });

  Future<void> show(WidgetTester tester, Presentation presentation, {required Size screen, double topInset = 0}) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1
      ..padding = FakeViewPadding(top: topInset);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerArea(
          presentation: presentation,
          onBack: () {},
          ui: ui,
          video: session.player.buildView(),
        ),
      ),
    );
  }

  const pad = Size(1194, 834);
  const padUpright = Size(834, 1194);
  const phone = Size(440, 956);

  testWidgets('the iPad gets its own controls over the page\'s player and in full screen, either way up', (
    tester,
  ) async {
    for (final screen in [pad, padUpright]) {
      await show(tester, Presentation.inline, screen: screen);
      expect(find.byType(PadInlineControls), findsOneWidget);
      expect(find.byType(PortraitControls), findsNothing);

      await show(tester, Presentation.landscape, screen: screen);
      expect(find.byType(PadFullScreenChrome), findsOneWidget);
      expect(find.byType(PadInlineControls), findsNothing);
    }
  });

  testWidgets('the iPad gets its own end screens', (tester) async {
    session.ended = true;
    await show(tester, Presentation.inline, screen: pad);
    expect(find.byType(PadEndInline), findsOneWidget);
    expect(find.byType(EndScreenPortrait), findsNothing);

    await show(tester, Presentation.landscape, screen: pad);
    expect(find.byType(PadEndFullScreen), findsOneWidget);
    expect(find.byType(PadEndInline), findsNothing);
  });

  testWidgets('a stray 竖屏 on the iPad falls to full screen\'s chrome', (tester) async {
    await show(tester, Presentation.vertical, screen: pad);
    expect(find.byType(PadFullScreenChrome), findsOneWidget);
  });

  testWidgets('the iPhone keeps its own, whatever the iPad has', (tester) async {
    await show(tester, Presentation.inline, screen: phone);
    expect(find.byType(PortraitControls), findsOneWidget);
    expect(find.byType(PadInlineControls), findsNothing);

    await show(tester, Presentation.landscape, screen: const Size(956, 440));
    expect(find.byType(LandscapeChrome), findsOneWidget);
    expect(find.byType(PadFullScreenChrome), findsNothing);

    session.ended = true;
    await show(tester, Presentation.inline, screen: phone);
    expect(find.byType(EndScreenPortrait), findsOneWidget);
    await show(tester, Presentation.landscape, screen: const Size(956, 440));
    expect(find.byType(EndScreenLandscape), findsOneWidget);
    expect(find.byType(PadEndFullScreen), findsNothing);
  });

  testWidgets('the iPad\'s danmaku fly over the whole box, status bar or not (09, 25); the iPhone\'s keep below it', (
    tester,
  ) async {
    Rect danmaku() => tester.getRect(find.byType(DanmakuLayer));
    for (final presentation in [Presentation.inline, Presentation.landscape]) {
      await show(tester, presentation, screen: pad, topInset: 24);
      expect(danmaku(), Offset.zero & pad, reason: '$presentation');
    }
    session.isVertical = true;
    await show(tester, Presentation.landscape, screen: pad, topInset: 24);
    expect(danmaku(), Offset.zero & pad, reason: 'an upright video, pillarboxed, keeps them across the screen (25)');
    await show(tester, Presentation.landscape, screen: padUpright, topInset: 24);
    expect(danmaku(), Offset.zero & padUpright);
    session.isVertical = false;
    expect(padDanmakuInsets, EdgeInsets.zero);

    await show(tester, Presentation.inline, screen: phone, topInset: 62);
    expect(danmaku().top, 62);
  });
}
