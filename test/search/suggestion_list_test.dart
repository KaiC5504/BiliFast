import 'package:bili_core/api.dart' hide RichText, SearchPage;
import 'package:bilifast/search/suggestion_list.dart';
import 'package:bilifast/shared/menu.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/system_font.dart';

const _suggestions = [
  SearchSuggestion(
    keyword: 'abc联动',
    text: HighlightedText([HighlightRun('abc', highlighted: true), HighlightRun('联动')]),
  ),
  SearchSuggestion(keyword: '扫地机', text: HighlightedText([HighlightRun('扫地机')])),
  SearchSuggestion(
    keyword: '刀剑abc',
    text: HighlightedText([HighlightRun('刀剑'), HighlightRun('abc', highlighted: true)]),
  ),
];

void main() {
  late List<String> selected;

  setUp(() => selected = []);

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(440, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuggestionList(suggestions: _suggestions, onSelect: (s) => selected.add(s.keyword)),
        ),
      ),
    );
  }

  Finder row(String keyword) => find.byKey(ValueKey('search-suggestion-$keyword'));

  /// The colours of [keyword]'s row's runs, in order.
  List<Color?> colours(WidgetTester tester, String keyword) {
    final rich = tester.widget<RichText>(find.descendant(of: row(keyword), matching: find.byType(RichText)));
    final runs = <Color?>[];
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) runs.add(span.style?.color ?? rich.text.style?.color);
      return true;
    });
    return runs;
  }

  testWidgets('one 44 tall row per suggestion, the typed part pink', (tester) async {
    await show(tester);
    expect(tester.getRect(row('abc联动')), const Rect.fromLTRB(0, 0, 440, 44));
    expect(tester.getRect(row('扫地机')).top, 44);
    expect(colours(tester, 'abc联动'), [SearchTheme.highlight, SearchTheme.text]);
    expect(colours(tester, '刀剑abc'), [SearchTheme.text, SearchTheme.highlight]);
    expect(colours(tester, '扫地机'), [SearchTheme.text]);
  });

  testWidgets('each row ends in a hairline from the gutter to the right edge', (tester) async {
    await show(tester);
    final hairline = find.descendant(
      of: row('扫地机'),
      matching: find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == SearchTheme.suggestionHairlineColor,
      ),
    );
    expect(tester.getRect(hairline), rectMoreOrLessEquals(const Rect.fromLTRB(12, 88 - 1 / 3, 440, 88)));
  });

  testWidgets('a tap searches the suggestion\'s keyword, also as an accessibility press', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester);
    await tester.tap(row('扫地机'));
    expect(selected, ['扫地机']);
    tester.semantics.tap(find.semantics.byLabel('刀剑abc'));
    expect(selected, ['扫地机', '刀剑abc']);
    handle.dispose();
  });

  testWidgets('a row darkens while pressed, as 历史记录 and 设置 rows do', (tester) async {
    await show(tester);
    expect(find.descendant(of: row('扫地机'), matching: find.byType(PressHighlight)), findsNothing);
    expect(tester.widget(row('扫地机')), isA<PressHighlight>());
    bool darkened() => find
        .descendant(
          of: row('扫地机'),
          matching: find.byWidgetPredicate(
            (widget) => widget is DecoratedBox && (widget.decoration as BoxDecoration).color == BiliColors.pressedFill,
          ),
        )
        .evaluate()
        .isNotEmpty;
    expect(darkened(), isFalse);
    final gesture = await tester.startGesture(tester.getCenter(row('扫地机')));
    await tester.pump(kPressTimeout);
    expect(darkened(), isTrue);
    await gesture.up();
    await tester.pump();
    expect(darkened(), isFalse);
    expect(selected, ['扫地机']);
  });

  testWidgets('with no Material above it, the list names the system font fallback itself', (tester) async {
    await expectSystemFallback(
      tester,
      () => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(440, 800)),
            child: SuggestionList(suggestions: _suggestions, onSelect: (_) {}),
          ),
        ),
      ),
      find.text('扫地机'),
    );
  });
}
