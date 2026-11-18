import 'dart:io';

import 'package:bilifast/home/shortcut_glyphs.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart';
import 'me_page_support.dart';

final _shortcutIcon = find
    .byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is ShortcutPainter, skipOffstage: false)
    .first;

/// 我的 in 深色模式 under the system font, pushed up as 251 is (106's place), and dressed as 252. With BILIFAST_SHOTS
/// naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> systemFont(WidgetTester tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    BiliFonts.family = BiliFonts.system;
  }

  testWidgets('251: dark, the list pushed up under the card as 106', (tester) async {
    await systemFont(tester);
    await showMe(tester, pixelRatio: 3, theme: appTheme(), dark: true);
    final finger = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('me-settings'))));
    for (var i = 0; i < 20 && tester.getCenter(_shortcutIcon).dy > 330; i++) {
      await finger.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getRect(find.byKey(const ValueKey('me-vip-card'))).top, 266);

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/251-me-dark-ours.png');
    await finger.up();
    await tester.pumpAndSettle();
  });

  testWidgets('252: dressed in dark, the picture fades into the dark page over the same 62 pt', (tester) async {
    await systemFont(tester);
    final folder = pictureFolder();
    final picture = (await tester.runAsync(
      () => drawPicture(
        folder,
        'head.png',
        1320,
        1320,
        (canvas) => canvas.drawColor(const Color(0xFFC4E9D3), BlendMode.src),
      ),
    ))!;
    final harness = await showMe(tester, pixelRatio: 3, theme: appTheme(), dark: true);
    harness.skin.skin = Skin(equip: skinEquip(color: 0xFF000000, lightText: false), headMyself: picture);
    await tester.pump();
    await settlePicture(tester);

    final fade = tester.widget<DecoratedBox>(find.byKey(const ValueKey('me-skin-fade')));
    final colours = (fade.decoration as BoxDecoration).gradient!.colors;
    expect(colours.first, const Color(0x0017181A));
    expect(colours.last, const Color(0xFF17181A));
    expect(tester.getRect(find.byKey(const ValueKey('me-skin-fade'))), const Rect.fromLTRB(0, 266, 440, 328));

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/252-me-dark-ours.png');
  });
}
