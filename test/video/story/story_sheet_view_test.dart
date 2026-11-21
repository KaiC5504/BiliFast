import 'package:bili_core/api.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/page_details.dart' show PageTab;
import 'package:bilifast/video/story/story_sheet.dart';
import 'package:bilifast/video/story/story_sheet_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../comments/comment_fixtures.dart' as fixtures;
import '../../comments/comments_tab_test.dart' show FakeComments, Replies;

const screen = Size(440, 956);

/// A list of 60 rows 50 tall, scrolling with the primary scroll controller as the sheet's tabs do.
Widget list(String name) => ListView.builder(
  key: ValueKey('$name-list'),
  primary: true,
  padding: EdgeInsets.zero,
  itemExtent: 50,
  itemCount: 60,
  itemBuilder: (context, index) => Text('$name $index'),
);

/// A test that lets the sheet finish moving before it ends, as the framework wants no animation left running.
void sheetTest(String description, Future<void> Function(WidgetTester tester) body, {TargetPlatformVariant? variant}) =>
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }, variant: variant ?? TargetPlatformVariant.only(TargetPlatform.android));

late StorySheetController sheet;

Future<void> host(WidgetTester tester, {Widget? intro, Widget? comments, Widget? under, bool still = false}) async {
  tester.view
    ..physicalSize = screen
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  sheet = StorySheetController(vsync: const TestVSync());
  addTearDown(sheet.dispose);
  final replies = ValueNotifier<int?>(98);
  addTearDown(replies.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: Material(
            color: BiliColors.videoBackground,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ?under,
                StorySheetView(
                  controller: sheet,
                  intro: intro ?? list('intro'),
                  comments: comments ?? list('comments'),
                  replies: replies,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> openAt(WidgetTester tester, SheetStop stop, {PageTab tab = PageTab.comments}) async {
  sheet.open(tab);
  if (stop == SheetStop.full) sheet.toggle();
  await settle(tester);
  expect(sheet.position.value, stop.index.toDouble());
}

double sheetTop(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('story-sheet'))).top;

ScrollPosition listOf(WidgetTester tester, String name) => tester
    .state<ScrollableState>(
      find.descendant(of: find.byKey(ValueKey('$name-list')), matching: find.byType(Scrollable), skipOffstage: false),
    )
    .position;

final header = find.byKey(const ValueKey('story-sheet-header'));

/// About 1500 px/s, in moves a frame apart.
Future<void> move(WidgetTester tester, TestGesture gesture, double dy, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  group('showing', () {
    sheetTest('closed, nothing is drawn; opened, the sheet rises to half; closed, it stays built out of sight', (
      tester,
    ) async {
      await host(tester);
      expect(find.byKey(const ValueKey('story-sheet')), findsNothing);
      await openAt(tester, SheetStop.half);
      expect(sheetTop(tester), StorySheetTheme.halfTop);
      expect(find.text('comments 0'), findsOneWidget);
      listOf(tester, 'comments').jumpTo(200);
      sheet.close();
      await settle(tester);
      expect(find.text('comments 4'), findsNothing);
      expect(find.text('comments 4', skipOffstage: false), findsOneWidget);
      // Opened again, the list is where it was left.
      await openAt(tester, SheetStop.half);
      expect(listOf(tester, 'comments').pixels, 200);
    });

    sheetTest('a tab\'s content starts right under the header; 评论 leaves its gap above the list', (tester) async {
      await host(
        tester,
        comments: CommentsTab(
          model: FakeComments(
            comments: [Comment(rpid: 1, member: const CommentMember(mid: 1), message: '一')],
          ),
          callbacks: Replies().callbacks,
        ),
      );
      await openAt(tester, SheetStop.half, tab: PageTab.intro);
      expect(tester.getRect(find.text('intro 0')).top, StorySheetTheme.halfTop + StorySheetTheme.headerHeight);
      sheet.selectTab(PageTab.comments);
      await tester.pump();
      final gap = tester.getRect(find.byKey(const ValueKey('comments-reserve')));
      expect(gap.top, moreOrLessEquals(StorySheetTheme.halfTop + StorySheetTheme.headerHeight));
      expect(gap.height, moreOrLessEquals(StorySheetTheme.commentsGap));
    });

    sheetTest('评论\'s write bar sits at the sheet\'s bottom, half and full, and slides away with it below half', (
      tester,
    ) async {
      await host(
        tester,
        comments: CommentsTab(
          model: FakeComments(
            comments: [Comment(rpid: 1, member: const CommentMember(mid: 1), message: '一')],
          ),
          callbacks: Replies().callbacks,
        ),
      );
      final bar = find.byKey(const ValueKey('comment-bar'));
      await openAt(tester, SheetStop.half);
      expect(tester.getRect(bar).bottom, moreOrLessEquals(screen.height));
      sheet.toggle();
      await settle(tester);
      expect(tester.getRect(bar).bottom, moreOrLessEquals(screen.height));
      sheet.toggle();
      await settle(tester);
      final gesture = await tester.startGesture(const Offset(220, 500));
      await move(tester, gesture, 200);
      final lowered = sheetTop(tester) - StorySheetTheme.halfTop;
      expect(lowered, greaterThan(100));
      expect(tester.getRect(bar).bottom, moreOrLessEquals(screen.height + lowered));
      await gesture.up();
      await settle(tester);
    });

    sheetTest('with Reduce Motion it jumps open', (tester) async {
      await host(tester, still: true);
      sheet.open(PageTab.comments);
      await tester.pump();
      expect(sheetTop(tester), StorySheetTheme.halfTop);
    });
  });

  group('the header strip', () {
    sheetTest('dragged up at 1500 px/s: full; down: half; down again: closed', (tester) async {
      await host(tester);
      await openAt(tester, SheetStop.half);
      await tester.timedDrag(header, const Offset(0, -300), const Duration(milliseconds: 200));
      await settle(tester);
      expect(sheet.stop, SheetStop.full);
      expect(sheetTop(tester), StorySheetTheme.fullTop);

      await tester.timedDrag(header, const Offset(0, 150), const Duration(milliseconds: 100));
      await settle(tester);
      expect(sheet.stop, SheetStop.half);
      expect(sheetTop(tester), StorySheetTheme.halfTop);

      await tester.timedDrag(header, const Offset(0, 150), const Duration(milliseconds: 100));
      await settle(tester);
      expect(sheet.stop, SheetStop.closed);
      expect(sheet.isOpen, isFalse);
    });

    sheetTest('the sheet follows the finger both ways; let go short and still, it jumps back', (tester) async {
      await host(tester);
      await openAt(tester, SheetStop.half);
      final gesture = await tester.startGesture(tester.getCenter(header));
      await move(tester, gesture, -120);
      final raised = StorySheetTheme.halfTop - sheetTop(tester);
      expect(raised, moreOrLessEquals(120, epsilon: 1));
      await move(tester, gesture, 60);
      expect(StorySheetTheme.halfTop - sheetTop(tester), moreOrLessEquals(raised - 60, epsilon: 0.5));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await settle(tester);
      expect(sheet.stop, SheetStop.half);
      expect(sheetTop(tester), StorySheetTheme.halfTop);
    });

    sheetTest('a drag that starts on a tab\'s words moves the sheet too', (tester) async {
      await host(tester);
      await openAt(tester, SheetStop.half);
      await tester.timedDrag(
        find.byKey(const ValueKey('story-sheet-tab-intro')),
        const Offset(0, -300),
        const Duration(milliseconds: 200),
      );
      await settle(tester);
      expect(sheet.stop, SheetStop.full);
      expect(sheet.tab, PageTab.comments);
    });
  });

  group('a tab\'s list', () {
    sheetTest('pulled down at its top, the whole sheet follows and the list stays put; let go still, it springs back', (
      tester,
    ) async {
      await host(tester);
      await openAt(tester, SheetStop.full);
      final gesture = await tester.startGesture(const Offset(220, 500));
      await move(tester, gesture, 150);
      expect(sheetTop(tester) - StorySheetTheme.fullTop, moreOrLessEquals(150, epsilon: 1));
      expect(listOf(tester, 'comments').pixels, 0);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await settle(tester);
      expect(sheet.stop, SheetStop.full);
      expect(sheetTop(tester), StorySheetTheme.fullTop);
      expect(listOf(tester, 'comments').pixels, 0);
    });

    sheetTest('pulled down at its top at 1500 px/s from half, the sheet closes', (tester) async {
      await host(tester);
      await openAt(tester, SheetStop.half);
      await tester.timedDrag(find.text('comments 3'), const Offset(0, 300), const Duration(milliseconds: 200));
      await settle(tester);
      expect(sheet.stop, SheetStop.closed);
      expect(sheet.isOpen, isFalse);
    });

    sheetTest('pushed up, it only scrolls: the sheet never rises, at half or full', (tester) async {
      await host(tester);
      await openAt(tester, SheetStop.half);
      await tester.timedDrag(find.text('comments 3'), const Offset(0, -300), const Duration(milliseconds: 200));
      await settle(tester);
      expect(sheet.stop, SheetStop.half);
      expect(sheetTop(tester), StorySheetTheme.halfTop);
      expect(listOf(tester, 'comments').pixels, greaterThan(250));

      listOf(tester, 'comments').jumpTo(0);
      sheet.toggle();
      await settle(tester);
      await tester.timedDrag(find.text('comments 3'), const Offset(0, -300), const Duration(milliseconds: 200));
      await settle(tester);
      expect(sheet.stop, SheetStop.full);
      expect(sheetTop(tester), StorySheetTheme.fullTop);
      expect(listOf(tester, 'comments').pixels, greaterThan(250));
    });

    sheetTest('pulled down then pushed back up in one drag: the sheet comes back to its stop, then the list scrolls', (
      tester,
    ) async {
      await host(tester);
      await openAt(tester, SheetStop.half);
      final gesture = await tester.startGesture(const Offset(220, 600));
      await move(tester, gesture, 120);
      expect(sheetTop(tester), greaterThan(StorySheetTheme.halfTop + 90));
      await move(tester, gesture, -260, steps: 13);
      expect(sheetTop(tester), StorySheetTheme.halfTop);
      expect(listOf(tester, 'comments').pixels, greaterThan(100));
      await gesture.up();
      await settle(tester);
      expect(sheet.stop, SheetStop.half);
      expect(sheetTop(tester), StorySheetTheme.halfTop);
    });

    sheetTest('scrolled down, a pull first brings the list to its top, then takes the sheet', (tester) async {
      await host(tester);
      await openAt(tester, SheetStop.half);
      listOf(tester, 'comments').jumpTo(80);
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(220, 600));
      await move(tester, gesture, 250);
      expect(listOf(tester, 'comments').pixels, 0);
      expect(sheetTop(tester) - StorySheetTheme.halfTop, moreOrLessEquals(250 - 80, epsilon: 1));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await settle(tester);
      expect(sheet.stop, SheetStop.half);
    });

    sheetTest('简介\'s list hands over the same way', (tester) async {
      await host(tester);
      await openAt(tester, SheetStop.half, tab: PageTab.intro);
      await tester.timedDrag(find.text('intro 3'), const Offset(0, 300), const Duration(milliseconds: 200));
      await settle(tester);
      expect(sheet.stop, SheetStop.closed);
    });

    sheetTest('on iOS the top never bounces while the sheet moves', (tester) async {
      await host(tester);
      await openAt(tester, SheetStop.full);
      final list = listOf(tester, 'comments');
      final seen = <double>[];
      list.addListener(() => seen.add(list.pixels));
      // Stamped, so the release has its speed: 15 pt every 10 ms.
      final gesture = await tester.createGesture();
      await gesture.down(const Offset(220, 500));
      for (var i = 1; i <= 10; i++) {
        await gesture.moveBy(const Offset(0, 15), timeStamp: Duration(milliseconds: 10 * i));
        await tester.pump(const Duration(milliseconds: 10));
        seen.add(list.pixels);
      }
      expect(sheetTop(tester) - StorySheetTheme.fullTop, greaterThan(100));
      await gesture.up(timeStamp: const Duration(milliseconds: 105));
      await settle(tester);
      expect(seen.every((pixels) => pixels == 0), isTrue, reason: '$seen');
      // Let go at speed towards half, it lands there, and the list doesn't fling after.
      expect(sheet.stop, SheetStop.half);
      expect(list.pixels, 0);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('the tabs and the button', () {
    sheetTest('a tap on a tab shows its content; the other is out of sight and the bar moves under the chosen', (
      tester,
    ) async {
      await host(tester);
      await openAt(tester, SheetStop.half);
      final underline = find.byKey(const ValueKey('story-sheet-underline'));
      expect(
        find.descendant(of: find.byKey(const ValueKey('story-sheet-tab-comments')), matching: underline),
        findsOneWidget,
      );
      await tester.tap(find.text('简介'));
      await tester.pump();
      expect(sheet.tab, PageTab.intro);
      expect(find.text('intro 0').hitTestable(), findsOneWidget);
      expect(find.text('comments 0'), findsNothing);
      expect(
        find.descendant(of: find.byKey(const ValueKey('story-sheet-tab-intro')), matching: underline),
        findsOneWidget,
      );
      await tester.tap(find.text('评论'));
      await tester.pump();
      expect(sheet.tab, PageTab.comments);
      expect(find.text('comments 0').hitTestable(), findsOneWidget);
    });

    sheetTest('评论 shows its count in brackets, short as the page shows counts', (tester) async {
      await host(tester);
      await openAt(tester, SheetStop.half);
      expect(find.text('(98)'), findsOneWidget);
    });

    sheetTest('the round button: ⌃⌄ at half goes full, chevrons in at full goes half', (tester) async {
      await host(tester);
      await openAt(tester, SheetStop.half);
      String icon() => (tester.widget<Image>(find.byType(Image)).image as AssetImage).assetName;
      expect(icon(), StorySheetTheme.expandAsset);
      await tester.tap(find.byKey(const ValueKey('story-sheet-button')));
      await settle(tester);
      expect(sheet.stop, SheetStop.full);
      expect(icon(), StorySheetTheme.collapseAsset);
      await tester.tap(find.byKey(const ValueKey('story-sheet-button')));
      await settle(tester);
      expect(sheet.stop, SheetStop.half);
      expect(sheetTop(tester), StorySheetTheme.halfTop);
    });

    sheetTest('评论 asks for its first page only once it shows', (tester) async {
      final model = FakeComments(loaded: false, loadingValue: true);
      await host(
        tester,
        comments: CommentsTab(model: model, callbacks: Replies().callbacks),
      );
      await openAt(tester, SheetStop.half, tab: PageTab.intro);
      expect(model.calls, isEmpty);
      await tester.tap(find.text('评论'));
      await tester.pump();
      expect(model.calls, ['ensureLoaded']);
    });

    sheetTest('the page\'s 评论 and the sheet\'s on one model load each page once', (tester) async {
      var page = 0;
      final api = fixtures.ScriptedApi()
        ..pages = (sort, offset) {
          page++;
          return CommentPage(
            comments: [for (var i = 0; i < 40; i++) fixtures.comment(page * 100 + i)],
            nextOffset: 'page${page + 1}',
            isEnd: false,
          );
        };
      final rig = fixtures.CommentsRig(api: api);
      addTearDown(rig.model.dispose);
      final pageScroll = ScrollController();
      addTearDown(pageScroll.dispose);
      final replies = Replies();
      await host(
        tester,
        under: PrimaryScrollController(
          controller: pageScroll,
          child: CommentsTab(model: rig.model, callbacks: replies.callbacks),
        ),
        comments: CommentsTab(model: rig.model, callbacks: replies.callbacks),
      );
      await settle(tester);
      // Whatever the page's own tab asked for by itself.
      final pages = rig.callsTo('comments').length;
      expect(pages, greaterThan(0));
      await openAt(tester, SheetStop.full);
      await settle(tester);
      expect(rig.callsTo('comments'), hasLength(pages));
      // The sheet's list nearing its end asks for the next page, once; the page's list, at its top, asks nothing.
      final sheetList = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('story-sheet')), matching: find.byType(Scrollable)).first,
      );
      sheetList.position.jumpTo(sheetList.position.maxScrollExtent);
      await settle(tester);
      expect(rig.callsTo('comments'), hasLength(pages + 1));
      expect(pageScroll.offset, 0);
    });
  });

  group('semantics', () {
    sheetTest('the button reads 展开 or 收起, the tabs are buttons, 关闭 closes, and the sheet offers all three', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await host(tester);
      await openAt(tester, SheetStop.half);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('story-sheet-button'))),
        isSemantics(isButton: true, label: '展开', hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('story-sheet-tab-comments'))),
        isSemantics(isButton: true, isSelected: true, label: '评论 98', hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('story-sheet-tab-intro'))),
        isSemantics(isButton: true, isSelected: false, label: '简介', hasTapAction: true),
      );

      tester.semantics.tap(find.semantics.byLabel('简介'));
      await tester.pump();
      expect(sheet.tab, PageTab.intro);
      tester.semantics.tap(find.semantics.byLabel('展开'));
      await settle(tester);
      expect(sheet.stop, SheetStop.full);
      expect(tester.getSemantics(find.byKey(const ValueKey('story-sheet-button'))), isSemantics(label: '收起'));

      void act(String label) {
        final node = tester.getSemantics(find.byKey(const ValueKey('story-sheet-card')));
        node.owner!.performAction(
          node.id,
          SemanticsAction.customAction,
          CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label)),
        );
      }

      expect(
        tester.getSemantics(find.byKey(const ValueKey('story-sheet-card'))),
        isSemantics(
          customActions: [
            const CustomSemanticsAction(label: '收起'),
            const CustomSemanticsAction(label: '关闭'),
          ],
        ),
      );
      act('收起');
      await settle(tester);
      expect(sheet.stop, SheetStop.half);
      act('展开');
      await settle(tester);
      expect(sheet.stop, SheetStop.full);
      act('关闭');
      await settle(tester);
      expect(sheet.stop, SheetStop.closed);

      await openAt(tester, SheetStop.half);
      tester.semantics.tap(find.semantics.byLabel('关闭'));
      await settle(tester);
      expect(sheet.stop, SheetStop.closed);
      semantics.dispose();
    });
  });
}
