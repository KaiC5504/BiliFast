import 'dart:io';

import 'package:bilifast/search/results/filter_panel.dart';
import 'package:bilifast/search/search_filters.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// 58's tab row ends in a hairline 438 px down; the panel starts under it.
const _panelTop = 439 / 3;

Key _chip(String id) => ValueKey('search-filter-$id');

/// Every chip, and the filters a tap on it asks for, from [from].
Map<String, SearchFilters> _taps(SearchFilters from) => {
  for (final order in FilterOrder.values) 'order-${order.name}': from.copyWith(order: order),
  for (final published in FilterPublished.values) 'published-${published.name}': from.copyWith(published: published),
  for (final length in FilterLength.values) 'length-${length.name}': from.copyWith(length: length),
};

class _Panel {
  _Panel(this.filters);

  SearchFilters filters;
  final changes = <SearchFilters>[];

  Widget build() => StatefulBuilder(
    builder: (context, setState) => SearchFilterPanel(
      filters: filters,
      onChanged: (next) => setState(() {
        changes.add(next);
        filters = next;
      }),
    ),
  );
}

Future<_Panel> _show(WidgetTester tester, [SearchFilters filters = const SearchFilters()]) async {
  showAsPhone(tester);
  final panel = _Panel(filters);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily: BiliFonts.family,
        fontFamilyFallback: BiliFonts.fallback,
        textTheme: BiliFonts.untracked,
      ),
      home: RepaintBoundary(
        key: const ValueKey('shot'),
        child: Scaffold(
          backgroundColor: BiliColors.card,
          body: Stack(
            children: [Positioned(top: _panelTop, left: 0, right: 0, child: panel.build())],
          ),
        ),
      ),
    ),
  );
  return panel;
}

Color _labelColour(WidgetTester tester, String id) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byKey(_chip(id)), matching: find.byType(RichText)),
  );
  return paragraph.text.style!.color!;
}

