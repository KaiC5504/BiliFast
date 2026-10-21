import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/search/results/result_more_sheet.dart';
import 'package:bilifast/search/results/results_view.dart';
import 'package:bilifast/search/search_model.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import 'results_support.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// The field row above the results is the page's: SafeArea's 62 and the 44 bar end it 106 down.
const _fieldRowBottom = 106.0;

/// Set to a folder outside the repo to write the 3× shots for tools/screen_diff.py against 56, 59, 60 and 61.
final _shots = Platform.environment['BILIFAST_SHOT_DIR'];

void main() {
  late StubSearchModel model;

  setUp(() => model = StubSearchModel());

  Future<void> show(WidgetTester tester, {bool sheet = false}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    // The services' font store puts MiSans back, so the system font comes after them.
    final services = await resultServices(loggedIn: true, api: FakePageApi());
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    final now = DateTime.now();
    model.videosValue = SearchResults(
      items: [
        video(
          1,
          title: HighlightedText.plain('同学们，v2发布!今晚最后的彩排!'),
          author: 'CopperowlTK3000',
          play: 92000,
          duration: 162,
          published: now.subtract(const Duration(hours: 23, minutes: 2)),
        ),
        video(
          2,
          title: HighlightedText.plain('周末周末朋友在聚会的时候，可是这里离春天还远呢~所以没有花开呀！月亮'),
          author: '林小橙子',
          play: 60000,
          duration: 21,
          published: DateTime(now.year, 1, 20),
        ),
        video(
          3,
          title: const HighlightedText([HighlightRun('云海列车 旅人'), HighlightRun('青柠', highlighted: true)]),
          author: '老周_Brest-修复珍藏版',
          play: 85,
          duration: 2312,
          published: DateTime(now.year, 1, 17),
        ),
        for (var i = 4; i < 12; i++) video(i, play: 488000, duration: 2312, published: DateTime(now.year, 1, 17)),
      ],
      loaded: true,
    );
    model.usersValue = SearchResults(
      items: [
        user(1, name: '青柠', fans: 8, level: 2),
        user(
          2,
          name: '青柠柠柠柠柠白狗探',
          fans: 1481000,
          videos: 539,
          level: 6,
          officialType: 0,
          officialDesc: 'bilibili 优质UP主',
        ),
        user(3, name: '青柠电', fans: 12000, videos: 79, level: 4),
        user(4, name: '青橙青', fans: 12000, videos: 100, level: 3),
      ],
      loaded: true,
      exhausted: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(textTheme: BiliFonts.untracked),
        builder: (context, page) => AppScope(services: services, child: page!),
        home: RepaintBoundary(
          key: const ValueKey('shot'),
          child: Scaffold(
            backgroundColor: BiliColors.card,
            body: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: _fieldRowBottom),
                    Expanded(
                      child: ResultsView(model: model, onOpenVideo: (_) {}, onOpenUser: (_) {}, onMore: (_) {}),
                    ),
                  ],
                ),
                if (sheet)
                  Positioned.fill(
                    child: ResultMoreSheet(video: video(1), onClose: () {}),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final dir = _shots;
    if (dir != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$dir/$name.png');
  }

  testWidgets('56 and 61: the tab row, the hairline and the video rows', (tester) async {
    await show(tester);
    await shoot(tester, '56-ours');
    expect(tester.getRect(find.byKey(const ValueKey('search-tab-indicator'))).top, closeTo(140, 0.01));
    expect(tester.getTopLeft(find.byKey(const ValueKey('search-row-BV1search1'))).dy, closeTo(146.33, 0.01));
    expect(tester.getTopLeft(find.byKey(const ValueKey('search-row-BV1search2'))).dy, closeTo(267.33, 0.01));
  });

  testWidgets('57: scrolled, the tab row has gone', (tester) async {
    await show(tester);
    await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, -300));
    await settle(tester);
    await shoot(tester, '57-ours');
    expect(tester.getBottomLeft(find.byKey(const ValueKey('search-tab-all'))).dy, lessThanOrEqualTo(_fieldRowBottom));
  });

  testWidgets('59: the ⋮ sheet over the rows', (tester) async {
    await show(tester, sheet: true);
    await shoot(tester, '59-ours');
    expect(tester.getRect(find.byKey(const ValueKey('search-sheet'))).top, closeTo(544.67, 0.01));
  });

  testWidgets('60: 用户 with its sort row', (tester) async {
    model.tabValue = SearchTab.users;
    await show(tester);
    await shoot(tester, '60-ours');
    expect(tester.getTopLeft(find.byKey(const ValueKey('search-row-user-701'))).dy, closeTo(186, 0.01));
    expect(tester.getRect(find.byKey(const ValueKey('search-follow-701'))).center.dy, closeTo(226, 0.01));
  });
}
