import 'package:bili_core/api.dart' show Chapter;
import 'package:bilifast/player_ui/chapter_strip.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'landscape_chapter_line_test.dart' show chapters;
import 'landscape_chrome_test.dart' show Rig;

final _strip = find.byKey(const ValueKey('chapter-strip'));

Future<Rig> mount(WidgetTester tester, {List<Chapter> parts = chapters}) async {
  final rig = Rig();
  rig.session
    ..duration.value = 241
    ..chapters = parts;
  await rig.mount(tester);
  return rig;
}

void main() {
  testWidgets('the strip shows only under the open 章节 panel with 章节进度条 on (273), never for hidden controls', (
    tester,
  ) async {
    final rig = await mount(tester);
    expect(_strip, findsNothing);

    rig.chrome.hide();
    await tester.pumpAndSettle();
    expect(_strip, findsNothing, reason: 'KaiC: nothing there while the controls are only hidden');

    rig.panels.open(PlayerPanel.chapters);
    await tester.pumpAndSettle();
    expect(_strip, findsOne);

    rig.session
      ..chapterBar = false
      ..changed();
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);

    rig.session
      ..chapterBar = true
      ..changed();
    await tester.pumpAndSettle();
    expect(_strip, findsOne);

    rig.panels.open(PlayerPanel.quality);
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);

    rig.panels.close();
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
  });

  testWidgets('a video without chapters has none, even with the panel open', (tester) async {
    final rig = await mount(tester, parts: const []);
    rig.panels.open(PlayerPanel.chapters);
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
  });

  testWidgets("273's layout: the chapters over the screen's whole width, a rule where each but the first starts, each "
      'title centred on its stretch', (tester) async {
    final rig = await mount(tester);
    rig.panels.open(PlayerPanel.chapters);
    await tester.pumpAndSettle();

    expect(tester.getRect(_strip), const Rect.fromLTRB(0, 440 - ChapterStripTheme.height, 956, 440));
    expect(find.byKey(const ValueKey('chapter-strip-rule-0.0')), findsNothing);
    final rule = tester.getRect(find.byKey(const ValueKey('chapter-strip-rule-108.0')));
    expect(rule.center.dx, closeTo(956 * 108 / 241, 0.01));
    expect(rule.width, ChapterStripTheme.rule);
    expect(rule.height, ChapterStripTheme.height);

    final first = find.descendant(of: _strip, matching: find.text('1'));
    final second = find.descendant(of: _strip, matching: find.text('2.3'));
    expect(tester.getCenter(first).dx, closeTo(956 * 54 / 241, 0.01));
    expect(tester.getCenter(second).dx, closeTo(956 * (108 + 241) / 2 / 241, 0.01));
    expect(tester.getCenter(first).dy, closeTo(440 - ChapterStripTheme.titleCentre, 0.01));
    final style = tester.widget<Text>(first).style!;
    expect(style.fontSize, ChapterStripTheme.titleText);
    expect(style.fontWeight, ChapterStripTheme.titleWeight);
    expect(style.color, BiliColors.onVideo);
  });

  testWidgets("the band fades in from clear to 273's grey over its top, and takes no touches", (tester) async {
    final rig = await mount(tester);
    rig.panels.open(PlayerPanel.chapters);
    await tester.pumpAndSettle();

    final band = tester
        .widgetList<DecoratedBox>(find.descendant(of: _strip, matching: find.byType(DecoratedBox)))
        .first
        .decoration as BoxDecoration;
    final gradient = band.gradient! as LinearGradient;
    expect(gradient.colors, [ChapterStripTheme.fillClear, ChapterStripTheme.fill]);
    expect(gradient.stops, [0, ChapterStripTheme.solidFrom]);
    expect(
      tester.widgetList<IgnorePointer>(find.ancestor(of: _strip, matching: find.byType(IgnorePointer))).first.ignoring,
      isTrue,
    );
  });

  group('at its edges', () {
    Future<ValueNotifier<double>> strip(WidgetTester tester, List<Chapter> parts, {double total = 241}) async {
      tester.view
        ..physicalSize = const Size(956, 440)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final duration = ValueNotifier(total);
      addTearDown(duration.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: ChapterStripTheme.height,
              child: ChapterStrip(chapters: parts, duration: duration),
            ),
          ),
        ),
      );
      return duration;
    }

    Finder rule(double from) => find.byKey(ValueKey('chapter-strip-rule-$from'));

    testWidgets('a stretch narrower than twice its title pad keeps its rule but drops its title', (tester) async {
      await strip(tester, const [
        Chapter(from: 0, to: 100, title: 'a'),
        Chapter(from: 100, to: 101, title: 'short'),
        Chapter(from: 101, to: 241, title: 'b'),
      ]);
      expect(956 / 241, lessThan(ChapterStripTheme.titlePad * 2));
      expect(rule(100), findsOne);
      expect(rule(101), findsOne);
      expect(find.text('short'), findsNothing);
      expect(find.text('a'), findsOne);
      expect(find.text('b'), findsOne);
    });

    testWidgets("a chapter running past the duration ends at the strip's edge; one starting past it has no rule", (
      tester,
    ) async {
      await strip(tester, const [
        Chapter(from: 0, to: 200, title: 'a'),
        Chapter(from: 200, to: 300, title: 'tail'),
        Chapter(from: 260, to: 320, title: 'past'),
      ]);
      expect(tester.getCenter(find.text('tail')).dx, closeTo((956 * 200 / 241 + 956) / 2, 0.01));
      expect(rule(200), findsOne);
      expect(rule(260), findsNothing);
      expect(find.text('past'), findsNothing);
    });

    testWidgets('a duration of 0 draws nothing until one arrives', (tester) async {
      final duration = await strip(tester, chapters, total: 0);
      expect(_strip, findsNothing);
      expect(find.text('1'), findsNothing);

      duration.value = 241;
      await tester.pump();
      expect(_strip, findsOne);
      expect(find.text('2.3'), findsOne);
    });
  });

  testWidgets('the bar draws the chapters while 章节进度条 is on, and none with it off', (tester) async {
    final rig = await mount(tester);
    SeekBar bar() => tester.widget<SeekBar>(find.byType(SeekBar));
    expect(bar().chapters, chapters);

    rig.session
      ..chapterBar = false
      ..changed();
    await tester.pump();
    expect(bar().chapters, isEmpty);

    rig.session
      ..chapterBar = true
      ..changed();
    await tester.pump();
    expect(bar().chapters, chapters);
  });
}
