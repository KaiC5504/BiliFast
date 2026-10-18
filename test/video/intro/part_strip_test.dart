import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/collection_row.dart';
import 'package:bilifast/video/intro/part_strip.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

List<Episode> parts(int count, {int? current}) => [
  for (var i = 0; i < count; i++) Episode(bvid: 'BVp', cid: i, title: 'P${i + 1} 第${i + 1}部分', current: i == current),
];

Future<void> show(WidgetTester tester, Widget strip) async {
  tester.view.physicalSize = const Size(440, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Align(alignment: Alignment.topCenter, child: strip),
      ),
    ),
  );
}

Finder chip(int cid) => find.byKey(ValueKey('part-$cid'));

void main() {
  testWidgets('the header says 选集 with the playing part among them, and opens the list', (tester) async {
    var opened = 0;
    await show(tester, PartStrip(parts: parts(5, current: 1), onChoose: (_) {}, onOpenList: () => opened++));

    expect(find.text('选集'), findsOneWidget);
    expect(find.text('2/5'), findsOneWidget);
    expect(find.byType(Chevron), findsOneWidget);
    await tester.tap(find.text('2/5'));
    expect(opened, 1);
  });

  testWidgets('without a playing part the header gives the count', (tester) async {
    await show(tester, PartStrip(parts: parts(4), onChoose: (_) {}, onOpenList: () {}));

    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('a chip plays its part; the playing one does nothing', (tester) async {
    final chosen = <int>[];
    await show(
      tester,
      PartStrip(parts: parts(3, current: 0), onChoose: (part) => chosen.add(part.cid), onOpenList: () {}),
    );

    await tester.tap(chip(1));
    await tester.tap(chip(0));
    await tester.pumpAndSettle();
    expect(chosen, [1]);
  });

  testWidgets('the playing chip is outlined pink with pink text and the playing bars; the others are grey', (
    tester,
  ) async {
    await show(tester, PartStrip(parts: parts(3, current: 1), onChoose: (_) {}, onOpenList: () {}));

    BoxDecoration decoration(int cid) =>
        tester
                .widget<AnimatedContainer>(find.descendant(of: chip(cid), matching: find.byType(AnimatedContainer)))
                .decoration!
            as BoxDecoration;
    Color? textColour(int cid) => tester
        .widget<RichText>(find.descendant(of: chip(cid), matching: find.byType(RichText)).first)
        .text
        .style
        ?.color;

    expect((decoration(1).border! as Border).top.color, BiliColors.pink);
    expect(textColour(1), BiliColors.pink);
    expect(find.descendant(of: chip(1), matching: find.byType(PlayingBars)), findsOneWidget);
    expect((decoration(0).border! as Border).top.color, BiliColors.softGrey);
    expect(decoration(0).color, BiliColors.softGrey);
    expect(textColour(0), BiliColors.text);
    expect(find.descendant(of: chip(0), matching: find.byType(PlayingBars)), findsNothing);
    expect(tester.getSize(chip(0)), const Size(IntroListTheme.partChipWidth, IntroListTheme.partChipHeight));
  });

  testWidgets('opens scrolled to the playing chip, and follows it when another part plays', (tester) async {
    await show(tester, PartStrip(parts: parts(20, current: 15), onChoose: (_) {}, onOpenList: () {}));

    final playing = tester.getRect(chip(15));
    expect(playing.left, greaterThanOrEqualTo(0));
    expect(playing.right, lessThanOrEqualTo(440));
    expect(chip(0), findsNothing);

    await show(tester, PartStrip(parts: parts(20, current: 2), onChoose: (_) {}, onOpenList: () {}));
    await tester.pumpAndSettle();
    final now = tester.getRect(chip(2));
    expect(now.left, greaterThanOrEqualTo(0));
    expect(now.right, lessThanOrEqualTo(440));
  });

  testWidgets('the last chip ends the strip, not past it', (tester) async {
    await show(tester, PartStrip(parts: parts(10, current: 9), onChoose: (_) {}, onOpenList: () {}));

    expect(tester.getRect(chip(9)).right, moreOrLessEquals(440 - BiliMetrics.gutter));
  });

  testWidgets('the header and each chip are buttons for accessibility; the playing chip is selected', (tester) async {
    final handle = tester.ensureSemantics();
    final chosen = <int>[];
    var opened = 0;
    await show(
      tester,
      PartStrip(parts: parts(3, current: 0), onChoose: (part) => chosen.add(part.cid), onOpenList: () => opened++),
    );

    final header = tester.getSemantics(find.bySemanticsLabel('选集'));
    expect(header, isSemantics(isButton: true, hasTapAction: true, value: '1/3'));
    header.owner!.performAction(header.id, SemanticsAction.tap);
    expect(opened, 1);

    expect(
      tester.getSemantics(find.bySemanticsLabel('P1 第1部分')),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true),
    );
    final other = tester.getSemantics(find.bySemanticsLabel('P2 第2部分'));
    other.owner!.performAction(other.id, SemanticsAction.tap);
    expect(chosen, [1]);
    handle.dispose();
  });

  testWidgets('draws nothing without parts', (tester) async {
    await show(tester, PartStrip(parts: const [], onChoose: (_) {}, onOpenList: () {}));

    expect(tester.getSize(find.byType(PartStrip)), Size.zero);
  });
}
