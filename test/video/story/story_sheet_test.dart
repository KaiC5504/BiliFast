import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/page_details.dart' show PageTab;
import 'package:bilifast/video/story/story_sheet.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter_test/flutter_test.dart';

const screen = 956.0;

double topOf(StorySheetController sheet) => StorySheetController.topFor(sheet.position.value, screen);

/// A test that lets whatever move it left running finish, as the test framework wants no animation running at its end.
void sheetTest(String description, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late StorySheetController sheet;

  // TestVSync's tickers run on the test's frames but aren't the tester's, so a move left running at the end is torn
  // down with the controller.
  Future<void> make(WidgetTester tester) async {
    sheet = StorySheetController(vsync: const TestVSync())..screenHeight = screen;
    addTearDown(sheet.dispose);
  }

  /// Opens to [stop] and lets the move finish.
  Future<void> rest(WidgetTester tester, SheetStop stop) async {
    sheet.open(PageTab.comments);
    if (stop == SheetStop.full) sheet.toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sheet.position.value, stop.index.toDouble());
  }

  /// A drag of [travel] points (down positive) in steps, let go at [velocity].
  void drag(double travel, {double velocity = 0, bool raises = true}) {
    sheet.dragStart(raises: raises);
    const steps = 10;
    for (var i = 0; i < steps; i++) {
      sheet.dragUpdate(travel / steps, screen);
    }
    sheet.dragEnd(velocity, screen);
  }

  /// The positions of the next [ms] milliseconds, a frame every 1/60 s.
  Future<List<double>> frames(WidgetTester tester, int ms) async {
    final seen = <double>[];
    await tester.pump();
    for (var t = 0; t < ms; t += 17) {
      await tester.pump(const Duration(microseconds: 16667));
      seen.add(sheet.position.value);
    }
    return seen;
  }

  group('the stops', () {
    test('top edges: half at 947 px, full at 162 px, closed off the screen, and back', () {
      expect(StorySheetController.topFor(0, screen), screen);
      expect(StorySheetController.topFor(1, screen), StorySheetTheme.halfTop);
      expect(StorySheetController.topFor(2, screen), StorySheetTheme.fullTop);
      // A spring's overshoot keeps full's pace above it.
      expect(
        StorySheetController.topFor(2.1, screen),
        moreOrLessEquals(StorySheetTheme.fullTop - 0.1 * (StorySheetTheme.halfTop - StorySheetTheme.fullTop)),
      );
      for (final position in [0.0, 0.25, 0.5, 1.0, 1.4, 2.0, 2.05]) {
        final top = StorySheetController.topFor(position, screen);
        expect(StorySheetController.positionFor(top, screen), moreOrLessEquals(position));
      }
      expect(StorySheetController.positionFor(screen + 50, screen), 0);
    });

    sheetTest('open goes to half on the tab asked for, in 100 ms ease-in-out (268 at 2.6 s)', (tester) async {
      await make(tester);
      sheet.open(PageTab.intro);
      expect(sheet.tab, PageTab.intro);
      expect(sheet.stop, SheetStop.half);
      expect(sheet.isOpen, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      expect(sheet.position.value, moreOrLessEquals(Curves.easeInOut.transform(0.25), epsilon: 0.01));
      await tester.pump(const Duration(milliseconds: 25));
      expect(sheet.position.value, moreOrLessEquals(0.5, epsilon: 0.01));
      await tester.pump(const Duration(milliseconds: 50));
      expect(sheet.position.value, 1);
      expect(topOf(sheet), StorySheetTheme.halfTop);
    });

    sheetTest('open on another tab while open switches the tab and tells the listeners', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.half);
      var told = 0;
      sheet.addListener(() => told++);
      sheet.open(PageTab.intro);
      expect(sheet.tab, PageTab.intro);
      expect(told, 1);
    });

    sheetTest('close takes 100 ms, evenly in points from full across half', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.full);
      sheet.close();
      expect(sheet.stop, SheetStop.closed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Half way in time and in points: 505 pt down, 30% of the way from half to closed.
      expect(topOf(sheet), moreOrLessEquals((StorySheetTheme.fullTop + screen) / 2, epsilon: 0.5));
      await tester.pump(const Duration(milliseconds: 50));
      expect(sheet.position.value, 0);
      expect(sheet.isOpen, isFalse);
    });

    sheetTest('the button toggles half and full in 100 ms each; expand and collapse go one way', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.half);
      sheet.toggle();
      expect(sheet.stop, SheetStop.full);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(sheet.position.value, 2);
      sheet.toggle();
      expect(sheet.stop, SheetStop.half);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(sheet.position.value, 1);
      sheet.expand();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(sheet.stop, SheetStop.full);
      sheet.collapse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(sheet.stop, SheetStop.half);
      expect(sheet.position.value, 1);
    });

    sheetTest('with Reduce Motion every move jumps', (tester) async {
      await make(tester);
      sheet.still = true;
      sheet.open(PageTab.comments);
      expect(sheet.position.value, 1);
      sheet.toggle();
      expect(sheet.position.value, 2);
      drag(100);
      expect(sheet.position.value, 2);
      sheet.close();
      expect(sheet.position.value, 0);
    });
  });

  group('drags', () {
    sheetTest('the sheet follows the finger point for point, never above full', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.half);
      sheet.dragStart();
      expect(sheet.dragging, isTrue);
      sheet.dragUpdate(-100, screen);
      expect(topOf(sheet), moreOrLessEquals(StorySheetTheme.halfTop - 100));
      sheet.dragUpdate(150, screen);
      expect(topOf(sheet), moreOrLessEquals(StorySheetTheme.halfTop + 50));
      sheet.dragUpdate(-1000, screen);
      expect(topOf(sheet), moreOrLessEquals(StorySheetTheme.fullTop));
      expect(sheet.position.value, 2);
    });

    sheetTest('a drag that may not raise the sheet stops where it found it', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.half);
      sheet.dragStart(raises: false);
      sheet.dragUpdate(80, screen);
      sheet.dragUpdate(-200, screen);
      expect(sheet.position.value, 1);
      // Flung up, it lands where it started, not on full.
      sheet.dragUpdate(40, screen);
      sheet.dragEnd(-1500, screen);
      expect(sheet.stop, SheetStop.half);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(sheet.position.value, 1);
    });

    sheetTest('an update outside a drag moves nothing: close took the sheet from under the finger', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.half);
      sheet.dragStart();
      sheet.dragUpdate(20, screen);
      sheet.close();
      expect(sheet.dragging, isFalse);
      sheet.dragUpdate(-300, screen);
      sheet.dragEnd(-1500, screen);
      expect(sheet.stop, SheetStop.closed);
    });

    sheetTest('the full sheet pulled down short of half and let go slowly jumps back, overshooting (268, 6.6 s)', (
      tester,
    ) async {
      await make(tester);
      await rest(tester, SheetStop.full);
      // 76% of the way to half, as 268 lets go at 9.2 s.
      drag(0.76 * (StorySheetTheme.halfTop - StorySheetTheme.fullTop));
      expect(sheet.stop, SheetStop.full);
      final seen = await frames(tester, 200);
      // It passes full by a few points, as 268's does (26 px), and settles there within about 100 ms.
      final highest = seen.reduce((a, b) => a > b ? a : b);
      final overshoot = (StorySheetController.topFor(highest, screen) - StorySheetTheme.fullTop).abs();
      expect(highest, greaterThan(2));
      expect(overshoot, inInclusiveRange(2, 12));
      final landed = seen.indexWhere((position) => (position - 2).abs() < 0.005);
      expect(landed * 1000 / 60, lessThan(120));
      expect(seen.last, 2);
    });

    sheetTest('the jump back covers nearly all the way in two frames, as 268 does', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.full);
      final pulled = 0.55 * (StorySheetTheme.halfTop - StorySheetTheme.fullTop);
      drag(pulled);
      final seen = await frames(tester, 70);
      final left = [
        for (final position in seen) StorySheetController.topFor(position, screen) - StorySheetTheme.fullTop,
      ];
      // 268 at 8.2 s, let go about 6 ms before its next frame: 434 px, then 310, 55, -18, -11 px. A frame after the
      // let-go the spring has 44% left, two frames 1.4%, then it overshoots by about 5%.
      expect(left[0] / pulled, moreOrLessEquals(0.444, epsilon: 0.02));
      expect(left[1] / pulled, moreOrLessEquals(0.014, epsilon: 0.02));
      expect(left[2] / pulled, moreOrLessEquals(-0.048, epsilon: 0.02));
    });

    sheetTest('the full sheet dragged past half lands on half', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.full);
      drag(StorySheetTheme.halfTop - StorySheetTheme.fullTop + 20);
      expect(sheet.stop, SheetStop.half);
      await frames(tester, 300);
      expect(sheet.position.value, 1);
    });

    sheetTest('a fling moves on a stop that way: half up to full, full down to half, half down to closed', (
      tester,
    ) async {
      await make(tester);
      await rest(tester, SheetStop.half);
      drag(-30, velocity: -1500);
      expect(sheet.stop, SheetStop.full);
      await frames(tester, 300);
      expect(sheet.position.value, 2);

      drag(30, velocity: 1500);
      expect(sheet.stop, SheetStop.half);
      await frames(tester, 300);
      expect(sheet.position.value, 1);

      drag(30, velocity: 1500);
      expect(sheet.stop, SheetStop.closed);
      // Closing takes the 100 ms curve, without a bounce.
      final seen = await frames(tester, 150);
      expect(seen.every((position) => position >= 0 && position <= 1), isTrue);
      expect(sheet.position.value, 0);
      expect(sheet.isOpen, isFalse);
    });

    sheetTest('the fling speed: 300 pt/s let go jumps back, 400 moves on', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.full);
      drag(60, velocity: 300);
      expect(sheet.stop, SheetStop.full);
      await frames(tester, 300);
      drag(60, velocity: 400);
      expect(sheet.stop, SheetStop.half);
    });

    sheetTest('half dragged down a little and let go slowly comes back; far down, it closes', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.half);
      drag(100);
      expect(sheet.stop, SheetStop.half);
      await frames(tester, 300);
      expect(sheet.position.value, 1);

      drag((screen - StorySheetTheme.halfTop) * 0.6);
      expect(sheet.stop, SheetStop.closed);
      await frames(tester, 150);
      expect(sheet.position.value, 0);
    });

    sheetTest('a jump back starts at the finger\'s speed: let go moving away, it comes back later', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.full);
      Future<double> afterAFrame(double velocity) async {
        drag(100, velocity: velocity);
        final left = (await frames(tester, 17)).single;
        await frames(tester, 300);
        expect(sheet.position.value, 2);
        return StorySheetController.topFor(left, screen) - StorySheetTheme.fullTop;
      }

      final still = await afterAFrame(0);
      final away = await afterAFrame(250);
      final towards = await afterAFrame(-250);
      expect(away, greaterThan(still));
      expect(towards, lessThan(still));
    });

    sheetTest('a new drag catches the sheet where it is', (tester) async {
      await make(tester);
      await rest(tester, SheetStop.half);
      sheet.toggle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final caught = sheet.position.value;
      sheet.dragStart();
      await tester.pump(const Duration(milliseconds: 50));
      expect(sheet.position.value, caught);
      sheet.dragEnd(0, screen);
    });
  });
}
