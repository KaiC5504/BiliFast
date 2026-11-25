import 'package:bili_core/api.dart' show Chapter;
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'landscape_chrome_test.dart' show Rig;

const chapters = [Chapter(from: 0, to: 108, title: '1'), Chapter(from: 108, to: 241, title: '2.3')];

final _chapters = find.byKey(const ValueKey('landscape-chapters'));
final _title = find.byKey(const ValueKey('landscape-chapter-title'));

String? titleOf(WidgetTester tester) => _title.evaluate().isEmpty ? null : tester.widget<Text>(_title).data;

Future<Rig> mountAt(WidgetTester tester, double seconds, {List<Chapter> parts = chapters}) async {
  final rig = Rig();
  rig.session
    ..duration.value = 241
    ..chapters = parts;
  await rig.mount(tester);
  rig.session.readout.seconds.value = seconds;
  await tester.pump();
  return rig;
}

void main() {
  testWidgets('without chapters the line is the time alone, as 04', (tester) async {
    await mountAt(tester, 108, parts: const []);

    expect(find.text('01:48/04:01'), findsOne);
    expect(_chapters, findsNothing);
    expect(find.text('章节'), findsNothing);
  });

  testWidgets("with chapters it reads 01:48/04:01 · 章节 · 2.3 › as 274: the chapter holding the position", (
    tester,
  ) async {
    final rig = await mountAt(tester, 108);

    expect(find.text('01:48/04:01'), findsOne);
    expect(find.descendant(of: _chapters, matching: find.text('章节')), findsOne);
    expect(titleOf(tester), '2.3');
    // Two dots and the chevron, in that order after the time.
    final time = tester.getRect(find.byKey(const ValueKey('landscape-time')));
    final word = tester.getRect(find.text('章节'));
    final title = tester.getRect(_title);
    expect(time.right, lessThan(word.left));
    expect(word.right, lessThan(title.left));
    expect(title.center.dy, closeTo(time.center.dy, 0.01));
    final marks = find.descendant(of: _chapters, matching: find.byType(CustomPaint));
    expect(marks, findsNWidgets(3));
    final first = tester.getRect(marks.at(0)), second = tester.getRect(marks.at(1)), last = tester.getRect(marks.at(2));
    expect(first.width, closeTo(ChapterLineTheme.dot, 0.01));
    expect(word.left - first.right, closeTo(ChapterLineTheme.dotGap, 0.01));
    expect(second.left - word.right, closeTo(ChapterLineTheme.dotGap, 0.01));
    expect(title.left - second.right, closeTo(ChapterLineTheme.dotGap, 0.01));
    expect(last.left - title.right, closeTo(ChapterLineTheme.chevronGap, 0.01));
    expect(last.width, closeTo(ChapterLineTheme.chevronWidth, 0.01));
    expect(last.height, closeTo(ChapterLineTheme.chevronHeight, 0.01));
    expect(first.center.dy, closeTo(time.center.dy - ChapterLineTheme.dotLift, 0.01));
    expect(last.center.dy, closeTo(time.center.dy - ChapterLineTheme.chevronLift, 0.01));

    rig.session.readout.seconds.value = 50;
    await tester.pump();
    expect(find.text('00:50/04:01'), findsOne);
    expect(titleOf(tester), '1');
  });

  testWidgets('it follows a drag as the time does, and the playhead again once the drag gives up', (tester) async {
    final rig = await mountAt(tester, 50);
    expect(titleOf(tester), '1');

    rig.session.scrub(200);
    await tester.pump();
    expect(find.text('03:20/04:01'), findsOne);
    expect(titleOf(tester), '2.3');

    rig.session.cancelScrub();
    await tester.pump();
    expect(find.text('00:50/04:01'), findsOne);
    expect(titleOf(tester), '1');
  });

  testWidgets('before the first chapter, or in one without a title, it reads 章节 › alone', (tester) async {
    final rig = await mountAt(
      tester,
      5,
      parts: const [Chapter(from: 10, to: 100, title: '开场'), Chapter(from: 100, to: 241, title: '')],
    );
    expect(find.text('章节'), findsOne);
    expect(_title, findsNothing);
    expect(find.descendant(of: _chapters, matching: find.byType(CustomPaint)), findsNWidgets(2));

    rig.session.readout.seconds.value = 50;
    await tester.pump();
    expect(titleOf(tester), '开场');

    rig.session.readout.seconds.value = 150;
    await tester.pump();
    expect(_title, findsNothing);
  });

  testWidgets('a tap on the 章节 part opens its panel and keeps the controls up; the time opens nothing', (
    tester,
  ) async {
    final rig = await mountAt(tester, 108);

    await tester.tap(find.byKey(const ValueKey('landscape-time')), warnIfMissed: false);
    expect(rig.panels.value, isNull);

    await tester.tap(_chapters);
    expect(rig.panels.value, PlayerPanel.chapters);
    expect(rig.chrome.shows, greaterThan(0));
  });

  testWidgets('the 章节 part presses through accessibility, as VoiceOver and the Windows test driver do', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final rig = await mountAt(tester, 108);

    tester.semantics.tap(find.semantics.byLabel('章节'));
    expect(rig.panels.value, PlayerPanel.chapters);
    semantics.dispose();
  });

  testWidgets('with 章节进度条 off the part still shows and opens the panel, the only way back to the switch', (
    tester,
  ) async {
    final rig = await mountAt(tester, 108);
    rig.session
      ..chapterBar = false
      ..changed();
    await tester.pump();

    expect(find.descendant(of: _chapters, matching: find.text('章节')), findsOne);
    expect(titleOf(tester), '2.3');
    await tester.tap(_chapters);
    expect(rig.panels.value, PlayerPanel.chapters);
  });

  testWidgets("the part's target runs from the line down to the bar, and the bar and time stay where 04 has them", (
    tester,
  ) async {
    await mountAt(tester, 108);

    final target = tester.getRect(_chapters);
    final time = tester.getRect(find.byKey(const ValueKey('landscape-time')));
    final bar = tester.getRect(find.byKey(const ValueKey('landscape-bar')));
    expect(target.top, closeTo(time.center.dy - BiliMetrics.chromeTimeBox / 2, 0.01));
    expect(target.bottom, closeTo(bar.top, 0.01));
    expect(target.height, BiliMetrics.chromeTimeBox + BiliMetrics.chromeBarTop);
    expect(bar.center.dy, closeTo(359, 1));
    expect(time.left, 63);
  });

  testWidgets('held, the bar takes the whole line away with the time, and lifting brings it back', (tester) async {
    final rig = await mountAt(tester, 108);

    rig.chrome.holdBar(true);
    await tester.pumpAndSettle();
    final fade = tester.widget<AnimatedOpacity>(
      find.ancestor(of: _chapters, matching: find.byType(AnimatedOpacity)).first,
    );
    expect(fade.opacity, 0);
    await tester.tap(_chapters, warnIfMissed: false);
    expect(rig.panels.value, isNull);

    rig.chrome.holdBar(false);
    await tester.pumpAndSettle();
    await tester.tap(_chapters);
    expect(rig.panels.value, PlayerPanel.chapters);
  });
}
