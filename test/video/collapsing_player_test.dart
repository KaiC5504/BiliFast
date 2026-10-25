import 'package:bilifast/player_ui/portrait_controls.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/collapsing_player.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/page_tabs.dart';
import 'package:bilifast/video/player_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

const full = 440 / BiliMetrics.videoAspect;
const bar = CollapseTheme.barHeight;
const reserve = full - bar;

/// 17's 3:4 video in the 440 pt wide box.
const tall = 440 * CollapseTheme.uprightLimit;
const upright = (width: 1080, height: 1440);

void main() {
  group('the height (BiliNative CollapsingPlayer)', () {
    double height(double offset, {double from = 0, double full = full}) =>
        CollapsingPlayer.heightFor(full: full, offset: offset, from: from);

    test('it gives up what is scrolled after the pause point, down to the bar', () {
      expect(height(0), full);
      expect(height(100), full - 100);
      expect(height(reserve), bar);
      expect(height(1000), bar);
      expect(height(400, from: 300), full - 100);
      expect(height(1000, from: 300), bar);
    });

    test('above the pause point, and in an overscroll at the top, it keeps its full height', () {
      expect(height(200, from: 300), full);
      expect(height(-40), full);
    });

    test('a box no taller than the bar never shrinks', () {
      expect(height(100, full: bar), bar);
      expect(height(100, full: 0), 0);
    });

    test('progress runs from 0 at full height to 1 at the bar', () {
      expect(CollapsingPlayer.progressOf(full: full, height: full), 0);
      expect(CollapsingPlayer.progressOf(full: full, height: full - reserve / 2), closeTo(0.5, 1e-9));
      expect(CollapsingPlayer.progressOf(full: full, height: bar), 1);
      expect(CollapsingPlayer.progressOf(full: bar, height: bar), 0);
    });

    test('12\'s bar is 202 px at 3×', () {
      expect(bar * 3, closeTo(202, 1e-9));
    });
  });

  group('over the tabs', () {
    late PageTabsController tabs;
    late CollapsingPlayer collapse;
    late int heard;

    setUp(() {
      tabs = PageTabsController();
      collapse = CollapsingPlayer(tabs: tabs, vsync: const TestVSync())..width = 440;
      heard = 0;
      collapse.addListener(() => heard++);
    });

    tearDown(() {
      collapse.dispose();
      tabs.dispose();
    });

    Widget list(String name) => ListView(
      key: PageStorageKey(name),
      primary: true,
      children: [for (var i = 0; i < 100; i++) SizedBox(height: 60, child: Text('$name $i'))],
    );

    Future<void> host(WidgetTester tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PageTabs(controller: tabs, intro: list('简介'), comments: list('评论')),
        ),
      );
    }

    ScrollController scroll(PageTab tab) => tabs.scrollOf(tab);

    Future<void> showComments(WidgetTester tester) async {
      tabs.select(PageTab.comments, animate: false);
      await tester.pump();
    }

    testWidgets('playing, the tab scrolls under the full-height player and nothing is told', (tester) async {
      await host(tester);
      scroll(PageTab.intro).jumpTo(500);
      await tester.pump();
      expect(collapse.height, full);
      expect(collapse.progress, 0);
      expect(heard, 0);
    });

    testWidgets('paused, it follows what the shown tab scrolls after the pause, and a scroll back above the pause '
        'point moves the point up', (tester) async {
      await host(tester);
      scroll(PageTab.intro).jumpTo(300);
      collapse.paused = true;
      expect(collapse.height, full, reason: 'a pause halfway down doesn\'t snap it to the bar');
      expect(heard, 0);

      scroll(PageTab.intro).jumpTo(350);
      expect(collapse.height, full - 50);
      expect(heard, 1);
      scroll(PageTab.intro).jumpTo(2000);
      expect(collapse.height, bar);
      expect(collapse.progress, 1);

      scroll(PageTab.intro).jumpTo(100);
      expect(collapse.height, full);
      scroll(PageTab.intro).jumpTo(140);
      expect(collapse.height, full - 40, reason: 'shrinking from where it was scrolled back to');
    });

    testWidgets('switching tabs follows the shown tab from its own pause point, the height passing between the two '
        'with the swipe', (tester) async {
      await host(tester);
      await showComments(tester);
      scroll(PageTab.comments).jumpTo(500);
      tabs.select(PageTab.intro, animate: false);
      await tester.pump();
      collapse.paused = true;

      scroll(PageTab.intro).jumpTo(100);
      expect(collapse.height, full - 100);
      await showComments(tester);
      expect(collapse.height, full, reason: 'scrolled while playing, not since the pause');
      scroll(PageTab.comments).jumpTo(560);
      expect(collapse.height, full - 60);

      tabs.pager.jumpTo(220);
      await tester.pump();
      expect(tabs.position, 0.5);
      expect(collapse.height, closeTo(full - 80, 1e-9));
    });

    testWidgets('once it plays it grows back to full over 300 ms, never behind a scroll back to the top', (
      tester,
    ) async {
      await host(tester);
      collapse.paused = true;
      scroll(PageTab.intro).jumpTo(100);
      expect(collapse.height, full - 100);

      tabs.scrollToTop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      collapse.paused = false;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          collapse.height,
          greaterThanOrEqualTo(full - tabs.offsetOf(PageTab.intro) - 1e-9),
          reason: 'no gap opens between the tab row and the content coming back down',
        );
      }
      await tester.pump(CollapseTheme.resume);
      expect(tabs.offsetOf(PageTab.intro), 0);
      expect(collapse.height, full);

      collapse.paused = true;
      scroll(PageTab.intro).jumpTo(1000);
      expect(collapse.height, bar);
      collapse.paused = false;
      expect(collapse.height, bar, reason: 'it grows rather than jumps');
      await tester.pump();
      await tester.pump(CollapseTheme.resume ~/ 2);
      expect(collapse.height, inExclusiveRange(bar, full));
      await tester.pump(CollapseTheme.resume);
      expect(collapse.height, full);
    });

    testWidgets('with Reduce Motion it is full again at once', (tester) async {
      await host(tester);
      collapse
        ..still = true
        ..paused = true;
      scroll(PageTab.intro).jumpTo(1000);
      expect(collapse.height, bar);
      collapse.paused = false;
      expect(collapse.height, full);
    });

    testWidgets('the reserve is the full height less the bar, and follows the width', (tester) async {
      expect(collapse.reserve, reserve);
      collapse.width = 956;
      expect(collapse.reserve, 956 / BiliMetrics.videoAspect - bar);
      expect(collapse.height, 956 / BiliMetrics.videoAspect);
    });
  });

  group('the box\'s shape (17)', () {
    double box(({int width, int height})? video, {bool ended = false}) =>
        inlinePlayerHeight(440, video: video, ended: ended);

    test('16:9 for a landscape, square or unknown video; an upright one takes its own shape up to 3:4', () {
      expect(box(null), full, reason: 'unknown: 16:9 until it is known');
      expect(box((width: 1920, height: 1080)), full);
      expect(box((width: 1080, height: 1080)), full);
      expect(box((width: 0, height: 0)), full);
      expect(box(upright), closeTo(586.67, 0.005), reason: '17: bottom 648.67 under the 62 pt status bar');
      expect(box((width: 1080, height: 1200)), closeTo(440 * 1200 / 1080, 1e-9));
      expect(box((width: 1080, height: 1920)), closeTo(tall, 1e-9), reason: 'a 9:16 sits in the 3:4 box');
    });

    test('at the end the end screen takes the 16:9 box (18)', () {
      expect(box(upright, ended: true), full);
    });
  });

  group('an upright video\'s box', () {
    late PageTabsController tabs;
    late CollapsingPlayer collapse;
    late FakePlayerSession session;
    late int heard;

    setUp(() {
      tabs = PageTabsController();
      session = FakePlayerSession();
      collapse = CollapsingPlayer(tabs: tabs, vsync: const TestVSync());
      heard = 0;
      collapse.addListener(() => heard++);
    });

    tearDown(() {
      collapse.dispose();
      tabs.dispose();
      session.dispose();
    });

    /// A tab as the page's are: the reserve's gap, then the content.
    Widget list(String name) => Builder(
      builder: (context) => CustomScrollView(
        key: PageStorageKey(name),
        primary: true,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: PlayerReserve.of(context))),
          SliverList.list(children: [for (var i = 0; i < 100; i++) SizedBox(height: 60, child: Text('$name $i'))]),
        ],
      ),
    );

    /// The tabs laid out from the screen's top, as the page lays them out from the bar's bottom: a tab's content
    /// rides the box's bottom edge when its top is at the box's height less the bar.
    Future<void> host(WidgetTester tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CollapseReserve(
            collapse: collapse,
            child: PageTabs(controller: tabs, intro: list('简介'), comments: list('评论')),
          ),
        ),
      );
    }

    ScrollController scroll(PageTab tab) => tabs.scrollOf(tab);

    double top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

    Future<void> showComments(WidgetTester tester) async {
      tabs.select(PageTab.comments, animate: false);
      await tester.pump();
    }

    Future<void> showIntro(WidgetTester tester) async {
      tabs.select(PageTab.intro, animate: false);
      await tester.pump();
    }

    void shaped({bool ended = false}) {
      session
        ..videoShape = upright
        ..ended = ended
        ..changed();
    }

    testWidgets('a shape known by the first layout is taken at once', (tester) async {
      session.videoShape = upright;
      collapse
        ..session = session
        ..width = 440;
      expect(collapse.full, closeTo(tall, 1e-9));
      expect(collapse.height, closeTo(tall, 1e-9));
      expect(collapse.progress, 0);
      expect(collapse.reserve, closeTo(tall - bar, 1e-9));
      expect(collapse.reserveListenable.value, closeTo(tall - bar, 1e-9));
      expect(heard, 0, reason: 'the page sets the width as it lays out');
    });

    testWidgets('a shape arriving after the first layout grows the box over 150 ms, easing in and out', (tester) async {
      collapse
        ..session = session
        ..width = 440;
      expect(collapse.full, full);
      shaped();
      expect(collapse.full, full, reason: 'it starts from where it is');
      expect(collapse.shape.value, closeTo(tall, 1e-9), reason: 'the shape it is taking, at once');
      await tester.pump();
      await tester.pump(CollapseTheme.reshape ~/ 4);
      expect(collapse.full, closeTo(full + (tall - full) * CollapseTheme.reshapeCurve.transform(0.25), 0.01));
      expect(collapse.full, lessThan(full + (tall - full) * 0.25), reason: 'easing in');
      await tester.pump(CollapseTheme.reshape ~/ 4);
      expect(collapse.full, closeTo((full + tall) / 2, 0.01));
      expect(collapse.height, collapse.full);
      expect(collapse.reserveListenable.value, closeTo(collapse.full - bar, 1e-9));
      await tester.pump(CollapseTheme.reshape);
      expect(collapse.full, closeTo(tall, 1e-9));
      expect(collapse.height, closeTo(tall, 1e-9));
      expect(collapse.progress, 0);
    });

    testWidgets('at the end the box goes to 16:9 over 150 ms with the content riding its bottom, never counting as '
        'shrunk, and 重播 grows it back (18)', (tester) async {
      session.videoShape = upright;
      collapse
        ..session = session
        ..width = 440;
      await host(tester);
      expect(top(tester, '简介 0') + bar, closeTo(tall, 0.01));
      var shrunk = false;
      collapse.addListener(() => shrunk |= collapse.progress > 0);

      shaped(ended: true);
      await tester.pump();
      await tester.pump(CollapseTheme.reshape ~/ 2);
      expect(collapse.height, closeTo((tall + full) / 2, 0.01));
      expect(top(tester, '简介 0') + bar, closeTo(collapse.height, 0.01), reason: 'the body rides with the box');
      await tester.pump(CollapseTheme.reshape);
      expect(collapse.height, full);
      expect(collapse.reserve, reserve);
      expect(top(tester, '简介 0') + bar, closeTo(full, 0.01));

      shaped();
      await tester.pump();
      await tester.pump(CollapseTheme.reshape ~/ 2);
      expect(collapse.height, closeTo((tall + full) / 2, 0.01));
      await tester.pump(CollapseTheme.reshape);
      expect(collapse.height, closeTo(tall, 1e-9));
      expect(top(tester, '简介 0') + bar, closeTo(tall, 0.01));
      expect(shrunk, isFalse, reason: 'the controls stay as they are and no 继续播放 shows');
    });

    testWidgets('a tab scrolled under the box keeps its content where it is on screen through a change of shape; one '
        'scrolled less than the change rides the box', (tester) async {
      session.videoShape = upright;
      collapse
        ..session = session
        ..width = 440;
      await host(tester);
      await showComments(tester);
      scroll(PageTab.comments).jumpTo(100);
      await showIntro(tester);
      scroll(PageTab.intro).jumpTo(600);
      await tester.pump();
      expect(collapse.height, full);
      final before = top(tester, '简介 12');

      shaped(ended: true);
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(CollapseTheme.reshape ~/ 8);
        expect(top(tester, '简介 12'), closeTo(before, 0.01), reason: 'no jump at frame $i');
        expect(collapse.height, full);
      }
      expect(tabs.offsetOf(PageTab.intro), closeTo(600 - (tall - full), 0.01));
      expect(tabs.offsetOf(PageTab.comments), 0, reason: 'its 100 pt was less than the 339 the box gave up');
      await showComments(tester);
      expect(top(tester, '评论 0') + bar, closeTo(full, 0.01));
      await showIntro(tester);

      shaped();
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(CollapseTheme.reshape ~/ 8);
        expect(top(tester, '简介 12'), closeTo(before, 0.01), reason: 'no jump growing back, frame $i');
        expect(collapse.height, full, reason: 'scrolled, it stays 16:9');
      }
      expect(tabs.offsetOf(PageTab.intro), closeTo(600, 0.01));
    });

    testWidgets('playing, a scroll takes its height above 16:9 one for one, then the tab scrolls under it; scrolled '
        'back it grows again, never counting as shrunk (21)', (tester) async {
      session.videoShape = upright;
      collapse
        ..session = session
        ..width = 440;
      await host(tester);
      scroll(PageTab.intro).jumpTo(100);
      await tester.pump();
      expect(collapse.height, closeTo(tall - 100, 1e-9));
      expect(top(tester, '简介 0') + bar, closeTo(collapse.height, 0.01), reason: 'the list rides it');
      scroll(PageTab.intro).jumpTo(tall - full);
      expect(collapse.height, closeTo(full, 1e-9));
      scroll(PageTab.intro).jumpTo(800);
      expect(collapse.height, full);
      expect(collapse.progress, 0);
      scroll(PageTab.intro).jumpTo(50);
      expect(collapse.height, closeTo(tall - 50, 1e-9));
      scroll(PageTab.intro).jumpTo(0);
      expect(collapse.height, closeTo(tall, 1e-9));
      expect(collapse.progress, 0);
    });

    testWidgets('paused at the top, it shrinks from its full height to the bar', (tester) async {
      session.videoShape = upright;
      collapse
        ..session = session
        ..width = 440;
      await host(tester);
      collapse.paused = true;
      scroll(PageTab.intro).jumpTo(200);
      expect(collapse.height, closeTo(tall - 200, 1e-9));
      expect(collapse.progress, closeTo(200 / (tall - bar), 1e-9));
      scroll(PageTab.intro).jumpTo(2000);
      expect(collapse.height, closeTo(bar, 1e-9));
      expect(collapse.progress, 1);
    });

    testWidgets('paused down the page at 16:9, it shrinks from 16:9; scrolled back up it grows to the height it has '
        'playing there', (tester) async {
      session.videoShape = upright;
      collapse
        ..session = session
        ..width = 440;
      await host(tester);
      scroll(PageTab.intro).jumpTo(500);
      collapse.paused = true;
      expect(collapse.height, full, reason: 'a pause doesn\'t move it');
      expect(collapse.progress, 0);
      scroll(PageTab.intro).jumpTo(600);
      expect(collapse.height, closeTo(full - 100, 1e-9));
      expect(collapse.progress, closeTo(100 / reserve, 1e-9));
      scroll(PageTab.intro).jumpTo(2000);
      expect(collapse.height, closeTo(bar, 1e-9));
      expect(collapse.progress, 1);
      scroll(PageTab.intro).jumpTo(300);
      expect(collapse.height, closeTo(tall - 300, 1e-9));
      expect(collapse.progress, 0);
    });

    testWidgets('once it plays it grows back to its playing height: 16:9 down the page', (tester) async {
      session.videoShape = upright;
      collapse
        ..session = session
        ..width = 440;
      await host(tester);
      collapse.paused = true;
      scroll(PageTab.intro).jumpTo(1000);
      expect(collapse.height, closeTo(bar, 1e-9));
      collapse.paused = false;
      expect(collapse.height, closeTo(bar, 1e-9), reason: 'it grows rather than jumps');
      expect(collapse.progress, 1);
      await tester.pump();
      await tester.pump(CollapseTheme.resume ~/ 2);
      expect(collapse.height, inExclusiveRange(bar, full));
      expect(collapse.progress, inExclusiveRange(0, 1));
      await tester.pump(CollapseTheme.resume);
      expect(collapse.height, closeTo(full, 1e-9), reason: 'not the 3:4 height: the tab is scrolled');
      expect(collapse.progress, 0);
    });

    testWidgets('paused a little down the tall box, playing again fades 继续播放 out where it is', (tester) async {
      session.videoShape = upright;
      collapse
        ..session = session
        ..width = 440;
      await host(tester);
      collapse.paused = true;
      scroll(PageTab.intro).jumpTo(100);
      final progress = collapse.progress;
      expect(progress, closeTo(100 / (tall - bar), 1e-9));
      collapse.paused = false;
      expect(collapse.progress, closeTo(progress, 1e-9), reason: 'no snap');
      heard = 0;
      await tester.pump();
      await tester.pump(CollapseTheme.resume ~/ 2);
      expect(collapse.height, closeTo(tall - 100, 1e-9), reason: 'its playing height there');
      expect(collapse.progress, inExclusiveRange(0, progress));
      expect(heard, greaterThan(0));
      await tester.pump(CollapseTheme.resume);
      expect(collapse.progress, 0);
    });

    testWidgets('with Reduce Motion it changes shape at once', (tester) async {
      collapse
        ..still = true
        ..session = session
        ..width = 440;
      shaped();
      expect(collapse.height, closeTo(tall, 1e-9));
      expect(heard, 1);
      shaped(ended: true);
      expect(collapse.height, full);
    });

    testWidgets('disposed, it follows the session no more', (tester) async {
      collapse
        ..session = session
        ..width = 440
        ..dispose();
      shaped();
      collapse = CollapsingPlayer(tabs: tabs, vsync: const TestVSync());
    });
  });

  group('the bar (11, 12)', () {
    late List<String> calls;

    setUp(() => calls = []);

    Future<void> show(WidgetTester tester, double progress, {bool still = false}) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final height = full - progress * reserve;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(440, 956), disableAnimations: still),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 440,
                height: height,
                child: CollapsedPlayerBar(
                  progress: progress,
                  onResume: () => calls.add('resume'),
                  onBack: () => calls.add('back'),
                  onMore: () => calls.add('more'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(CollapseTheme.controlsFade);
    }

    double opacityOf(WidgetTester tester, Finder finder) =>
        tester.widget<AnimatedOpacity>(find.ancestor(of: finder, matching: find.byType(AnimatedOpacity)).first).opacity;

    Color shade(WidgetTester tester) => tester
        .widget<ColoredBox>(
          find.descendant(of: find.byKey(const ValueKey('collapse-resume')), matching: find.byType(ColoredBox)),
        )
        .color;

    double labelOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find.descendant(of: find.byKey(const ValueKey('collapse-label')), matching: find.byType(Opacity)),
        )
        .opacity;

    testWidgets('mid-shrink (11): the video darkens a share of the way and ▶ 继续播放 fades in at the bar\'s place; no '
        '‹ or ⋮ yet', (tester) async {
      await show(tester, 0.45);
      expect(shade(tester).a, closeTo(CollapseTheme.shade.a * 0.45, 1e-3));
      expect(labelOpacity(tester), closeTo(0.72, 1e-9));
      final label = tester.getRect(find.text('继续播放'));
      expect(
        label.center.dy,
        closeTo(bar / 2 - CollapseTheme.rowLift, 0.5),
        reason: 'at the top, where the bar will be',
      );
      expect(opacityOf(tester, find.byKey(const ValueKey('collapse-back'))), 0);
      expect(opacityOf(tester, find.byKey(const ValueKey('collapse-more'))), 0);
      await show(tester, 0.8);
      expect(labelOpacity(tester), 1, reason: 'fully in before the end of the way');
    });

    testWidgets('the bar (12): ‹ at 17 pt, ▶ 继续播放 16 pt in the middle, ⋮ at the right, all 2.5 px above the middle', (
      tester,
    ) async {
      await show(tester, 1);
      expect(shade(tester), CollapseTheme.shade);
      expect(opacityOf(tester, find.byKey(const ValueKey('collapse-back'))), 1);
      expect(opacityOf(tester, find.byKey(const ValueKey('collapse-more'))), 1);
      const middle = bar / 2 - CollapseTheme.rowLift;
      final back = tester.getRect(find.byType(BackGlyph));
      expect(back.left, closeTo(CollapseTheme.backLeft, 0.01));
      expect(back.width, closeTo(CollapseTheme.backGlyphWidth, 0.01));
      expect(back.height, closeTo(CollapseTheme.backGlyphHeight, 0.01));
      expect(back.center.dy, closeTo(middle, 0.01));
      final more = tester.getRect(find.byType(MoreDots));
      expect(more.right, closeTo(440 - CollapseTheme.moreRight, 0.01));
      expect(more.center.dy, closeTo(middle, 0.01));
      final label = find.text('继续播放');
      expect(tester.widget<Text>(label).style!.fontSize, CollapseTheme.labelText);
      final play = tester.getRect(
        find.descendant(of: find.byKey(const ValueKey('collapse-label')), matching: find.byType(CustomPaint)).first,
      );
      expect(play.width, closeTo(CollapseTheme.playGlyphWidth, 0.01));
      expect(play.height, closeTo(CollapseTheme.playGlyphHeight, 0.01));
      expect(tester.getRect(label).left - play.right, closeTo(CollapseTheme.labelGap, 0.01));
      expect(
        (play.left + tester.getRect(label).right) / 2,
        closeTo(220 + CollapseTheme.labelShift, 0.01),
        reason: '12 sets the pair right of the middle',
      );
      expect(play.center.dy, closeTo(middle, 0.01));
    });

    testWidgets('any tap resumes, the corners included until they show; then ‹ goes back and ⋮ opens ⋮', (
      tester,
    ) async {
      await show(tester, 0.5);
      await tester.tapAt(const Offset(220, 100));
      await tester.tapAt(Offset(CollapseTheme.backLeft + 4, bar / 2));
      await tester.tapAt(Offset(440 - CollapseTheme.moreRight, bar / 2));
      expect(calls, ['resume', 'resume', 'resume']);

      calls.clear();
      await show(tester, 1);
      await tester.tap(find.byKey(const ValueKey('collapse-back')));
      await tester.tap(find.byKey(const ValueKey('collapse-more')));
      await tester.tapAt(const Offset(220, 20));
      expect(calls, ['back', 'more', 'resume']);
    });

    testWidgets('every part answers an accessibility press; the corners only once they show', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester, 0.5);
      expect(find.semantics.byLabel('返回'), findsNothing);
      expect(find.semantics.byLabel('更多'), findsNothing);
      tester.semantics.tap(find.semantics.byLabel('继续播放'));
      await show(tester, 1);
      tester.semantics.tap(find.semantics.byLabel('返回'));
      tester.semantics.tap(find.semantics.byLabel('更多'));
      tester.semantics.tap(find.semantics.byLabel('继续播放'));
      expect(calls, ['resume', 'back', 'more', 'resume']);
      handle.dispose();
    });

    testWidgets('with Reduce Motion ‹ and ⋮ simply appear', (tester) async {
      await show(tester, 1, still: true);
      final fade = tester.widget<AnimatedOpacity>(
        find.ancestor(of: find.byKey(const ValueKey('collapse-back')), matching: find.byType(AnimatedOpacity)).first,
      );
      expect(fade.duration, Duration.zero);
    });
  });
}
