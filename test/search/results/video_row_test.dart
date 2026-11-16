import 'package:bili_core/api.dart';
import 'package:bilifast/search/results/video_row.dart';
import 'package:bilifast/shared/menu.dart' show PressHighlight;
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../../support/space_host.dart';
import 'results_support.dart';

void main() {
  late List<SearchVideo> opened;
  late int mores;

  setUp(() {
    opened = [];
    mores = 0;
  });

  Future<void> pumpRow(WidgetTester tester, SearchVideo row) => pumpSpaceHost(
    tester,
    SizedBox(
      width: 440,
      child: SearchVideoRow(
        video: row,
        now: DateTime(2026, 11, 16),
        onOpen: () => opened.add(row),
        onMore: () => mores++,
      ),
    ),
  );

  final name = find.byKey(const ValueKey('search-uploader-BV1search1'));
  // The drawn line is read as a label too; the button is the one that takes a tap.
  final nameButton = find.semantics.byPredicate(
    (node) => node.label == '测试作者' && node.getSemanticsData().hasAction(SemanticsAction.tap),
  );

  Color? highlight(WidgetTester tester) =>
      (tester
                  .widget<DecoratedBox>(
                    find.descendant(of: find.byType(PressHighlight), matching: find.byType(DecoratedBox)),
                  )
                  .decoration
              as BoxDecoration)
          .color;

  testWidgets("the uploader's name opens their space, not the video", (tester) async {
    await pumpRow(tester, video(1, author: '测试作者'));
    await tester.tap(name);
    await pumpRoute(tester);
    final space = openSpaces(tester).single;
    expect((space.mid, space.name), (501, '测试作者'));
    expect(opened, isEmpty);
  });

  testWidgets("the space gets the row's face, and none for a row without one", (tester) async {
    const face = 'https://i1.hdslb.com/bfs/face/made-up-face.jpg';
    final base = video(1, author: '测试作者');
    final withFace = SearchVideo(
      aid: base.aid,
      bvid: base.bvid,
      title: base.title,
      author: base.author,
      mid: base.mid,
      face: face,
      cover: base.cover,
      play: base.play,
      danmaku: base.danmaku,
      duration: base.duration,
      published: base.published,
    );
    await pumpRow(tester, withFace);
    await tester.tap(name);
    await pumpRoute(tester);
    expect(openSpaces(tester).single.face, face);

    await closeSpace(tester);
    await pumpRow(tester, base);
    await tester.tap(name);
    await pumpRoute(tester);
    expect(openSpaces(tester).single.face, isNull);
  });

  testWidgets("a press on the name doesn't light the row", (tester) async {
    await pumpRow(tester, video(1));
    final gesture = await tester.startGesture(tester.getCenter(name));
    await tester.pump(kPressTimeout);
    expect(highlight(tester), isNull);
    await gesture.up();
    await pumpRoute(tester);
    expect(openSpaces(tester), hasLength(1));
  });

  testWidgets('the target is the UP glyph and the name, with a little room above and below', (tester) async {
    await pumpRow(tester, video(1, author: '测试作者'));
    final target = tester.getRect(name);
    final drawn = tester.getRect(find.text('测试作者', findRichText: true).first);
    expect(target.right, moreOrLessEquals(drawn.right, epsilon: 0.01));
    expect(target.height, greaterThan(SearchResultTheme.metaLine));

    await tester.tapAt(Offset(target.left + 2, target.top + 1));
    await pumpRoute(tester);
    expect(openSpaces(tester), hasLength(1), reason: 'the slop above the line and the UP glyph count');
  });

  testWidgets('the rest of the row still opens the video, and ⋮ its sheet', (tester) async {
    await pumpRow(tester, video(1));
    final target = tester.getRect(name);
    await tester.tapAt(Offset(target.right + 12, target.center.dy));
    await tester.tap(find.byKey(const ValueKey('search-title-BV1search1')), warnIfMissed: false);
    await tester.tap(find.byKey(const ValueKey('search-cover-placeholder')), warnIfMissed: false);
    await tester.tap(find.byKey(const ValueKey('search-more-BV1search1')));
    await pumpRoute(tester);
    expect(opened, hasLength(3));
    expect(mores, 1);
    expect(openSpaces(tester), isEmpty);
  });

  testWidgets('without a mid the name is part of the row', (tester) async {
    final row = SearchVideo(
      aid: 1001,
      bvid: 'BV1search1',
      title: HighlightedText.plain('测试视频标题'),
      author: '测试作者',
      mid: 0,
      cover: '',
      play: 10,
      danmaku: 0,
      duration: 60,
      published: null,
    );
    final semantics = tester.ensureSemantics();
    await pumpRow(tester, row);
    expect(name, findsNothing);
    expect(nameButton, findsNothing);
    await tester.tap(find.text('测试作者', findRichText: true), warnIfMissed: false);
    await pumpRoute(tester);
    expect(opened, hasLength(1));
    expect(openSpaces(tester), isEmpty);
    semantics.dispose();
  });

  testWidgets("the name is its own button, labelled with the name, that opens the space", (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRow(tester, video(1, author: '测试作者'));
    expect(tester.getSemantics(name), isSemantics(label: '测试作者', isButton: true, hasTapAction: true));
    tester.semantics.tap(nameButton);
    await pumpRoute(tester);
    expect(openSpaces(tester).single.mid, 501);
    expect(opened, isEmpty);
    semantics.dispose();
  });
}
