import 'dart:io';

import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/panels/panel_parts.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_player_session.dart';
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// Landscape ⋮ as KaiC's iPhone draws it (21), under the system font, scrolled as 21 is: 自动连播's row cut at the
/// top. With BILIFAST_SHOTS naming a folder outside the repo, the 3× shot is saved there for tools/screen_diff.py.
void main() {
  testWidgets('21: ⋮ in landscape, 后台听视频 on between 镜像翻转 and 画面尺寸', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(loadIconFonts);
    showAsPhone(tester, landscape: true);
    final session = FakePlayerSession();
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
    panels.open(PlayerPanel.more);
    await tester.pumpAndSettle();

    // 21 has 自动连播's text centred 13.4 pt down.
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: find.byKey(const ValueKey('panel-frame')), matching: find.byType(Scrollable)),
    );
    scroll.position.jumpTo(scroll.position.pixels + tester.getCenter(find.text('自动连播')).dy - 13.4);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final mirror = tester.getCenter(find.text('镜像翻转')).dy;
    final listen = find.byKey(const ValueKey('more-background-listen'));
    expect(tester.getCenter(find.text('后台听视频')).dy - mirror, BiliMetrics.panelRowHeight);
    expect(tester.widget<PanelSwitch>(find.descendant(of: listen, matching: find.byType(PanelSwitch))).on, isTrue);

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/21-ours.png');
  });
}
