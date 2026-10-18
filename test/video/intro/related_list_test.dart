import 'package:bili_core/api.dart' show VideoCard;
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/related_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

VideoCard card(int i, {int duration = 175, int views = 4815000, int danmaku = 17000}) => VideoCard(
  aid: i,
  bvid: 'BV$i',
  cid: i,
  title: '相关视频 $i',
  cover: '',
  duration: duration,
  ownerMid: i,
  ownerName: '学姐圆$i',
  views: views,
  danmaku: danmaku,
  likes: 0,
);

Future<void> show(
  WidgetTester tester,
  List<VideoCard> cards, {
  ValueChanged<VideoCard>? onOpen,
  ValueChanged<VideoCard>? onWatchLater,
  bool still = false,
}) async {
  tester.view.physicalSize = const Size(440, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (still) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: CustomScrollView(
          slivers: [
            RelatedSliver(cards: cards, onOpen: onOpen ?? (_) {}, onWatchLater: onWatchLater ?? (_) {}),
            const SliverToBoxAdapter(child: SizedBox(key: ValueKey('after'), height: 10)),
          ],
        ),
      ),
    ),
  );
}

Finder row(int i) => find.ancestor(of: find.text('相关视频 $i'), matching: find.byType(KeyedSubtree)).first;

void main() {
  test('durations drop the leading zero of the minutes', () {
    expect(RelatedSliver.duration(175), '2:55');
    expect(RelatedSliver.duration(30), '0:30');
    expect(RelatedSliver.duration(754), '12:34');
    expect(RelatedSliver.duration(3723), '1:02:03');
  });

  testWidgets('a row shows the title, UP and its uploader, the counts and the duration', (tester) async {
    await show(tester, [card(1)]);
    await tester.pumpAndSettle();

    expect(find.text('相关视频 1'), findsOneWidget);
    expect(find.text('UP'), findsOneWidget);
    expect(find.text('学姐圆1'), findsOneWidget);
    expect(find.text('481.5万'), findsOneWidget);
    expect(find.text('1.7万'), findsOneWidget);
    expect(find.text('2:55'), findsOneWidget);
  });

  testWidgets('no duration tag on a card without one', (tester) async {
    await show(tester, [card(1, duration: 0)]);
    await tester.pumpAndSettle();

    expect(find.text('0:00'), findsNothing);
  });

  testWidgets('rows are 92 apart under the gap above, the cover 128 × 72 at the gutter', (tester) async {
    await show(tester, [card(1), card(2)]);
    await tester.pumpAndSettle();

    final first = tester.getRect(row(1));
    final second = tester.getRect(row(2));
    expect(first.top, moreOrLessEquals(IntroListTheme.sectionTop));
    expect(first.height, IntroListTheme.relatedRowHeight);
    expect(second.top - first.top, IntroListTheme.relatedRowHeight);
    final cover = tester.getRect(find.descendant(of: row(1), matching: find.byType(ClipRRect)).first);
    expect(cover.left, BiliMetrics.gutter);
    expect(cover.top - first.top, moreOrLessEquals(IntroListTheme.relatedCoverTop));
    expect(cover.size, const Size(IntroListTheme.relatedCoverWidth, IntroListTheme.relatedCoverHeight));
    expect(
      tester.getRect(find.text('相关视频 1')).left,
      BiliMetrics.gutter + IntroListTheme.relatedCoverWidth + IntroListTheme.relatedTextGap,
    );
  });

  testWidgets('the first hairline runs the full width, the ones between rows start 10 in', (tester) async {
    await show(tester, [card(1), card(2)]);
    await tester.pumpAndSettle();

    Rect hairline(int i) => tester.getRect(
      find.descendant(
        of: row(i),
        matching: find.byWidgetPredicate((widget) => widget is ColoredBox && widget.color == BiliColors.divider),
      ),
    );
    expect(hairline(1).left, 0);
    expect(hairline(1).width, 440);
    expect(hairline(2).left, IntroListTheme.relatedDividerInset);
    expect(hairline(2).height, moreOrLessEquals(BiliMetrics.panelHairline));
  });

  testWidgets('a tap on a row opens its video', (tester) async {
    final opened = <String>[];
    await show(tester, [card(1), card(2)], onOpen: (card) => opened.add(card.bvid));
    await tester.pumpAndSettle();

    await tester.tap(find.text('相关视频 2'));
    expect(opened, ['BV2']);
  });

  testWidgets('⋮ opens a menu whose 稍后再看 saves the video and closes it', (tester) async {
    final later = <String>[];
    final opened = <String>[];
    await show(
      tester,
      [card(1), card(2)],
      onWatchLater: (card) => later.add(card.bvid),
      onOpen: (card) => opened.add(card.bvid),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: row(2), matching: find.byKey(const ValueKey('related-more'))));
    await tester.pumpAndSettle();
    expect(find.text('稍后再看'), findsOneWidget);
    expect(opened, isEmpty);

    await tester.tap(find.text('稍后再看'));
    await tester.pumpAndSettle();
    expect(later, ['BV2']);
    expect(find.text('稍后再看'), findsNothing);
  });

  testWidgets('a tap beside the menu closes it without saving', (tester) async {
    final later = <String>[];
    await show(tester, [card(1)], onWatchLater: (card) => later.add(card.bvid));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('related-more')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 900));
    await tester.pumpAndSettle();
    expect(find.text('稍后再看'), findsNothing);
    expect(later, isEmpty);
  });

  testWidgets('each row is a button named by its title, and ⋮ a button of its own', (tester) async {
    final handle = tester.ensureSemantics();
    final opened = <String>[];
    final later = <String>[];
    await show(
      tester,
      [card(1)],
      onOpen: (card) => opened.add(card.bvid),
      onWatchLater: (card) => later.add(card.bvid),
    );
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.bySemanticsLabel('相关视频 1'));
    expect(node, isSemantics(isButton: true, hasTapAction: true));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(opened, ['BV1']);

    final more = tester.getSemantics(find.bySemanticsLabel('更多'));
    expect(more, isSemantics(isButton: true, hasTapAction: true));
    more.owner!.performAction(more.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    final watchLater = tester.getSemantics(find.bySemanticsLabel('稍后再看'));
    watchLater.owner!.performAction(watchLater.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(later, ['BV1']);
    handle.dispose();
  });

  testWidgets('builds only the rows on screen', (tester) async {
    await show(tester, [for (var i = 0; i < 200; i++) card(i)]);
    await tester.pumpAndSettle();

    expect(find.text('相关视频 0'), findsOneWidget);
    expect(find.text('相关视频 199'), findsNothing);
    // 956 pt of screen and the viewport's cache hold about 13 rows of 92.
    expect(find.textContaining('相关视频 ').evaluate().length, lessThan(16));
  });

  testWidgets('an empty list draws nothing, not even its gap', (tester) async {
    await show(tester, const []);

    expect(find.text('UP'), findsNothing);
    expect(tester.getRect(find.byKey(const ValueKey('after'))).top, 0);
  });

  testWidgets('the rows come in when the list arrives, and settle', (tester) async {
    await show(tester, const []);
    await show(tester, [card(1), card(2)]);

    final opacity = find.ancestor(of: find.text('相关视频 2'), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(opacity.first).opacity, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(opacity.first).opacity, 1);
  });

  testWidgets('with reduced motion the rows are simply there', (tester) async {
    await show(tester, [card(1)], still: true);

    expect(find.ancestor(of: find.text('相关视频 1'), matching: find.byType(Opacity)), findsNothing);
  });
}
