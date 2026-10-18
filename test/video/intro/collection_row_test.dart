import 'package:bilifast/shared/menu.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/collection_row.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

List<Episode> episodes(int count, {int? current}) => [
  for (var i = 0; i < count; i++) Episode(bvid: 'BV$i', cid: i, title: '第$i集', current: i == current),
];

Future<void> show(WidgetTester tester, Widget row) async {
  tester.view.physicalSize = const Size(440, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Align(alignment: Alignment.topCenter, child: row),
      ),
    ),
  );
}

void main() {
  test('the place is the playing episode among all of them, or only the count when none plays', () {
    expect(CollectionRow.place(episodes(221, current: 220)), '221/221');
    expect(CollectionRow.place(episodes(3, current: 0)), '1/3');
    expect(CollectionRow.place(episodes(5)), '5');
  });

  testWidgets('shows 合集 · its name and the playing place, in a 36 pt card inside the gutters', (tester) async {
    await show(tester, CollectionRow(title: 'MAD系列', episodes: episodes(221, current: 220), onOpen: () {}));

    expect(find.text('合集 · MAD系列'), findsOneWidget);
    expect(find.text('221/221'), findsOneWidget);
    expect(find.byType(PlayingBars), findsOneWidget);
    final card = tester.getRect(find.byType(PressHighlight));
    expect(card.left, BiliMetrics.gutter);
    expect(card.right, 440 - BiliMetrics.gutter);
    expect(card.top, moreOrLessEquals(IntroListTheme.sectionTop));
    expect(card.height, IntroListTheme.collectionHeight);
    expect(
      tester.getSize(find.byType(CollectionRow)).height,
      moreOrLessEquals(IntroListTheme.sectionTop + IntroListTheme.collectionHeight + IntroListTheme.sectionBottom),
    );
  });

  testWidgets('a long name gives way to the place, which stays whole', (tester) async {
    await show(tester, CollectionRow(title: '一个非常非常长的合集名字' * 4, episodes: episodes(12, current: 3), onOpen: () {}));

    expect(tester.takeException(), isNull);
    expect(find.text('4/12'), findsOneWidget);
    expect(tester.getRect(find.text('4/12')).right, lessThan(440 - BiliMetrics.gutter));
  });

  testWidgets('a tap opens the 选集 sheet', (tester) async {
    var opened = 0;
    await show(tester, CollectionRow(title: 'MAD系列', episodes: episodes(3, current: 1), onOpen: () => opened++));

    await tester.tap(find.text('合集 · MAD系列'));
    expect(opened, 1);
  });

  testWidgets('is one button for accessibility, with the place as its value', (tester) async {
    final handle = tester.ensureSemantics();
    var opened = 0;
    await show(tester, CollectionRow(title: 'MAD系列', episodes: episodes(3, current: 1), onOpen: () => opened++));

    final node = tester.getSemantics(find.bySemanticsLabel('合集 · MAD系列'));
    expect(node, isSemantics(isButton: true, hasTapAction: true, value: '2/3'));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(opened, 1);
    handle.dispose();
  });

  testWidgets('draws nothing without episodes', (tester) async {
    await show(tester, CollectionRow(title: 'MAD系列', episodes: const [], onOpen: () {}));

    expect(tester.getSize(find.byType(CollectionRow)), Size.zero);
  });
}
