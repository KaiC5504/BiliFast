import 'dart:io';

import 'package:bili_core/engine.dart' show EngineSnapshot, PlaybackMode;
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/playback/overlay_stats.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_loading.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/video_player_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

import '../support/fake_player_session.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import 'mixed_lines.dart';

/// The player's 正在缓冲 as KaiC's iPhone draws it, under the system font, against 66 (the small player) and 65
/// (landscape full screen), measured in px / 3. With BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are
/// saved there.
/// The Lottie's ink centres 0.35 pt above its box's centre (12.1, 11.65 of 24).
const _inkAbove = 0.35;

void main() {
  late FakePlayerSession session;
  late PlayerUi ui;

  setUp(() {
    session = FakePlayerSession()
      ..stats.value = const OverlayStats(mode: PlaybackMode.btr, downloadBps: 69.33 * 1024, engine: EngineSnapshot());
    final chrome = ChromeState()..hide();
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

  Future<void> render(WidgetTester tester, {required bool landscape}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(() => AssetLottie(PlayerLoading.asset).load());
    showAsPhone(tester, landscape: landscape);
    BiliFonts.family = BiliFonts.system;
    final area = VideoPlayerArea(
      presentation: landscape ? Presentation.landscape : Presentation.inline,
      onBack: () {},
      ui: ui,
      video: session.player.buildView(),
      loading: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('screen'),
          // Held on the TV's first frame, whole, for a still to measure.
          child: MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        ),
        home: ColoredBox(
          color: BiliColors.videoBackground,
          child: landscape
              ? area
              : Stack(
                  children: [
                    Positioned(left: 0, right: 0, top: 62, height: 440 / BiliMetrics.videoAspect, child: area),
                  ],
                ),
        ),
      ),
    );
    await tester.pump();
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) {
      await saveShot(
        tester,
        find.byKey(const ValueKey('screen')),
        '$shots/player-loading-${landscape ? 'landscape' : 'portrait'}.png',
      );
    }
  }

  double baseline(WidgetTester tester) {
    final text = find.byKey(const ValueKey('player-loading-text'));
    final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: text, matching: find.byType(RichText)));
    return tester.getTopLeft(text).dy + paragraph.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  }

  testWidgets('66: the TV on the small player\'s centre, the line\'s baseline 21.3 pt under it', (tester) async {
    await render(tester, landscape: false);
    final tv = tester.getRect(find.byType(Lottie));
    // The TV's ink is 64 × 60 px about (661.5, 556) px.
    expect(tv.size, const Size.square(24));
    expect(tv.center, const Offset(220, 62 + 247.5 / 2));
    expect(tv.center.dy, closeTo(556 / 3 + _inkAbove, 0.5));
    expect(find.text('正在缓冲... 69.33 KB/s'), findsOneWidget);
    // Digits' baseline at 657 px.
    expect(baseline(tester), closeTo(657 / 3, 0.5));
    expect(tester.getCenter(find.byKey(const ValueKey('player-loading-text'))).dx, closeTo(220, 0.01));
  });

  testWidgets('65: the TV on the screen\'s centre in landscape full screen', (tester) async {
    await render(tester, landscape: true);
    final tv = tester.getRect(find.byType(Lottie));
    expect(tv.center, const Offset(478, 220));
    expect(tv.center.dy, closeTo(657.5 / 3 + _inkAbove, 0.5));
    // Digits' baseline at 760 px.
    expect(baseline(tester), closeTo(760 / 3, 0.5));
  });
}
