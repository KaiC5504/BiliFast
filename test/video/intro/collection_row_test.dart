import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bilifast/shared/menu.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/collection_row.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('the playing mark is tall, short, tall: 1.72 wide bars 4.2 apart, centred on the line (font-check 02)', (
    tester,
  ) async {
    const scale = 3.0;
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: const PlayingBars(color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final (width, height, alpha) = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: scale);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final size = (image.width, image.height);
      image.dispose();
      return (size.$1, size.$2, [for (var i = 0; i < size.$1 * size.$2; i++) bytes.getUint8(i * 4 + 3) / 255]);
    }))!;
    expect(height / scale, closeTo(IntroListTheme.barsHeight, 0.34));

    double at(int x, int y) => alpha[y * width + x];

    /// The covered length of a run of pixels, and where its middle is, in points.
    (double, double) span(List<double> coverage) {
      var total = 0.0, moment = 0.0;
      for (final (i, value) in coverage.indexed) {
        total += value;
        moment += (i + 0.5) * value;
      }
      return (total / scale, moment / total / scale);
    }

    final bars = <List<int>>[];
    for (var x = 0; x < width; x++) {
      if (Iterable.generate(height, (y) => at(x, y)).reduce(math.max) <= 0.05) continue;
      if (bars.isNotEmpty && bars.last.last == x - 1) {
        bars.last.add(x);
      } else {
        bars.add([x]);
      }
    }
    expect(bars, hasLength(3));
    final across = [
      for (final bar in bars) span([for (var x = 0; x < width; x++) bar.contains(x) ? at(x, height ~/ 2) : 0]),
    ];
    final down = [
      for (final bar in bars) span([for (var y = 0; y < height; y++) bar.map((x) => at(x, y)).reduce(math.max)]),
    ];
    final widths = [for (final (length, _) in across) length];
    final centres = [for (final (_, centre) in across) centre];
    final heights = [for (final (length, _) in down) length];
    final middles = [for (final (_, middle) in down) middle];

    for (final bar in widths) {
      expect(bar, closeTo(1.72, 0.1));
    }
    expect(centres[1] - centres[0], closeTo(4.2, 0.05));
    expect(centres[2] - centres[1], closeTo(4.2, 0.05));
    expect(heights[0], closeTo(11.75, 0.15));
    expect(heights[1], closeTo(17 / 3, 0.15));
    expect(heights[2], closeTo(11, 0.15));
    for (final middle in middles) {
      expect(middle, closeTo(IntroListTheme.barsHeight / 2, 0.05));
    }
  });

  testWidgets('draws nothing without episodes', (tester) async {
    await show(tester, CollectionRow(title: 'MAD系列', episodes: const [], onOpen: () {}));

    expect(tester.getSize(find.byType(CollectionRow)), Size.zero);
  });
}
