import 'package:bili_core/api.dart' show Chapter;
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _chapters = [
  Chapter(from: 0, to: 30, title: '开场'),
  Chapter(from: 30, to: 70, title: '正片'),
  Chapter(from: 70, to: 100, title: '结尾'),
];

const _phone = Size(956, 440);
const _pad = Size(1194, 834);

const _tick = 'HapticFeedbackType.selectionClick';

/// A 218 pt bar over a 100 s video: the TV's centre travels 200 pt, 2 pt a second, so the dots sit at 69 and 149.
final class _Bar {
  double position = 0;
  final repaint = ValueNotifier(0);
  final commits = <double>[];

  Future<void> mount(WidgetTester tester, {List<Chapter> chapters = _chapters, Size screen = _phone}) async {
    addTearDown(repaint.dispose);
    await tester.runAsync(SeekBar.precache);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: screen),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 218,
              child: SeekBar(
                position: () => position,
                duration: () => 100,
                buffered: () => 0,
                repaint: repaint,
                onScrub: (seconds) {
                  position = seconds;
                  repaint.value++;
                },
                onCommit: commits.add,
                onCancel: () {},
                chapters: chapters,
              ),
            ),
          ),
        ),
      ),
    );
  }

  RenderObject painter(WidgetTester tester) =>
      tester.renderObject(find.descendant(of: find.byType(SeekBar), matching: find.byType(CustomPaint)).first);

  Offset at(WidgetTester tester, double seconds) =>
      tester.getRect(find.byType(SeekBar)).centerLeft + Offset(9 + 2 * seconds, 0);

  /// A finger on the thumb, moved 10 s past the drag's slop to take hold of the bar.
  Future<TestGesture> hold(WidgetTester tester) async {
    final finger = await tester.startGesture(at(tester, position));
    await finger.moveBy(const Offset(20, 0));
    await tester.pump();
    return finger;
  }
}

/// A chapter dot of [radius] at [x] on the bar's middle.
PaintPattern _dot(PaintPattern pattern, double x, double radius) =>
    pattern..circle(x: x, y: BiliMetrics.barTouchHeight / 2, radius: radius, color: ChapterDotTheme.color);

