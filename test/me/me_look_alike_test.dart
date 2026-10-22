import 'dart:io';

import 'package:bilifast/me/me_model.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart';
import 'me_page_support.dart';

/// 我的 as KaiC's iPhone draws it, under the system font, against 87's and 106's measures (px / 3). With
/// BILIFAST_SHOTS naming a folder outside the repo, the 3× shot is saved there for tools/screen_diff.py.
void main() {
  testWidgets("我的 under the system font: 87's header, counts, 会员 card and shortcuts, then 106's 更多服务", (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    BiliFonts.family = BiliFonts.system;
    await showMe(tester, pixelRatio: 3, theme: appTheme(), fonts: FontStore.memory()..select(FontChoice.system));

    Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
    expect(rect('me-vip-card').top, 266);
    expect(rect('me-vip-card').bottom, 320);
    expect(tester.getTopLeft(find.byKey(const ValueKey('me-list'))).dy, 320, reason: 'the list starts under the card');
    for (final (index, key) in ['me-offline', 'me-history', 'me-favourites', 'me-later'].indexed) {
      expect(rect(key).center.dx, 55 + 110.0 * index, reason: key);
    }

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/87-me-ours.png');
  });

  testWidgets('logged out under the system font: 点击登录 level with the grey head, the rest as 87', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    BiliFonts.family = BiliFonts.system;
    await showMe(
      tester,
      view: const MeLoggedOut(),
      pixelRatio: 3,
      theme: appTheme(),
      fonts: FontStore.memory()..select(FontChoice.system),
    );

    final head = tester.getRect(find.byKey(const ValueKey('me-avatar')));
    expect(head, const Rect.fromLTWH(15, 126, 64, 64));
    expect(tester.getCenter(find.text('点击登录')).dy, head.center.dy);
    expect(tester.getTopLeft(find.byKey(const ValueKey('me-list'))).dy, 266);

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/me-logged-out-ours.png');
  });
}
