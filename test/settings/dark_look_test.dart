import 'dart:io';

import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/appearance.dart';
import 'package:bilifast/settings/dark_mode_page.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'settings_fakes.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// 设置 and 深色设置 in 深色模式 as KaiC's iPhone draws them (242, 249), and 深色设置 in light, which has no screenshot:
/// each must fit at 440 pt; with BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for
/// tools/screen_diff.py (the official bar is iOS 26's, 10 pt taller: `--anchor 106:116`).
void main() {
  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget Function(AppServices services) page, {
    bool dark = true,
  }) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester, dark: dark);
    final world = await SettingsWorld.create(appearance: AppearanceModel.memory(dark: dark));
    addTearDown(world.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => AppScope(services: world.services, child: child!),
        home: RepaintBoundary(key: const ValueKey('shot'), child: page(world.services)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  testWidgets('设置 in dark (242)', (tester) async {
    await shoot(tester, '242-settings-dark', (_) => SettingsPage(prefs: PlayerPrefs.memory(), version: '1.5.0 (1)'));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, const Color(0xFF0A0B0C));
  });

  testWidgets('深色设置 in dark (249): the row 175 px over its 2 px hairline, the switch off', (tester) async {
    await shoot(tester, '249-dark-mode-dark', (services) => DarkModePage(model: services.appearance));
    final row = tester.getRect(find.byKey(const ValueKey('dark-follow-system')));
    // 249: the section's hairline at 389 px, the row from 390.
    expect(row.top * 3, closeTo(390 - 30, 1), reason: 'our bar is 10 pt shorter than iOS 26\'s');
    expect(row.height * 3, closeTo(175, 0.01));
    final track = tester.getRect(find.byKey(const ValueKey('settings-switch')));
    expect(track.right * 3, closeTo(1320 - 23, 0.01));
    expect((track.center.dy - row.top) * 3, closeTo(476 - 390, 1));
  });

  testWidgets('深色设置 in light, drawn as the other 设置 pages', (tester) async {
    await shoot(tester, '249-dark-mode-light', (services) => DarkModePage(model: services.appearance), dark: false);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, const Color(0xFFF1F2F3));
  });
}