void main() {
  late List<Object?> haptics;

  setUp(() {
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
        return null;
      },
    );
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  group('the dots (272)', () {
    testWidgets('each chapter start but the first is a light round dot as thick as the bar: 2 pt at rest', (
      tester,
    ) async {
      final bar = _Bar();
      await bar.mount(tester);
      const rest = BiliMetrics.barHeight * ChapterDotTheme.barShare / 2;
      expect(rest, 1);
      expect(bar.painter(tester), _dot(_dot(paints, 69, rest), 149, rest));
      expect(bar.painter(tester), paintsExactlyCountTimes(#drawCircle, 2));
      expect(bar.painter(tester), paintsExactlyCountTimes(#drawRect, 0), reason: 'no dark ticks');
    });

    testWidgets('they grow with the bar as it is held, to 4 pt, and back when it lifts', (tester) async {
      final bar = _Bar();
      await bar.mount(tester);
      final finger = await bar.hold(tester);
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        bar.painter(tester),
        paints..something((method, arguments) {
          if (method != #drawCircle) return false;
          final radius = arguments[1] as double;
          return radius > 1 && radius < 2;
        }),
        reason: 'on its way',
      );
      await tester.pumpAndSettle();
      const held = BiliMetrics.tvBarDragHeight * ChapterDotTheme.barShare / 2;
      expect(held * 2, 12 / 3, reason: "272: 12 px across, the held bar's thickness");
      expect(bar.painter(tester), _dot(_dot(paints, 69, held), 149, held));

      await finger.up();
      await tester.pumpAndSettle();
      expect(bar.painter(tester), _dot(_dot(paints, 69, 1), 149, 1));
    });

    testWidgets('no dots without chapters, nor for a lone chapter starting the bar', (tester) async {
      final bar = _Bar();
      await bar.mount(tester, chapters: const []);
      expect(bar.painter(tester), paintsExactlyCountTimes(#drawCircle, 0));

      final lone = _Bar();
      await lone.mount(tester, chapters: const [Chapter(from: 0, to: 100, title: '全片')]);
      expect(lone.painter(tester), paintsExactlyCountTimes(#drawCircle, 0), reason: 'the first starts the bar');
    });

    testWidgets('held, no title shows over the thumb', (tester) async {
      final bar = _Bar()..position = 20;
      await bar.mount(tester);
      final finger = await bar.hold(tester);
      await tester.pumpAndSettle();
      expect(bar.position, 30);
      expect(find.byType(Text), findsNothing);
      await finger.moveBy(const Offset(20, 0));
      await tester.pumpAndSettle();
      expect(find.text('正片'), findsNothing);
      await finger.up();
      await tester.pumpAndSettle();
    });
  });

  group('the tick of the hand', () {
    testWidgets('a drag across a dot ticks once each way', (tester) async {
      final bar = _Bar()..position = 10;
      await bar.mount(tester);
      final finger = await bar.hold(tester);
      expect(bar.position, 20);
      expect(haptics, isEmpty);

      await finger.moveBy(const Offset(30, 0));
      expect(bar.position, 35);
      expect(haptics, [_tick]);
      await finger.moveBy(const Offset(10, 0));
      expect(haptics, [_tick], reason: 'still inside 正片');

      await finger.moveBy(const Offset(-20, 0));
      expect(bar.position, 30);
      expect(haptics, [_tick], reason: 'on the dot is past it');
      await finger.moveBy(const Offset(-4, 0));
      expect(bar.position, 28);
      expect(haptics, [_tick, _tick]);

      await finger.up();
      await tester.pumpAndSettle();
      expect(bar.commits, [28]);
      expect(haptics, hasLength(2), reason: 'the lift ticks nothing');
    });

    testWidgets('several dots in one move tick once', (tester) async {
      final bar = _Bar()..position = 10;
      await bar.mount(tester);
      final finger = await bar.hold(tester);
      await finger.moveBy(const Offset(120, 0));
      expect(bar.position, 80);
      expect(haptics, [_tick]);
      await finger.moveBy(const Offset(-140, 0));
      expect(bar.position, 10);
      expect(haptics, [_tick, _tick]);
      await finger.up();
      await tester.pumpAndSettle();
    });

    testWidgets('no tick within one chapter, nor across the bar without chapters', (tester) async {
      final bar = _Bar()..position = 32;
      await bar.mount(tester);
      var finger = await bar.hold(tester);
      await finger.moveBy(const Offset(40, 0));
      await finger.moveBy(const Offset(-60, 0));
      expect(bar.position, 32);
      await finger.up();
      await tester.pumpAndSettle();
      expect(haptics, isEmpty);

      final bare = _Bar()..position = 10;
      await bare.mount(tester, chapters: const []);
      finger = await bare.hold(tester);
      await finger.moveBy(const Offset(140, 0));
      expect(bare.position, 90);
      await finger.up();
      await tester.pumpAndSettle();
      expect(haptics, isEmpty);
    });

    testWidgets('a tap on a dot, a touch that never drags and a VoiceOver step tick nothing', (tester) async {
      final semantics = tester.ensureSemantics();
      final bar = _Bar()..position = 25;
      await bar.mount(tester);
      await tester.tapAt(bar.at(tester, 30));
      final finger = await tester.startGesture(bar.at(tester, 30));
      await tester.pump(const Duration(milliseconds: 300));
      await finger.up();
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byType(SeekBar));
      node.owner!.performAction(node.id, SemanticsAction.increase);
      expect(bar.commits, [35]);
      expect(haptics, isEmpty);
      semantics.dispose();
    });
  });

  group('the iPad, unchanged', () {
    testWidgets('keeps its dark ticks and the title over the thumb, and ticks no hand', (tester) async {
      final bar = _Bar()..position = 10;
      await bar.mount(tester, screen: _pad);
      expect(bar.painter(tester), paintsExactlyCountTimes(#drawRect, 2));
      expect(bar.painter(tester), paints..rect(color: BiliColors.chromeTick));
      expect(bar.painter(tester), paintsExactlyCountTimes(#drawCircle, 0));

      final finger = await bar.hold(tester);
      await tester.pumpAndSettle();
      expect(find.text('开场'), findsOneWidget);
      await finger.moveBy(const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(bar.position, 35);
      expect(find.text('正片'), findsOneWidget);
      expect(haptics, isEmpty);
      await finger.up();
      await tester.pumpAndSettle();
      expect(find.text('正片'), findsNothing);
    });
  });
}