void main() {
  group('taps', () {
    testWidgets('each chip asks for its own value at once', (tester) async {
      const from = SearchFilters(
        order: FilterOrder.plays,
        published: FilterPublished.week,
        length: FilterLength.over120,
      );
      for (final MapEntry(key: id, value: expected) in _taps(from).entries) {
        final panel = await _show(tester, from);
        await tester.tap(find.byKey(_chip(id)));
        await tester.pump();
        expect(panel.changes, expected == from ? isEmpty : [expected], reason: id);
      }
    });

    testWidgets('the chosen chip again changes nothing', (tester) async {
      final panel = await _show(tester);
      for (final id in ['order-relevance', 'published-any', 'length-any']) {
        await tester.tap(find.byKey(_chip(id)));
        await tester.pump();
      }
      expect(panel.changes, isEmpty);

      await tester.tap(find.byKey(_chip('length-from60to120')));
      await tester.pump();
      await tester.tap(find.byKey(_chip('length-from60to120')));
      await tester.pump();
      expect(panel.changes, [const SearchFilters(length: FilterLength.from60to120)]);
    });

    testWidgets('one change keeps the other rows', (tester) async {
      final panel = await _show(tester);
      await tester.tap(find.byKey(_chip('order-danmaku')));
      await tester.pump();
      await tester.tap(find.byKey(_chip('published-halfYear')));
      await tester.pump();
      expect(panel.changes.last, const SearchFilters(order: FilterOrder.danmaku, published: FilterPublished.halfYear));
    });
  });

  testWidgets('the chosen chip of each row has the pink label on the same grey', (tester) async {
    await _show(tester, const SearchFilters(order: FilterOrder.newest, length: FilterLength.under10));
    final chosen = {'order-newest', 'published-any', 'length-under10'};
    for (final id in _taps(const SearchFilters()).keys) {
      expect(
        _labelColour(tester, id),
        chosen.contains(id) ? SearchFilterTheme.chipChosenLabel : SearchFilterTheme.chipLabel,
        reason: id,
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byKey(_chip(id)), matching: find.byType(DecoratedBox)),
      );
      expect((box.decoration as BoxDecoration).color, SearchFilterTheme.chip, reason: id);
    }
  });

  testWidgets('every chip is a button that reads as chosen or not and answers accessibility presses', (tester) async {
    final semantics = tester.ensureSemantics();
    final panel = await _show(tester);
    const chosen = {'order-relevance', 'published-any', 'length-any'};
    final labels = {
      for (final order in FilterOrder.values) 'order-${order.name}': order.label,
      for (final published in FilterPublished.values) 'published-${published.name}': published.label,
      for (final length in FilterLength.values) 'length-${length.name}': length.label,
    };
    for (final MapEntry(key: id, value: label) in labels.entries) {
      expect(
        tester.getSemantics(find.byKey(_chip(id))),
        isSemantics(
          label: label,
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
          isSelected: chosen.contains(id),
        ),
        reason: id,
      );
    }

    final node = tester.getSemantics(find.byKey(_chip('published-day')));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    tester.semantics.tap(find.semantics.byLabel('120分钟+'));
    await tester.pump();
    expect(panel.changes, [
      const SearchFilters(published: FilterPublished.day),
      const SearchFilters(published: FilterPublished.day, length: FilterLength.over120),
    ]);
    semantics.dispose();
  });

  group('look-alike (58)', () {
    Future<void> useSystemFont(WidgetTester tester) async {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      BiliFonts.family = BiliFonts.system;
      await tester.runAsync(loadSystemFontStandIns);
    }

    testWidgets('digits sit a pixel apart and a point from Chinese under the system font only', (tester) async {
      List<(String, double?)> runs(String id) => [
        for (final span
            in (tester.widget<Text>(find.descendant(of: find.byKey(_chip(id)), matching: find.byType(Text))).textSpan!
                    as TextSpan)
                .children!
                .cast<TextSpan>())
          (span.text!, span.style?.letterSpacing),
      ];
      await _show(tester);
      expect(runs('length-over120'), [('120分钟+', null)]);

      await useSystemFont(tester);
      await _show(tester);
      expect(runs('length-over120'), [('12', 1 / 3), ('0', 1 / 3 + 1), ('分', null), ('钟', 1.0), ('+', null)]);
      expect(runs('length-from10to30'), [('10-3', 1 / 3), ('0', 1 / 3 + 1), ('分钟', null)]);
      expect(runs('published-week'), [('最近一周', null)]);
    });

    testWidgets('titles and chips sit where 58 draws them, the panel as tall as its rows', (tester) async {
      await useSystemFont(tester);
      await _show(tester);
      Rect chip(String id) => tester.getRect(find.byKey(_chip(id)));

      // 58's chips in pt: 12, 117, 222 and 327 across, 99 × 26.
      expect(chip('order-relevance'), _near(const Rect.fromLTWH(12, 185, 99, 26)));
      expect(chip('order-danmaku'), _near(const Rect.fromLTWH(327, 185, 99, 26)));
      expect(chip('published-week'), _near(const Rect.fromLTWH(222, 254, 99, 26)));
      // Without 58's date range, 内容时长 follows 发布时间's chips 69 down as 发布时间 follows 排序方式's, not 105.
      const dateRows = 105 - 69.0;
      expect(chip('length-any'), _near(const Rect.fromLTWH(12, 359 - dateRows, 99, 26)));
      expect(chip('length-over120'), _near(const Rect.fromLTWH(117, 395 - dateRows, 99, 26)));

      expect(tester.getCenter(find.text('排序方式')).dy, moreOrLessEquals(166.33, epsilon: 0.5));
      expect(tester.getCenter(find.text('发布时间')).dy, moreOrLessEquals(235.33, epsilon: 0.5));
      expect(tester.getTopLeft(find.text('排序方式')).dx, 12);

      final panel = tester.getRect(find.byType(SearchFilterPanel));
      expect(panel.bottom, moreOrLessEquals(chip('length-over120').bottom + SearchFilterTheme.bottom, epsilon: 0.01));

      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/58-ours.png');
    });
  });
}

Matcher _near(Rect expected) => predicate<Rect>(
  (rect) =>
      (rect.left - expected.left).abs() < 0.01 &&
      (rect.top - expected.top).abs() < 0.01 &&
      (rect.width - expected.width).abs() < 0.01 &&
      (rect.height - expected.height).abs() < 0.01,
  'near $expected',
);
