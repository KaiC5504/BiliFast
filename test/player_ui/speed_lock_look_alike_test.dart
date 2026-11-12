import 'dart:io';

import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/player_hud.dart';
import 'package:bilifast/player_ui/speed_lock.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'player_gestures_test.dart' show Rig;

/// 竖屏's speed lock as KaiC's iPhone draws it, at 3× under the system font: the hint against 182, the armed band against
/// 183 and the locked pill against 186 at 15.5 s. With BILIFAST_SHOTS naming a folder outside the repo, the shots are
/// saved there for tools/screen_diff.py.
void main() {
  late Rig rig;

  setUp(() => rig = Rig()..orientation.enterVertical());
  tearDown(() => rig.dispose());

  Future<void> shoot(WidgetTester tester, String name, SpeedLockPhase phase) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;
    if (phase != SpeedLockPhase.locked) rig.chrome.showHud(const SpeedUpHud());
    rig.speedLock.value = phase;

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child!),
        // The page's Material gives 倍速中 its body style, as on the phone.
        home: Material(
          color: BiliColors.videoBackground,
          child: PlayerHud(ui: rig.ui),
        ),
      ),
    );
    final context = tester.element(find.byType(PlayerHud));
    await tester.runAsync(() => precacheImage(const AssetImage(SpeedLockTheme.lockAsset), context));
    await tester.pumpAndSettle();

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/speed-lock-$name.png');
  }

  /// The ink of every Text and glyph in [parent], in pt.
  Rect inkOf(WidgetTester tester, Finder parent) {
    final rects = [
      for (final element in find.descendant(of: parent, matching: find.byType(Text)).evaluate())
        tester.getRect(find.byElementPredicate((e) => e == element)),
      for (final element in find.descendant(of: parent, matching: find.byType(Image)).evaluate())
        tester.getRect(find.byElementPredicate((e) => e == element)),
      for (final element in find.descendant(of: parent, matching: find.byType(CustomPaint)).evaluate())
        tester.getRect(find.byElementPredicate((e) => e == element)),
    ];
    return rects.reduce((a, b) => a.expandToInclude(b));
  }

  testWidgets('182: ↓ 拖动到此处锁定倍速 centred in the black band under the progress line, 倍速中 under the top row', (
    tester,
  ) async {
    await shoot(tester, '182', SpeedLockPhase.holding);
    // 182: the band from 872 pt down; the ↓ from 148.33 pt, the text's ink to 293.33, centred 897 down.
    final band = tester.getRect(find.byKey(const ValueKey('speed-lock-hint')));
    expect(band.top, closeTo(872, 0.01));
    final row = inkOf(tester, find.byKey(const ValueKey('speed-lock-hint')));
    expect(row.center.dx, closeTo(220.8, 1));
    expect(row.center.dy, closeTo(897.2, 1));
    expect(row.width, closeTo(145, 1.5));
    // 182: 倍速中's pill 174-266 across, 106-142 down.
    final pill = tester.getRect(
      find.ancestor(of: find.byKey(const ValueKey('hud-speed-pill')), matching: find.byType(Container)).first,
    );
    expect(pill.top, closeTo(106, 0.01));
    expect(pill.height, SpeedLockTheme.pillHeight);
    expect(pill.left, closeTo(174, 0.5));
    expect(pill.width, closeTo(92, 0.5));
  });

  testWidgets('183: 🔒 松手锁定倍速 on the lighter band', (tester) async {
    await shoot(tester, '183', SpeedLockPhase.armed);
    final band = tester.getRect(find.byKey(const ValueKey('speed-lock-armed')));
    expect(band.top, closeTo(872, 0.01));
    expect(band.bottom, 956);
    // 183: the lock's ink from 169 pt, the text's to 272.33, centred 897 down.
    final row = inkOf(tester, find.byKey(const ValueKey('speed-lock-armed')));
    expect(row.center.dx, closeTo(220.7, 1));
    expect(row.center.dy, closeTo(897, 1));
  });

  testWidgets('186 at 15.5 s: 🔒 锁定倍速中 取消 in 倍速中’s place', (tester) async {
    await shoot(tester, '186', SpeedLockPhase.locked);
    // 186: the pill 141.33-298.67 across, 106-142 down.
    final pill = tester.getRect(find.byKey(const ValueKey('speed-lock-pill')));
    expect(pill.top, closeTo(106, 0.01));
    expect(pill.height, SpeedLockTheme.pillHeight);
    expect(pill.center.dx, closeTo(220, 0.01));
    expect(pill.width, closeTo(157.33, 1.5));
  });
}
