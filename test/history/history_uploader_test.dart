import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/history/history_model.dart';
import 'package:bilifast/history/watch_history_page.dart';
import 'package:bilifast/shared/menu.dart' show PressHighlight;
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import '../support/space_host.dart';
import 'history_fakes.dart';

void main() {
  late List<VideoRoute> opened;

  setUp(() => opened = []);

  const face = 'https://i0.hdslb.com/bfs/face/history-501.jpg';
  final watched = historyItem(1, viewAt: wall(19, 3, 2), title: '看过的视频', ownerFace: face);

  Future<void> show(WidgetTester tester, HistoryItem item) async {
    final model = HistoryModel(
      api: FakePageApi()..historyItems = [item],
      isLoggedIn: () => true,
      now: () => wallTime(19, 9, 8),
      utcOffset: testOffset,
      logger: Logger(session: 'test'),
    );
    addTearDown(model.dispose);
    await pumpSpaceHost(
      tester,
      SizedBox(
        width: 440,
        height: 956,
        child: WatchHistoryPage(model: model, open: (context, route) => opened.add(route)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder name(HistoryItem item) => find.byKey(ValueKey('history-uploader-${item.id}'));
  Finder row(HistoryItem item) => find.byKey(ValueKey('history-${item.id}'));
  FinderBase<SemanticsNode> nameButton(HistoryItem item) => find.semantics.byPredicate(
    (node) => node.label == item.ownerName && node.getSemanticsData().hasAction(SemanticsAction.tap),
  );

  Color? highlight(WidgetTester tester, HistoryItem item) =>
      (tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.descendant(of: row(item), matching: find.byType(PressHighlight)),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration)
          .color;

  testWidgets("the uploader's name opens their space with the face, not the video", (tester) async {
    await show(tester, watched);
    await tester.tap(name(watched));
    await pumpRoute(tester);
    final space = openSpaces(tester).single;
    expect((space.mid, space.name, space.face), (501, 'UP1', face));
    expect(opened, isEmpty);
  });

  testWidgets("a press on the name doesn't light the row", (tester) async {
    await show(tester, watched);
    final gesture = await tester.startGesture(tester.getCenter(name(watched)));
    await tester.pump(kPressTimeout);
    expect(highlight(tester, watched), isNull);
    await gesture.up();
    await pumpRoute(tester);
    expect(openSpaces(tester), hasLength(1));
  });

  testWidgets('the target is the UP glyph and the name, with a little room above and below', (tester) async {
    await show(tester, watched);
    final target = tester.getRect(name(watched));
    final drawn = tester.getRect(find.descendant(of: row(watched), matching: find.text('UP1')));
    expect(target.right, moreOrLessEquals(drawn.right, epsilon: 0.01));
    expect(target.left, moreOrLessEquals(drawn.left - HistoryTheme.glyphBox - HistoryTheme.glyphGap, epsilon: 0.01));
    expect(target.top, lessThan(drawn.top));
    expect(target.bottom - drawn.bottom, moreOrLessEquals(HistoryTheme.metaGap / 2, epsilon: 0.01));

    await tester.tapAt(Offset(target.left + 2, target.top + 1));
    await pumpRoute(tester);
    expect(openSpaces(tester), hasLength(1), reason: 'the slop above the line and the UP glyph count');
  });

  testWidgets('the rest of the row still opens the video', (tester) async {
    await show(tester, watched);
    final target = tester.getRect(name(watched));
    await tester.tapAt(Offset(target.right + 12, target.center.dy));
    await tester.pump();
    expect(opened, hasLength(1));
    expect(openSpaces(tester), isEmpty);
  });

  testWidgets('without a mid the name is part of the row', (tester) async {
    final semantics = tester.ensureSemantics();
    final anonymous = historyItem(2, viewAt: wall(19, 3, 2), ownerMid: 0);
    await show(tester, anonymous);
    expect(name(anonymous), findsNothing);
    expect(nameButton(anonymous), findsNothing);
    await tester.tap(find.descendant(of: row(anonymous), matching: find.text('UP2')), warnIfMissed: false);
    await pumpRoute(tester);
    expect(opened, hasLength(1));
    expect(openSpaces(tester), isEmpty);
    semantics.dispose();
  });

  testWidgets('the name is its own button, labelled with the name, that opens the space', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, watched);
    expect(tester.getSemantics(name(watched)), isSemantics(label: 'UP1', isButton: true, hasTapAction: true));
    tester.semantics.tap(nameButton(watched));
    await pumpRoute(tester);
    expect(openSpaces(tester).single.mid, 501);
    expect(opened, isEmpty);
    semantics.dispose();
  });

  testWidgets("VoiceOver hears the name in the row's label and on its button, nowhere else", (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, watched);
    final labels = [
      for (final node in find.semantics.byPredicate((node) => node.label.contains('UP1')).evaluate()) node.label,
    ];
    expect(labels, hasLength(2));
    expect(labels, contains('UP1'));
    expect(labels, contains(startsWith('看过的视频，UP1，')));
    expect(find.semantics.byPredicate((node) => node.label.contains('看过的视频')).evaluate(), hasLength(1));
    expect(
      find.semantics.byPredicate(
        (node) => node.label == '更多操作' && node.getSemanticsData().hasAction(SemanticsAction.tap),
      ),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('a mid without a name gets no target', (tester) async {
    final nameless = historyItem(3, viewAt: wall(19, 3, 2), ownerName: '');
    await show(tester, nameless);
    expect(row(nameless), findsOne);
    expect(name(nameless), findsNothing);
  });

  testWidgets('a name cut short by the line: the target ends where the drawn name does', (tester) async {
    final long = historyItem(4, viewAt: wall(19, 3, 2), ownerName: '一个很长很长的名字' * 6);
    await show(tester, long);
    final drawn = find.descendant(of: row(long), matching: find.text(long.ownerName));
    expect(tester.renderObject<RenderParagraph>(drawn).didExceedMaxLines, isTrue);
    expect(tester.getRect(name(long)).right, moreOrLessEquals(tester.getRect(drawn).right, epsilon: 0.01));
  });
}
