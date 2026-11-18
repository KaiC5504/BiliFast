import 'package:bilifast/me/me_glyphs.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'me_page_support.dart';

final _night = find.byKey(const ValueKey('me-night'));

MeTopGlyph _dayNightGlyph(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.descendant(of: _night, matching: find.byType(CustomPaint)).last);
  return (paint.painter! as MeTopGlyphPainter).glyph;
}

SystemUiOverlayStyle _statusBar(WidgetTester tester) => tester
    .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(find.byType(AnnotatedRegion<SystemUiOverlayStyle>))
    .last
    .value;

/// 我的's ☾ and ☀ (02, 251): the top row's last glyph switches 深色模式.
void main() {
  testWidgets('☾ turns dark: the page redraws in its night colours and shows ☀; ☀ turns it back', (tester) async {
    final harness = await showMe(tester);
    final appearance = harness.services.appearance;
    expect(_dayNightGlyph(tester), MeTopGlyph.night);
    expect(tester.widget<Material>(find.byType(Material).last).color, const Color(0xFFFFFFFF));

    await tester.tap(_night);
    await tester.pump();
    expect(BiliTheme.dark, isTrue);
    expect(appearance.dark, isTrue);
    expect(_dayNightGlyph(tester), MeTopGlyph.day);
    expect(tester.widget<Material>(find.byType(Material).last).color, const Color(0xFF17181A));
    expect(_statusBar(tester), SystemUiOverlayStyle.light);
    expect(find.text('即将推出'), findsNothing);

    await tester.tap(_night);
    await tester.pump();
    expect(BiliTheme.dark, isFalse);
    expect(_dayNightGlyph(tester), MeTopGlyph.night);
    expect(tester.widget<Material>(find.byType(Material).last).color, const Color(0xFFFFFFFF));
    expect(_statusBar(tester), SystemUiOverlayStyle.dark);
  });

  testWidgets('the switch stops following iOS, as the official one does', (tester) async {
    final harness = await showMe(tester);
    final appearance = harness.services.appearance;
    await appearance.setFollowSystem(true);
    await tester.tap(_night);
    await tester.pump();
    expect(appearance.followSystem, isFalse);
    expect(BiliTheme.dark, isTrue);
  });

  testWidgets('its accessibility press is 夜间模式 in light and 日间模式 in dark', (tester) async {
    final handle = tester.ensureSemantics();
    await showMe(tester);
    tester.semantics.tap(find.semantics.byLabel('夜间模式'));
    await tester.pump();
    expect(BiliTheme.dark, isTrue);
    expect(find.semantics.byLabel('夜间模式'), findsNothing);
    tester.semantics.tap(find.semantics.byLabel('日间模式'));
    await tester.pump();
    expect(BiliTheme.dark, isFalse);
    handle.dispose();
  });

  testWidgets('started dark, it shows ☀ and the 会员 card in 251\'s colours', (tester) async {
    await showMe(tester, dark: true);
    expect(_dayNightGlyph(tester), MeTopGlyph.day);
    expect(MeTheme.card, const Color(0xFF37232C));
    expect(MeTheme.vipLabelInk, const Color(0xFFFFFFFF));
    expect(MeTheme.skinFadeColors.last, const Color(0xFF17181A));
  });
}
