import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilifast/player/bili_player.dart' show PlayerStatus, StatusChanged;
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/player_gestures.dart';
import 'package:bilifast/player_ui/player_hud.dart';
import 'package:bilifast/player_ui/portrait_controls.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'player_gestures_test.dart' show Rig;

/// The small player's brightness level mid-drag on KaiC's iPhone, layered as the page lays it (gestures, controls,
/// HUD). No official screenshot shows one; with BILIFAST_SHOTS naming a folder outside the repo, the shot is saved
/// there to look at.
void main() {
  testWidgets("the level sits centred in the 440 × 247.5 box at 0.8×, clear of the controls' rows", (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(SeekBar.precache);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;

    final rig = Rig()..session.duration.value = 212;
    addTearDown(rig.dispose);
    rig.session.player.emit(const StatusChanged(PlayerStatus.playing));
    const box = Rect.fromLTWH(0, 62, 440, 440 / BiliMetrics.videoAspect);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child!),
        home: Material(
          color: BiliColors.videoBackground,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: box,
                // A flat stand-in for a picture under the controls' shade.
                child: ColoredBox(
                  color: const Color(0xFF6B625B),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PlayerGestureLayer(ui: rig.ui),
                      PortraitControls(ui: rig.ui),
                      PlayerHud(ui: rig.ui),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Up 60 pt from the left third: 0.5 + 60 / 247.5.
    final gesture = await tester.startGesture(box.center.translate(-110, 30));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -10), timeStamp: Duration(milliseconds: 16 * (i + 1)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(rig.chrome.hud.value, isA<LevelHud>());

    final pill = tester.getRect(
      find.ancestor(of: find.byIcon(Icons.brightness_high_rounded), matching: find.byType(Container)).first,
    );
    expect(pill.center.dx, moreOrLessEquals(box.center.dx));
    expect(pill.center.dy, moreOrLessEquals(box.center.dy));
    expect(pill.height, moreOrLessEquals(BiliMetrics.hudHeight * 0.8));
    const content = BiliMetrics.hudIcon + BiliMetrics.hudGap + BiliMetrics.hudBarWidth;
    expect(pill.width, moreOrLessEquals((BiliMetrics.hudPadding * 2 + content) * 0.8));
    // The rows keep their 44 pt touch targets at the box's top and bottom.
    expect(pill.top - box.top, greaterThan(BiliMetrics.chromeButton + 20));
    expect(box.bottom - pill.bottom, greaterThan(BiliMetrics.chromeButton + 20));

    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('screen')));
    await tester.runAsync(() async {
      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots == null) return;
      final image = await render.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('$shots/small-player-level.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
