import 'package:bili_core/devlog.dart';
import 'package:bilifast/history/history_model.dart';
import 'package:bilifast/history/watch_history_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import 'history_fakes.dart';
import 'pixel_probe.dart';

/// Where the 3× shots go for tools/screen_diff.py, outside the repo: `--dart-define=HISTORY_SHOTS=<folder>`. Nothing
/// is written without it.
const _shots = String.fromEnvironment('HISTORY_SHOTS');

void main() {
  setUpAll(loadSystemFontStandIns);

  final boundary = GlobalKey();

  // 256's rows: eight from today, some part watched, one finished.
  final items = [
    for (var i = 0; i < 8; i++)
      historyItem(
        i + 1,
        viewAt: wall(18, 16, 42 - i * 4, month: 11),
        progress: i == 2 ? -1 : 20 + i * 10,
        duration: 600,
        device: i.isEven ? 1 : 2,
        title: i.isEven ? '示例视频标题，两行长的标题在这里换行继续写下去$i' : '示例视频标题$i',
      ),
  ];

  Future<void> show(WidgetTester tester, {bool dark = false}) async {
    showAsPhone(tester, dark: dark);
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    final api = FakePageApi()..historyItems = items;
    final model = HistoryModel(
      api: api,
      isLoggedIn: () => true,
      now: () => wallTime(18, 17, 0).add(const Duration(days: 30)),
      utcOffset: testOffset,
      logger: Logger(session: 'test'),
    );
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: BiliFonts.family,
          fontFamilyFallback: BiliFonts.fallback,
          textTheme: BiliFonts.untracked,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        builder: (context, child) => RepaintBoundary(key: boundary, child: child),
        home: WatchHistoryPage(model: model, loginGate: FakeLoginGate(), share: (_) async => true),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('256 at night: the page, rows and hairlines dark, the words, ⋮ and progress as measured', (tester) async {
    await show(tester, dark: true);
    if (_shots.isNotEmpty) await saveShot(tester, find.byKey(boundary), '$_shots/256.png');
    final row = tester.getRect(find.byKey(ValueKey('history-${items[1].id}')));
    final colours = await pixelsAt(tester, find.byKey(boundary), [
      const Offset(220, 20),
      Offset(row.right - 60, row.top + 40),
      Offset(row.right - 60, row.bottom - 0.1),
    ]);
    // 256: the page #17181A, the hairline between rows #2F3134.
    expect(colours, [const Color(0xFF17181A), const Color(0xFF17181A), const Color(0xFF2F3134)]);
    final line = tester.widget<ColoredBox>(find.byKey(const ValueKey('history-progress-line')).first);
    expect(line.color, const Color(0xFFD44E7D));
    expect(HistoryTheme.back, const Color(0xFFE7E9EB));
    expect(HistoryTheme.rowTitle, const Color(0xFFE7E9EB));
    expect(HistoryTheme.meta, const Color(0xFF757A81));
    expect(HistoryTheme.more, const Color(0xFF46494D));
  });

  testWidgets('by day the same page keeps its light colours', (tester) async {
    await show(tester);
    final colours = await pixelsAt(tester, find.byKey(boundary), [const Offset(220, 20)]);
    expect(colours, [const Color(0xFFFFFFFF)]);
    expect(HistoryTheme.progress, const Color(0xFFEA6E96));
  });
}
