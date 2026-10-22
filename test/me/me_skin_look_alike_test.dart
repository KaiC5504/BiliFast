import 'dart:io';

import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart';
import 'me_page_support.dart';

/// 我的 dressed as KaiC's iPhone draws it under the system font, against 109's measures (px / 3). The picture is a
/// plain stand-in in the dark of 109's frame at its edges, so the fade and the white ink can be measured against
/// 109 without its art. With BILIFAST_SHOTS naming a folder outside the repo, the 3× shot is saved there for
/// tools/screen_diff.py.
void main() {
  testWidgets("109 under the system font: 87's header in white over the picture, its fade into the list", (
    tester,
  ) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    BiliFonts.family = BiliFonts.system;
    final folder = pictureFolder();
    final picture = (await tester.runAsync(
      () => drawPicture(
        folder,
        'head.png',
        1320,
        1320,
        (canvas) => canvas.drawColor(const Color(0xFF292323), BlendMode.src),
      ),
    ))!;
    final harness = await showMe(
      tester,
      pixelRatio: 3,
      theme: appTheme(),
      fonts: FontStore.memory()..select(FontChoice.system),
    );

    Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
    const keys = [
      'me-cast',
      'me-scan',
      'me-outfit',
      'me-night',
      'me-avatar',
      'me-name',
      'me-edit',
      'me-vip-label',
      'me-bcoin',
      'me-coins',
      'me-space',
      'me-dynamics',
      'me-following',
      'me-followers',
      'me-vip-card',
      'me-vip-centre',
      'me-offline',
      'me-list',
    ];
    final stock = {for (final key in keys) key: rect(key)};

    harness.skin.skin = Skin(equip: skinEquip(), headMyself: picture);
    await tester.pump();
    await settlePicture(tester);

    // 109's white ink lies where 87's dark ink does, to the pixel.
    for (final key in keys) {
      expect(rect(key), stock[key], reason: key);
    }
    expect(rect('me-skin-picture'), const Rect.fromLTRB(0, 0, 440, 328));
    expect(rect('me-skin-fade'), const Rect.fromLTRB(0, 266, 440, 328));
    expect(rect('me-vip-card').top, 266);

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/109-me-ours.png');
  });
}
