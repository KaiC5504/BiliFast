import 'dart:io';

import 'package:bilifast/shared/menu.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/collection_row.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../mixed_lines.dart' show appTheme;
import 'bars_ink.dart';

/// 03's 合集 row (合集 · MAD系列, 221/221) under the system font, its card where 03's is (599.67 pt down), the playing
/// mark on its still frame. With BILIFAST_SHOTS naming a folder outside the repo, the 3× shot is saved there for
/// tools/screen_diff.py.
const _cardTop = 599.67;

void main() {
  testWidgets('03: the playing mark, its bars 4.2 apart and centred on the card, 7 before 221/221', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child),
        home: Material(
          color: BiliColors.card,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: _cardTop - IntroListTheme.sectionTop,
                child: CollectionRow(
                  title: 'MAD系列',
                  episodes: [
                    for (var i = 0; i < 221; i++) Episode(bvid: 'BV$i', cid: i, title: '第$i集', current: i == 220),
                  ],
                  onOpen: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/03-collection-ours.png');

    final card = tester.getRect(find.byType(PressHighlight));
    expect(card.top, moreOrLessEquals(_cardTop));
    final mark = tester.getRect(find.byType(PlayingBars));
    expect(mark.center.dy, moreOrLessEquals(card.center.dy));
    final bars = await barsIn(
      tester,
      find.byKey(const ValueKey('screen')),
      area: mark.inflate(1),
      over: PageTheme.chipFill,
    );
    expect(bars, hasLength(3));
    expect(bars[1].x - bars[0].x, closeTo(IntroListTheme.barStep, 0.05));
    expect(bars[2].x - bars[1].x, closeTo(IntroListTheme.barStep, 0.05));
    expect(bars[1].x, closeTo(mark.center.dx, 0.05));
    for (final bar in bars) {
      expect(bar.y, closeTo(card.center.dy, 0.05));
      expect(bar.ink, IntroListTheme.iconInk);
    }
  });
}
