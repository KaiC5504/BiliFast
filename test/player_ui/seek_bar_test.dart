import 'package:bili_core/api.dart' show Chapter;
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _chapters = [
  Chapter(from: 0, to: 30, title: '开场'),
  Chapter(from: 30, to: 70, title: '正片'),
  Chapter(from: 70, to: 100, title: ''),
];

final class Rig {
  double position = 0;
  double duration = 100;
  final repaint = ValueNotifier(0);
  final scrubs = <double>[];
  final commits = <double>[];
  int cancels = 0;

  Future<void> mount(
    WidgetTester tester, {
    List<Chapter> chapters = const [],
    SeekBarStyle? style,
    bool still = false,
  }) async {
    addTearDown(repaint.dispose);
    await tester.runAsync(SeekBar.precache);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 218,
              child: SeekBar(
                position: () => position,
                duration: () => duration,
                buffered: () => 0,
                repaint: repaint,
                onScrub: _scrub,
                onCommit: commits.add,
                onCancel: () => cancels++,
                chapters: chapters,
                style: style ?? SeekBarStyle.tv,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _scrub(double seconds) {
    scrubs.add(seconds);
    position = seconds;
    repaint.value++;
  }

  RenderObject painter(WidgetTester tester) =>
      tester.renderObject(find.descendant(of: find.byType(SeekBar), matching: find.byType(CustomPaint)).first);

  Rect rect(WidgetTester tester) => tester.getRect(find.byType(SeekBar));

  SeekBarState state(WidgetTester tester) => tester.state<SeekBarState>(find.byType(SeekBar));

  /// Where the thumb's centre is for [seconds]: the bar is 218 wide, so the TV's centre travels 200 for 100 s.
  Offset thumb(WidgetTester tester, double seconds) =>
      rect(tester).centerLeft + Offset(BiliMetrics.thumbWidth / 2 + (218 - BiliMetrics.thumbWidth) * seconds / 100, 0);
}

/// Lets a finger take hold of the bar and move it past the slop, then [steps] more moves of [by].
Future<TestGesture> _hold(WidgetTester tester, Rig rig, {double by = 4, int steps = 0}) async {
  final finger = await tester.startGesture(rig.thumb(tester, rig.position));
  await finger.moveBy(Offset(by.sign * 20, 0));
  await tester.pump();
  for (var i = 0; i < steps; i++) {
    await finger.moveBy(Offset(by, 0));
  }
  await tester.pump();
  return finger;
}

void main() {
  testWidgets('a tick marks each chapter start inside the video, not the first at 0', (tester) async {
    final rig = Rig();
    await rig.mount(tester, chapters: _chapters);
    expect(rig.painter(tester), paintsExactlyCountTimes(#drawRect, 2));
    expect(rig.painter(tester), paints..rect(color: BiliColors.chromeTick));
  });

  testWidgets('without chapters there are no ticks', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(rig.painter(tester), paintsExactlyCountTimes(#drawRect, 0));
  });

  testWidgets('no ticks before the duration is known', (tester) async {
    final rig = Rig()..duration = 0;
    await rig.mount(tester, chapters: _chapters);
    expect(rig.painter(tester), paintsExactlyCountTimes(#drawRect, 0));
  });

  testWidgets('the chapter under the thumb shows its title while dragging, and goes when the finger lifts', (
    tester,
  ) async {
    final rig = Rig();
    await rig.mount(tester, chapters: _chapters);
    expect(find.text('开场'), findsNothing);

    final rect = rig.rect(tester);
    final gesture = await tester.startGesture(rect.centerLeft + const Offset(30, 0));
    await gesture.moveBy(const Offset(4, 0));
    await tester.pumpAndSettle();
    expect(find.text('开场'), findsOneWidget);
    final title = tester.getRect(find.text('开场'));
    expect(title.bottom, lessThan(rect.top), reason: 'the title sits above the bar');

    await gesture.moveTo(rect.center);
    await tester.pumpAndSettle();
    expect(find.text('正片'), findsOneWidget);
    expect(find.text('开场'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('正片'), findsNothing);
    expect(rig.commits, hasLength(1));
  });

  testWidgets('a chapter without a title shows nothing', (tester) async {
    final rig = Rig()..position = 80;
    await rig.mount(tester, chapters: _chapters);
    final rect = rig.rect(tester);
    final gesture = await tester.startGesture(rect.centerRight - const Offset(10, 0));
    await gesture.moveBy(const Offset(-4, 0));
    await tester.pumpAndSettle();
    expect(rig.position, greaterThan(70));
    expect(find.byType(Text), findsNothing);
    await gesture.up();
  });

  test('the chapter holding a position', () {
    expect(SeekBar.chapterTitle(_chapters, 10), '开场');
    expect(SeekBar.chapterTitle(_chapters, 30), '正片');
    expect(SeekBar.chapterTitle(_chapters, 80), isNull);
    expect(SeekBar.chapterTitle(const [], 10), isNull);
    expect(SeekBar.chapterTitle(const [Chapter(from: 20, to: 40, title: '中段')], 10), isNull);
  });

  testWidgets('a drag moves the position by the distance dragged, wherever the finger lands, and commits it', (
    tester,
  ) async {
    final rig = Rig()..position = 50;
    await rig.mount(tester);
    final rect = rig.rect(tester);
    final travel = rect.width - BiliMetrics.thumbWidth;

    // Near the start of the bar, far from the thumb at the middle: nothing jumps there.
    final gesture = await tester.startGesture(rect.centerLeft + const Offset(20, 0));
    await tester.pump();
    expect(rig.scrubs, isEmpty);
    await gesture.moveBy(Offset(travel / 4, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(rig.scrubs.last, closeTo(75, 0.01));
    expect(rig.commits.single, closeTo(75, 0.01));
  });

  testWidgets('a drag holds the bar until it lifts; a tap never holds it', (tester) async {
    final holds = <bool>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 218,
            child: SeekBar(
              position: () => 50,
              duration: () => 100,
              buffered: () => 0,
              repaint: ValueNotifier(0),
              onScrub: (_) {},
              onCommit: (_) {},
              onCancel: () {},
              onHold: holds.add,
            ),
          ),
        ),
      ),
    );
    final centre = tester.getCenter(find.byType(SeekBar));
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(holds, isEmpty);

    final finger = await tester.startGesture(centre);
    await finger.moveBy(const Offset(30, 0));
    expect(holds, [true]);
    await finger.up();
    expect(holds, [true, false]);
    await tester.pumpAndSettle();
  });

  testWidgets('a tap on the bar seeks nowhere', (tester) async {
    final rig = Rig()..position = 50;
    await rig.mount(tester);
    final rect = rig.rect(tester);
    await tester.tapAt(rect.centerLeft + const Offset(20, 0));
    await tester.tapAt(rect.centerRight - const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(rig.scrubs, isEmpty);
    expect(rig.commits, isEmpty);
    expect(rig.position, 50);
  });

  testWidgets('the 竖屏 style draws a white dot and no TV face', (tester) async {
    final rig = Rig()..position = 50;
    await rig.mount(tester, style: SeekBarStyle.dot);
    expect(
      rig.painter(tester),
      paints
        ..rrect(color: BiliColors.verticalTrack)
        ..rrect(color: BiliColors.verticalPlayed)
        ..circle(color: BiliColors.verticalThumb),
    );
    expect(rig.painter(tester), paintsExactlyCountTimes(#drawRRect, 2), reason: 'no buffered part');
  });

  testWidgets('the TV style draws no dot', (tester) async {
    final rig = Rig()..position = 50;
    await rig.mount(tester);
    expect(rig.painter(tester), paintsExactlyCountTimes(#drawCircle, 0));
    expect(
      rig.painter(tester),
      paints
        ..rrect(color: BiliColors.chromeTrack)
        ..rrect(color: BiliColors.chromeBuffered)
        ..rrect(color: BiliColors.pink),
    );
  });

  testWidgets('the 竖屏 style drags the whole video across the bar less the dot, and stops at the ends', (tester) async {
    final rig = Rig();
    await rig.mount(tester, style: SeekBarStyle.dot);
    final rect = rig.rect(tester);
    final travel = rect.width - BiliMetrics.verticalDot;

    await tester.dragFrom(rect.center, Offset(travel, 0));
    await tester.pumpAndSettle();
    expect(rig.commits.last, closeTo(100, 0.01));
    await tester.dragFrom(rect.center, Offset(travel * 2, 0));
    await tester.pumpAndSettle();
    expect(rig.commits.last, 100);
    await tester.dragFrom(rect.center, Offset(-travel * 3, 0));
    await tester.pumpAndSettle();
    expect(rig.commits.last, 0);
  });

  testWidgets('VoiceOver reads the time and steps it by ten seconds through the commit', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig()..position = 30;
    await rig.mount(tester);

    final node = tester.getSemantics(find.byType(SeekBar));
    expect(
      node,
      isSemantics(
        label: '进度',
        value: '00:30 / 01:40',
        increasedValue: '00:40 / 01:40',
        decreasedValue: '00:20 / 01:40',
        isSlider: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );

    node.owner!.performAction(node.id, SemanticsAction.increase);
    node.owner!.performAction(node.id, SemanticsAction.decrease);
    expect(rig.commits, [40, 20]);

    rig.position = 95;
    rig.repaint.value++;
    await tester.pump();
    expect(tester.getSemantics(find.byType(SeekBar)), isSemantics(value: '01:35 / 01:40'));
    node.owner!.performAction(node.id, SemanticsAction.increase);
    rig.position = 4;
    node.owner!.performAction(node.id, SemanticsAction.decrease);
    expect(rig.commits.skip(2), [100, 0], reason: 'a step stops at the ends');
    semantics.dispose();
  });

  testWidgets('before the duration is known VoiceOver gets no time and no steps', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig()..duration = 0;
    await rig.mount(tester);
    expect(
      tester.getSemantics(find.byType(SeekBar)),
      isSemantics(label: '进度', value: '', hasIncreaseAction: false, hasDecreaseAction: false),
    );
    semantics.dispose();
  });

  testWidgets('the hidden line draws only the played part, with round ends and no track', (tester) async {
    var position = 25.0;
    final repaint = ValueNotifier(0);
    addTearDown(repaint.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: 400,
            child: HiddenProgressLine(position: () => position, duration: () => 100, repaint: repaint),
          ),
        ),
      ),
    );
    RenderObject line() =>
        tester.renderObject(find.descendant(of: find.byType(HiddenProgressLine), matching: find.byType(CustomPaint)));
    const height = BiliMetrics.hiddenLine;
    expect(
      line(),
      paints
        ..rrect(rrect: RRect.fromLTRBR(0, 0, 100, height, const Radius.circular(height / 2)), color: BiliColors.pink),
    );
    expect(line(), paintsExactlyCountTimes(#drawRRect, 1));
    expect(line(), paintsExactlyCountTimes(#drawRect, 0));

    position = 0;
    repaint.value++;
    await tester.pump();
    expect(line(), paintsNothing);
  });

  testWidgets('the dot grows under the finger and shrinks back', (tester) async {
    final rig = Rig()..position = 50;
    await rig.mount(tester, style: SeekBarStyle.dot);
    expect(rig.painter(tester), paints..circle(radius: BiliMetrics.verticalDot / 2));

    final gesture = await tester.startGesture(rig.rect(tester).center);
    await tester.pumpAndSettle();
    expect(rig.painter(tester), paints..circle(radius: BiliMetrics.verticalDotDragging / 2));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(rig.painter(tester), paints..circle(radius: BiliMetrics.verticalDot / 2));
  });

  group('the TV', () {
    test('each change moves the eyes a step its way, up to the ends, and none steps them back', () {
      var look = 0;
      for (var i = 0; i < 3; i++) {
        look = SeekBar.lookAfter(look, 0.4);
      }
      expect(SeekBar.eyesOf(look), closeTo(0.65, 1e-9));
      for (var i = 0; i < 20; i++) {
        look = SeekBar.lookAfter(look, 2);
      }
      expect(SeekBar.eyesOf(look), 1);
      look = SeekBar.lookAfter(look, 0);
      expect(SeekBar.eyesOf(look), closeTo(0.95, 1e-9));
      for (var i = 0; i < 40; i++) {
        look = SeekBar.lookAfter(look, -0.01);
      }
      expect(SeekBar.eyesOf(look), 0);
      for (var i = 0; i < 9; i++) {
        look = SeekBar.lookAfter(look, 0);
      }
      expect(SeekBar.eyesOf(look), closeTo(0.45, 1e-9));
      look = SeekBar.lookAfter(look, 0);
      expect(SeekBar.eyesOf(look), SeekBar.eyesAtRest);
      expect(SeekBar.lookAfter(look, 0), 0, reason: 'at rest a change of none leaves them centred');
    });

    testWidgets('draws the official Lottie in its 18 pt box, centred on the bar and the played part\'s end', (
      tester,
    ) async {
      final rig = Rig()..position = 50;
      await rig.mount(tester);
      final box = Rect.fromCenter(
        center: rig.thumb(tester, 50) - rig.rect(tester).topLeft,
        width: BiliMetrics.thumbWidth,
        height: BiliMetrics.thumbHeight,
      );
      expect(box.top, (BiliMetrics.barTouchHeight - BiliMetrics.thumbHeight) / 2);
      expect(
        rig.painter(tester),
        paints
          ..rrect(color: BiliColors.chromeTrack)
          ..rrect(color: BiliColors.chromeBuffered)
          ..rrect(color: BiliColors.pink)
          ..save()
          ..translate(x: box.left, y: box.top),
      );
      expect(rig.state(tester).eyes, SeekBar.eyesAtRest);
      expect(rig.state(tester).blink, isNull);
    });

    testWidgets('the eyes step with each move of the drag, each way, and stop at the ends', (tester) async {
      final rig = Rig()..position = 50;
      await rig.mount(tester);
      final finger = await _hold(tester, rig);
      final state = rig.state(tester);
      final first = state.eyes;
      expect(first, greaterThan(SeekBar.eyesAtRest), reason: 'taking hold moved it later');

      for (var i = 1; i <= 3; i++) {
        await finger.moveBy(const Offset(4, 0));
        expect(state.eyes, closeTo(first + i * SeekBar.eyesStep, 1e-9));
      }
      await finger.moveBy(const Offset(-4, 0));
      expect(state.eyes, closeTo(first + 2 * SeekBar.eyesStep, 1e-9));

      for (var i = 0; i < 12; i++) {
        await finger.moveBy(const Offset(2, 0));
      }
      expect(state.eyes, 1);
      for (var i = 0; i < 25; i++) {
        await finger.moveBy(const Offset(-2, 0));
      }
      expect(state.eyes, 0);
      expect(rig.position, greaterThan(0), reason: 'the eyes stopped before the bar did');
      await finger.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a move that changes nothing steps the eyes back toward the centre', (tester) async {
      final rig = Rig()..position = 80;
      await rig.mount(tester);
      final finger = await _hold(tester, rig, steps: 5);
      final state = rig.state(tester);
      expect(rig.position, 100, reason: 'the last move reached the end');
      final looking = state.eyes;
      expect(looking, greaterThan(SeekBar.eyesAtRest + SeekBar.eyesStep));

      await finger.moveBy(const Offset(4, 0));
      expect(state.eyes, closeTo(looking - SeekBar.eyesStep, 1e-9));
      for (var i = 0; i < 20; i++) {
        await finger.moveBy(const Offset(4, 0));
      }
      expect(state.eyes, SeekBar.eyesAtRest);
      await finger.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a touch centres the eyes before it moves anything', (tester) async {
      final rig = Rig()..position = 50;
      await rig.mount(tester);
      final finger = await _hold(tester, rig, steps: 4);
      await finger.up();
      await tester.pump(const Duration(milliseconds: 40));
      expect(rig.state(tester).eyes, isNot(SeekBar.eyesAtRest), reason: 'still on the way back');

      final again = await tester.startGesture(rig.thumb(tester, rig.position));
      await tester.pump();
      expect(rig.state(tester).eyes, SeekBar.eyesAtRest);
      expect(rig.state(tester).blink, isNull);
      await again.up();
      await tester.pumpAndSettle();
    });

    testWidgets('when a drag lifts the eyes come back, then the TV blinks once and rests', (tester) async {
      final rig = Rig()..position = 50;
      await rig.mount(tester);
      final finger = await _hold(tester, rig, steps: 6);
      final state = rig.state(tester);
      final away = state.eyes - SeekBar.eyesAtRest;
      expect(away, greaterThan(0.2));

      await finger.up();
      await tester.pump();
      expect(state.blink, isNull, reason: 'not before the eyes are back');
      final back = SeekBar.eyesReturn * (away / SeekBar.eyesAtRest);
      await tester.pump(back ~/ 2);
      expect(state.eyes, inExclusiveRange(SeekBar.eyesAtRest, SeekBar.eyesAtRest + away));
      await tester.pump(back ~/ 2 + const Duration(milliseconds: 20));
      expect(state.eyes, SeekBar.eyesAtRest);

      final blinks = <double>[];
      for (var i = 0; i < 30 && tester.hasRunningAnimations; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (state.blink case final blink?) blinks.add(blink);
      }
      expect(blinks, isNotEmpty);
      expect(blinks.first, lessThan(0.1));
      expect(blinks.last, greaterThan(0.9));
      // 12 frames at 29.97 fps.
      expect(blinks.length * 16, closeTo(400, 32));
      expect(tester.hasRunningAnimations, isFalse);
      expect(state.blink, isNull);
      expect(state.eyes, SeekBar.eyesAtRest);
      expect(rig.commits, hasLength(1));
    });

    testWidgets('a tap and a touch that never became a drag do not blink', (tester) async {
      final rig = Rig()..position = 50;
      await rig.mount(tester);
      final state = rig.state(tester);
      await tester.tapAt(rig.thumb(tester, 50));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(state.blink, isNull);
      }

      final cancels = rig.cancels;
      final finger = await tester.startGesture(rig.thumb(tester, 50));
      await finger.moveBy(const Offset(5, 0));
      await finger.cancel();
      expect(rig.cancels, cancels + 1);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(state.blink, isNull);
      }
      expect(state.eyes, SeekBar.eyesAtRest);
    });

    testWidgets('Reduce Motion puts the eyes back at once and skips the blink', (tester) async {
      final rig = Rig()..position = 50;
      await rig.mount(tester, still: true);
      final finger = await _hold(tester, rig, steps: 6);
      final state = rig.state(tester);
      expect(state.eyes, greaterThan(SeekBar.eyesAtRest), reason: 'the eyes still follow the finger');

      await finger.up();
      expect(state.eyes, SeekBar.eyesAtRest);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(state.blink, isNull);
      }
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the TV keeps its size while held, and the bar thickens to 4 pt', (tester) async {
      final rig = Rig()..position = 50;
      await rig.mount(tester);
      final box = rig.thumb(tester, 50) - rig.rect(tester).topLeft - const Offset(9, 9);
      const rest = BiliMetrics.barHeight;
      expect(rig.painter(tester), paints..rrect(rrect: _capsule(218, rest), color: BiliColors.chromeTrack));

      final finger = await tester.startGesture(rig.thumb(tester, 50));
      await tester.pumpAndSettle();
      expect(
        rig.painter(tester),
        paints
          ..rrect(rrect: _capsule(218, BiliMetrics.tvBarDragHeight), color: BiliColors.chromeTrack)
          ..save()
          ..translate(x: box.dx, y: box.dy),
      );
      await finger.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the 竖屏 dot has no eyes to move and never blinks', (tester) async {
      final rig = Rig()..position = 50;
      await rig.mount(tester, style: SeekBarStyle.dot);
      final finger = await tester.startGesture(rig.rect(tester).center);
      await tester.pumpAndSettle();
      expect(
        rig.painter(tester),
        paints..rrect(rrect: _capsule(218, BiliMetrics.barDragHeight), color: BiliColors.verticalTrack),
      );
      for (var i = 0; i < 5; i++) {
        await finger.moveBy(const Offset(10, 0));
      }
      await finger.up();
      final state = rig.state(tester);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(state.blink, isNull);
      }
      expect(rig.painter(tester), paintsExactlyCountTimes(#drawPath, 0));
      expect(rig.painter(tester), paints..circle(radius: BiliMetrics.verticalDot / 2, color: BiliColors.verticalThumb));
    });
  });
}

RRect _capsule(double width, double height) => RRect.fromLTRBR(
  0,
  (BiliMetrics.barTouchHeight - height) / 2,
  width,
  (BiliMetrics.barTouchHeight + height) / 2,
  Radius.circular(height / 2),
);
