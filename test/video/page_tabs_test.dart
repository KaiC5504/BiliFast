import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/shared/custom_icons.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/page_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PageTabsController tabs;
  late List<String> calls;

  setUp(() {
    tabs = PageTabsController();
    calls = [];
  });

  tearDown(() => tabs.dispose());

  Widget row({int? replyCount = 213, bool danmakuOn = true, bool toggle = true}) => PageTabRow(
    controller: tabs,
    replyCount: replyCount,
    danmakuOn: danmakuOn,
    onToggleDanmaku: toggle ? () => calls.add('toggle') : null,
    onSendDanmaku: () => calls.add('send'),
  );

  Widget scrolling(String name) => ListView(
    key: PageStorageKey(name),
    children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('$name $i'))],
  );

  Future<void> host(WidgetTester tester, Widget child, {bool still = false}) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(440, 956), disableAnimations: still),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  Widget page({Widget? intro, Widget? comments, bool danmakuOn = true}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      row(danmakuOn: danmakuOn),
      Expanded(
        child: PageTabs(
          controller: tabs,
          intro: intro ?? scrolling('简介'),
          comments: comments ?? const Center(child: Text('评论列表')),
        ),
      ),
    ],
  );

  Rect underline(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('tab-underline')));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group('the row (03, 10, 18)', () {
    testWidgets('40 pt tall with a hairline; 简介 from 33 pt, the underline under it flush with the bottom', (
      tester,
    ) async {
      await host(tester, page());
      expect(tester.getSize(find.byType(PageTabRow)), const Size(440, PageTheme.tabRowHeight));
      final intro = tester.getRect(find.text('简介'));
      expect(intro.left, closeTo(PageTheme.tabFirstLabel, 0.01));
      expect(intro.center.dy, closeTo(PageTheme.tabRowHeight / 2, 1));
      final bar = underline(tester);
      expect(bar.left, closeTo(intro.left, 0.01));
      expect(bar.width, closeTo(intro.width, 0.01));
      expect(bar.bottom, PageTheme.tabRowHeight);
      expect(bar.height, PageTheme.underlineHeight);
      final comments = tester.getRect(find.text('评论'));
      expect(comments.left, closeTo(intro.right + PageTheme.tabSpacing, 0.01));
    });

    testWidgets('评论 carries the reply count, shortened, on the label\'s baseline; none before the detail', (
      tester,
    ) async {
      await host(tester, row(replyCount: null));
      expect(find.bySemanticsLabel('评论'), findsOneWidget);
      await host(tester, row(replyCount: 213));
      expect(find.bySemanticsLabel('评论 213'), findsOneWidget);
      expect(find.text('213'), findsOneWidget);
      await host(tester, row(replyCount: 12345));
      expect(find.bySemanticsLabel('评论 1.2万'), findsOneWidget);
      final label = tester.getRect(find.text('评论'));
      final count = tester.getRect(find.text('1.2万'));
      expect(count.left, closeTo(label.right + PageTheme.tabCountGap, 0.01));
      expect(count.height, lessThan(label.height));
    });

    testWidgets('the selected tab is pink, the other 61666D, and the underline spans 评论 with its count', (
      tester,
    ) async {
      await host(tester, page());
      Color colour(String text) => tester.widget<Text>(find.text(text)).style!.color!;
      expect(colour('简介'), BiliColors.pink);
      expect(colour('评论'), PageTheme.tabText);
      await tester.tap(find.text('评论'));
      await settle(tester);
      expect(tabs.selected, PageTab.comments);
      expect(colour('简介'), PageTheme.tabText);
      expect(colour('评论'), BiliColors.pink);
      expect(colour('213'), BiliColors.pink);
      final bar = underline(tester);
      expect(bar.left, closeTo(tester.getRect(find.text('评论')).left, 0.01));
      expect(bar.right, closeTo(tester.getRect(find.text('213')).right, 0.01));
      expect(find.text('评论列表'), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const ValueKey('tab-comments'))), isSemantics(isSelected: true));
    });

    testWidgets('danmaku on: 点我发弹幕 joined to the toggle on white, 12 pt from the edge (18)', (tester) async {
      await host(tester, row());
      final capsule = tester.getRect(find.byKey(const ValueKey('danmaku-capsule')));
      expect(
        capsule.size,
        const Size(PageTheme.danmakuFieldWidth + PageTheme.danmakuToggleOn, PageTheme.capsuleHeight),
      );
      expect(capsule.right, 440 - BiliMetrics.gutter);
      expect(capsule.center.dy, PageTheme.tabRowHeight / 2);
      expect(tester.getRect(find.byKey(const ValueKey('danmaku-toggle'))).width, PageTheme.danmakuToggleOn);
      expect(find.byIcon(CustomIcons.danmakuOn), findsNWidgets(2), reason: 'grey glyph, pink tick');
      expect(find.bySemanticsLabel('关闭弹幕'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('danmaku-send')));
      await tester.tap(find.byKey(const ValueKey('danmaku-toggle')));
      expect(calls, ['send', 'toggle']);
    });

    testWidgets('danmaku off: the toggle alone in its small capsule, no field to press (03)', (tester) async {
      await host(tester, row(danmakuOn: false));
      final capsule = tester.getRect(find.byKey(const ValueKey('danmaku-capsule')));
      expect(capsule.size, const Size(PageTheme.danmakuToggleOff, PageTheme.capsuleHeight));
      expect(capsule.right, 440 - BiliMetrics.gutter);
      expect(find.bySemanticsLabel('开启弹幕'), findsOneWidget);
      expect(find.bySemanticsLabel('点我发弹幕'), findsNothing);
      expect(find.byIcon(CustomIcons.danmakuOff), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('danmaku-toggle')));
      expect(calls, ['toggle']);
    });

    testWidgets('the capsule grows into the field when danmaku comes on', (tester) async {
      var on = false;
      late StateSetter set;
      await host(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Align(
              alignment: Alignment.topCenter,
              child: row(danmakuOn: on),
            );
          },
        ),
      );
      double width() => tester.getSize(find.byKey(const ValueKey('danmaku-capsule'))).width;
      set(() => on = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        width(),
        inExclusiveRange(PageTheme.danmakuToggleOff, PageTheme.danmakuFieldWidth + PageTheme.danmakuToggleOn),
      );
      await settle(tester);
      expect(width(), PageTheme.danmakuFieldWidth + PageTheme.danmakuToggleOn);
    });

    testWidgets('before the session the toggle shows the saved state and presses nothing', (tester) async {
      await host(tester, row(toggle: false));
      await tester.tap(find.byKey(const ValueKey('danmaku-toggle')));
      expect(calls, isEmpty);
    });

    testWidgets('every control answers an accessibility press', (tester) async {
      final semantics = tester.ensureSemantics();
      await host(tester, page());
      for (final label in ['评论 213', '点我发弹幕', '关闭弹幕']) {
        tester.semantics.tap(find.semantics.byLabel(label));
      }
      await settle(tester);
      expect(tabs.selected, PageTab.comments);
      expect(calls, ['send', 'toggle']);
      tester.semantics.tap(find.semantics.byLabel('简介'));
      await settle(tester);
      expect(tabs.selected, PageTab.intro);
      semantics.dispose();
    });
  });

  group('the pager', () {
    testWidgets('the underline follows a sideways swipe, and the tab switches when it lands', (tester) async {
      await host(tester, page());
      final start = underline(tester);
      final gesture = await tester.startGesture(const Offset(300, 400));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(-25, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final midway = underline(tester);
      expect(midway.left, greaterThan(start.left));
      expect(midway.right, greaterThan(start.right));
      expect(tester.getRect(find.text('评论')).left, greaterThan(midway.left), reason: 'not there yet');
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(-25, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tabs.selected, PageTab.comments);
      expect(underline(tester).left, closeTo(tester.getRect(find.text('评论')).left, 0.01));

      await tester.timedDrag(find.byType(PageTabs), const Offset(300, 0), const Duration(milliseconds: 200));
      await settle(tester);
      expect(tabs.selected, PageTab.intro);
      expect(underline(tester).left, closeTo(start.left, 0.01));
    });

    testWidgets('a kept tab out of sight stops its tickers; both run during a swipe', (tester) async {
      await host(tester, page(comments: scrolling('评论')));
      bool ticking(String text) => TickerMode.valuesOf(tester.element(find.text(text, skipOffstage: false))).enabled;
      tabs.select(PageTab.comments);
      await settle(tester);
      expect(ticking('评论 0'), isTrue);
      expect(ticking('简介 0'), isFalse);
      final gesture = await tester.startGesture(const Offset(220, 600));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(ticking('简介 0'), isTrue);
      expect(ticking('评论 0'), isTrue);
      // Let go early: back on 评论, and 简介 stops again.
      await gesture.up();
      await settle(tester);
      expect(ticking('简介 0'), isFalse);
      expect(ticking('评论 0'), isTrue);
    });

    testWidgets('each tab keeps its scroll position through a switch', (tester) async {
      await host(tester, page(comments: scrolling('评论')));
      await tester.drag(find.text('简介 3'), const Offset(0, -600));
      await settle(tester);
      final introTop = tester.getTopLeft(find.text('简介 12')).dy;
      tabs.select(PageTab.comments);
      await settle(tester);
      await tester.drag(find.text('评论 2'), const Offset(0, -300));
      await settle(tester);
      final commentsTop = tester.getTopLeft(find.text('评论 8')).dy;
      tabs.select(PageTab.intro);
      await settle(tester);
      expect(tester.getTopLeft(find.text('简介 12')).dy, introTop);
      tabs.select(PageTab.comments);
      await settle(tester);
      expect(tester.getTopLeft(find.text('评论 8')).dy, commentsTop);
    });

    testWidgets('each tab\'s list scrolls with its own controller, which the page reads; only the shown one goes back to '
        'its top', (tester) async {
      await host(tester, page(comments: scrolling('评论')));
      var heard = 0;
      void hear() => heard++;
      tabs.motion.addListener(hear);
      addTearDown(() => tabs.motion.removeListener(hear));
      expect(tabs.offsetOf(PageTab.intro), 0);
      expect(tabs.offsetOf(PageTab.comments), 0, reason: 'not laid out yet');

      await tester.drag(find.text('简介 3'), const Offset(0, -300));
      await settle(tester);
      final intro = tabs.offsetOf(PageTab.intro);
      expect(intro, greaterThan(200));
      expect(tabs.scrollOf(PageTab.intro).offset, intro);
      expect(heard, greaterThan(0));

      tabs.select(PageTab.comments);
      await settle(tester);
      await tester.drag(find.text('评论 2'), const Offset(0, -200));
      await settle(tester);
      expect(tabs.offsetOf(PageTab.comments), greaterThan(100));
      tabs.scrollToTop();
      await tester.pump();
      await tester.pump(CollapseTheme.resume ~/ 2);
      expect(tabs.offsetOf(PageTab.comments), greaterThan(0), reason: 'on its way');
      await tester.pump(CollapseTheme.resume);
      expect(tabs.offsetOf(PageTab.comments), 0);
      expect(tabs.offsetOf(PageTab.intro), intro, reason: 'the other tab stays where it was');

      tabs.select(PageTab.intro, animate: false);
      await tester.pump();
      tabs.scrollToTop(animate: false);
      await tester.pump();
      expect(tabs.offsetOf(PageTab.intro), 0);
    });

    testWidgets('with reduced motion a tap jumps straight to the tab', (tester) async {
      await host(tester, page(), still: true);
      await tester.tap(find.text('评论'));
      await tester.pump();
      expect(tabs.position, 1);
      expect(underline(tester).left, closeTo(tester.getRect(find.text('评论')).left, 0.01));
    });

    testWidgets('a select before the pager is laid out, as from full screen, still lands on the tab', (tester) async {
      tabs.select(PageTab.comments, animate: false);
      await host(tester, page());
      await tester.pump();
      expect(tabs.selected, PageTab.comments);
      expect(tabs.position, 1);
      expect(find.text('评论列表'), findsOneWidget);
    });

    testWidgets('the route\'s edge swipe goes back over the pager; a swipe from the middle only switches tabs', (
      tester,
    ) async {
      await host(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                SwipeBackPageRoute<void>(
                  builder: (_) => Scaffold(body: SafeArea(child: page())),
                ),
              ),
              child: const Text('首页'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      await tester.timedDragFrom(const Offset(300, 500), const Offset(-300, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tabs.selected, PageTab.comments);
      await tester.timedDragFrom(const Offset(150, 500), const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tabs.selected, PageTab.intro);
      expect(find.byType(PageTabs), findsOneWidget, reason: 'still on the page');
      await tester.timedDragFrom(const Offset(5, 500), const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byType(PageTabs), findsNothing);
      expect(find.text('首页'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
