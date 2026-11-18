import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;
import 'rank_support.dart';

const _screen = ValueKey('screen');

/// 230-233 as KaiC's iPhone draws them, under the system font; faces and chips are drawn by the room's own widgets ([LiveFace], the chips). With
/// BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  final names = ['演示观众1_o', '-演示观众演示-', '演示观众_3', '演示观众4', '演示观众5', '演示 观众6iii', '演示观众7-o', '演示观众'];
  final scores = [12002, 9000, 6005, 6004, 5001, 5000, 3011, 3000];
  final rank = LiveRankPage(
    entries: [
      for (var i = 0; i < names.length; i++)
        LiveRankEntry(
          rank: i + 1,
          user: viewer(i + 1, name: names[i], wealth: 29, medal: testMedal),
          score: scores[i],
        ),
    ],
  );
  final guardNames = ['-演示观众演示-', '演示观众1_o', '演示观 众3_o', '演示观众演示 ovo', '演示观众_3', '演示观众6_'];
  final weekly = LiveGuardPage(
    entries: [
      for (var i = 0; i < guardNames.length; i++)
        LiveRankEntry(
          rank: i + 1,
          user: viewer(50 + i, name: guardNames[i], guard: 2, medal: testMedal),
        ),
    ],
    total: 3351,
    topText: '上周TOP1',
    topUser: viewer(99, name: '演示观众演示观众', guard: 1),
  );

  Future<void> show(WidgetTester tester, {bool landscape = false, bool dark = false}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester, landscape: landscape, dark: dark);
    BiliFonts.family = BiliFonts.system;
    final services = await rankServices(loggedIn: false);
    final fake = PagedLiveApi(rankPage: rank, guardPages: {LiveGuardTab.weekly: weekly});
    final harness = RankHarness(api: fake);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: _screen,
          child: AppScope(services: services, child: child!),
        ),
        home: Scaffold(body: harness.page(landscape: landscape)),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold));
      for (final asset in [
        for (var i = 1; i <= 3; i++) ...['assets/images/live/rank_tag_$i.png', 'assets/images/live/rank_guard_$i.png'],
        'assets/images/live/rank_question.png',
        'assets/images/live/rank_exchange.png',
        'assets/images/live/rank_anchor.png',
      ]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await settle(tester);
  }

  Future<void> save(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/$name-ours.png');
  }

  testWidgets("230: the sheet 286.8 down, the pill 50 into it, rows 65 apart from 56 under the pill's top", (
    tester,
  ) async {
    await show(tester);
    expect(tester.getRect(byKey('rank-sheet')).top, moreOrLessEquals(956 * 0.3));
    final first = tester.getRect(byKey('rank-audience-1-1'));
    expect(first.center.dy, moreOrLessEquals(956 * 0.3 + 50 + 56 + 32.5));
    expect(tester.getRect(byKey('rank-audience-2-2')).top - first.top, 65);
    await save(tester, '230-live-room-rank-audience');
  });

  testWidgets('231: 大航海 on its purple, the segments, 上周TOP1, rows and the 立即上船 bar', (tester) async {
    await show(tester);
    await tester.tap(byKey('rank-tab-guard'));
    await settle(tester);
    final card = tester.getRect(byKey('rank-top-card'));
    expect(card.top, moreOrLessEquals(956 * 0.3 + 50 + 47 / 3 + 25 + 52 / 3));
    expect((card.left, card.right), (26, 414));
    expect(tester.getRect(byKey('rank-guard-weekly-50')).center.dy, moreOrLessEquals(1537 / 3, epsilon: 0.5));
    await save(tester, '231-live-room-rank-guard');
  });

  testWidgets('深色模式: 房间观众 on the dark surface, 大航海 on its own purple', (tester) async {
    await show(tester, dark: true);
    Color? ink(String text) => tester.widget<Text>(find.text(text).first).style!.color;
    final page = find.descendant(of: byKey('rank-sheet'), matching: find.byType(ColoredBox));
    expect(tester.widget<ColoredBox>(page.first).color, const Color(0xFF17181A));
    expect(ink('演示观众1_o'), const Color(0xFFE7E9EB));
    expect(ink('在线榜'), const Color(0xFFD44E7D));
    await save(tester, 'dark-live-room-rank-audience');
    await tester.tap(byKey('rank-tab-guard'));
    await settle(tester);
    expect(ink('演示观众6_'), const Color(0xFFFFFFFF));
    await save(tester, 'dark-live-room-rank-guard');
  });

  testWidgets('232 and 233: the panel at the right of full screen', (tester) async {
    await show(tester, landscape: true);
    expect(tester.getRect(byKey('rank-sheet')).left, 956 - 375);
    await save(tester, '232-live-room-landscape-rank-audience');
    await tester.tap(byKey('rank-tab-guard'));
    await settle(tester);
    await save(tester, '233-live-room-landscape-rank-guard');
  });
}
