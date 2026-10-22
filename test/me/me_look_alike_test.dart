import 'dart:io';

import 'package:bilifast/home/shortcut_glyphs.dart';
import 'package:bilifast/me/me_model.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart';
import 'me_page_support.dart';

final _list = find.byKey(const ValueKey('me-list'));

/// 离线缓存's icon.
final _shortcutIcon = find
    .byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is ShortcutPainter, skipOffstage: false)
    .first;

/// 我的 as KaiC's iPhone draws it, under the system font, against 87's, 106's and 107's measures (px / 3). With
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
    expect(tester.getTopLeft(_list).dy, 328, reason: "the list starts under 106's white band");
    for (final (index, key) in ['me-offline', 'me-history', 'me-favourites', 'me-later'].indexed) {
      expect(rect(key).center.dx, 55 + 110.0 * index, reason: key);
    }
    expect(tester.getCenter(_shortcutIcon).dy, 346);

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/87-me-ours.png');
  });

  testWidgets("106: the list pushed up goes under the card's white band, cut at 328", (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    BiliFonts.family = BiliFonts.system;
    await showMe(tester, pixelRatio: 3, theme: appTheme(), fonts: FontStore.memory()..select(FontChoice.system));

    final finger = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('me-settings'))));
    for (var i = 0; i < 20 && tester.getCenter(_shortcutIcon).dy > 330; i++) {
      await finger.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getCenter(_shortcutIcon).dy, lessThan(338), reason: 'half under the cut');
    expect(tester.getTopLeft(_list).dy, 328);

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/106-me-ours.png');
    await finger.up();
    await tester.pumpAndSettle();
  });

  testWidgets("107: pulled until the shortcuts' icons are 108.33 down, the TV hanging over them", (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    BiliFonts.family = BiliFonts.system;
    final harness = await showMe(
      tester,
      pixelRatio: 3,
      theme: appTheme(),
      fonts: FontStore.memory()..select(FontChoice.system),
    );

    final finger = await tester.startGesture(tester.getCenter(_list));
    // The bounce gives way less than the finger moves, so stepping by what is left closes in from above.
    for (var i = 0; i < 400 && tester.getCenter(_shortcutIcon).dy < 454.33 - 0.05; i++) {
      final left = 454.33 - tester.getCenter(_shortcutIcon).dy;
      await finger.moveBy(Offset(0, left < 1 / 3 ? 1 / 3 : left));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getCenter(_shortcutIcon).dy, moreOrLessEquals(454.33, epsilon: 0.34));
    await tester.runAsync(() => LoadingTv.precache(tester.element(find.byType(LoadingTv))));
    await tester.pump();
    // 107's face is tv_2's (ink 11.67-47.67 × 17.33-48.33 in its 60 pt box), its ink at 201.67-237.67 ×
    // 393.67-424.67: the box at 190, 376.33. The picture is drawn centred in the full-width slot.
    final tv = tester.getRect(find.byType(LoadingTv));
    expect(tv.center.dx - LoadingTvTheme.size / 2, 190);
    expect(tv.top, moreOrLessEquals(376.33, epsilon: 0.34));
    expect(tv.bottom, moreOrLessEquals(328 + 108.33, epsilon: 0.34), reason: 'the TV hangs at the pull\'s bottom');

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/107-me-ours.png');
    await finger.cancel();
    await tester.pumpAndSettle();
    expect(harness.model.refreshes, 0);
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
    expect(tester.getTopLeft(_list).dy, 274);

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/me-logged-out-ours.png');
  });
}
