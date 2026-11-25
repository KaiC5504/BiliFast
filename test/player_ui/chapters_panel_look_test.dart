import 'dart:io';

import 'package:bili_core/api.dart' show Chapter;
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// 章节 as KaiC's iPhone draws it (273), under the system font, 2.3 playing. With BILIFAST_SHOTS naming a folder
/// outside the repo, the 3× shot is saved there for tools/screen_diff.py.
void main() {
  testWidgets('273: 章节 in landscape, 2.3 playing', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester, landscape: true);
    final session = FakePlayerSession()
      ..chapters = const [Chapter(from: 0, to: 108, title: '1'), Chapter(from: 108, to: 241, title: '2.3')];
    session.scrubbing.value = 150;
    final orientation = OrientationController()..enterLandscape();
    final chrome = ChromeState();
    final panels = PanelController();
    addTearDown(() {
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
      session.dispose();
    });
    final ui = PlayerUi(
      session: session,
      chrome: chrome,
      panels: panels,
      orientation: orientation,
      device: NoDeviceControls(),
      onBack: () {},
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: BiliFonts.family,
          fontFamilyFallback: BiliFonts.fallback,
          textTheme: BiliFonts.untracked,
        ),
        home: RepaintBoundary(
          key: const ValueKey('shot'),
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: BiliColors.videoBackground)),
              Positioned.fill(child: PanelLayer(ui: ui)),
            ],
          ),
        ),
      ),
    );
    panels.open(PlayerPanel.chapters);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 273's places, in pt: the strip's edge, the first frame and the hairline under it.
    expect(tester.getTopLeft(find.byKey(const ValueKey('panel-frame'))).dx, closeTo(574, 0.01));
    expect(tester.getCenter(find.text('章节')).dy, closeTo(ChapterPanelTheme.headerCentre, 0.01));

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/273-ours.png');
  });
}
