import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/collection_row.dart';
import 'package:bilifast/video/intro/part_strip.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
// ignore: implementation_imports
import 'package:lottie/src/lottie.dart' show debugThrottleAnimationsInTests;

const _grey = Color(0xFF9499A0);

/// Counts its paints: whatever repaints the picture around the mark repaints this too.
class _CountingPainter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

bool _ticking(WidgetTester tester) => TickerMode.valuesOf(tester.element(find.byType(RawLottie, skipOffstage: false))).enabled;

double _progress(WidgetTester tester) => tester.widget<RawLottie>(find.byType(RawLottie, skipOffstage: false)).progress;

/// 简介's shape: a head that is never disposed (the mark [above] pt down in it), then a long list under it.
Future<ScrollController> _intro(WidgetTester tester, {double above = 300, ValueNotifier<double>? lead}) async {
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  final gap = lead ?? ValueNotifier(above);
  await tester.pumpWidget(
    MaterialApp(
      home: CustomScrollView(
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: gap,
                  builder: (context, height, _) => SizedBox(height: height),
                ),
                const PlayingBars(color: _grey),
              ],
            ),
          ),
          SliverList.builder(itemCount: 100, itemBuilder: (context, index) => const SizedBox(height: 80)),
        ],
      ),
    ),
  );
  await tester.pump();
  return scroll;
}

/// The check runs after the frame that moved it; its TickerMode lands in the next.
Future<void> _moved(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => PlayingBars.debugHoldStill = false);

  testWidgets('its frames repaint only its own layer, never the picture around it', (tester) async {
    final around = _CountingPainter();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(painter: around, size: const Size(20, 20)),
              const PlayingBars(color: _grey),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final first = _progress(tester);
    final paints = around.paints;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 1000 ~/ 60));
    }
    expect(_progress(tester), isNot(first), reason: 'it moved');
    expect(around.paints, paints);
  });

  testWidgets('it takes a new frame 30 times a second, not every vsync', (tester) async {
    await _intro(tester);
    final frames = <double>{};
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(microseconds: 1000000 ~/ 120));
      frames.add(_progress(tester));
    }
    expect(frames.length, inInclusiveRange(IntroListTheme.barsFps - 1, IntroListTheme.barsFps + 1));
  });

  testWidgets('the app draws 30 frames a second for it, not one per vsync', (tester) async {
    // The package parks its ticker on a timer between frames, which it turns off under flutter test.
    debugThrottleAnimationsInTests = true;
    addTearDown(() => debugThrottleAnimationsInTests = false);
    await _intro(tester);
    // A 60 Hz display: a frame asked for is drawn at the next vsync.
    const vsync = 1000000 ~/ 60;
    var now = 0;
    var drawn = 0;
    while (now < 2000000) {
      await tester.binding.delayed(const Duration(milliseconds: 1));
      now += 1000;
      if (!tester.binding.hasScheduledFrame) continue;
      final next = (now ~/ vsync + 1) * vsync;
      await tester.binding.delayed(Duration(microseconds: next - now));
      now = next;
      await tester.pump();
      drawn++;
    }
    expect(drawn / 2, closeTo(IntroListTheme.barsFps, 2));
  });

  testWidgets('scrolled away under the list it stops; back in sight it moves again', (tester) async {
    final scroll = await _intro(tester);
    expect(_ticking(tester), isTrue);
    expect(tester.hasRunningAnimations, isTrue);

    scroll.jumpTo(2000);
    await _moved(tester);
    expect(_ticking(tester), isFalse);
    expect(tester.hasRunningAnimations, isFalse, reason: 'nothing asks for frames');
    final held = _progress(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_progress(tester), held);

    scroll.jumpTo(250);
    await _moved(tester);
    expect(_ticking(tester), isTrue, reason: 'its last points show at the top');
    await tester.pump(const Duration(milliseconds: 200));
    expect(_progress(tester), isNot(held));
  });

  testWidgets('pushed out of sight and back by the content above it, with no scroll, it stops and moves again', (
    tester,
  ) async {
    final lead = ValueNotifier<double>(300);
    addTearDown(lead.dispose);
    await _intro(tester, lead: lead);
    expect(_ticking(tester), isTrue);

    lead.value = 2000;
    await _moved(tester);
    expect(_ticking(tester), isFalse);

    lead.value = 300;
    await _moved(tester);
    expect(_ticking(tester), isTrue);
  });

  testWidgets('a muted ticker around it still stops it while it is in sight', (tester) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, on, child) => TickerMode(enabled: on, child: child!),
          child: ListView(children: const [PlayingBars(color: _grey)]),
        ),
      ),
    );
    await tester.pump();
    expect(_ticking(tester), isTrue);
    enabled.value = false;
    await tester.pump();
    expect(_ticking(tester), isFalse);
    expect(tester.hasRunningAnimations, isFalse);
    enabled.value = true;
    await tester.pump();
    expect(_ticking(tester), isTrue);
  });

  testWidgets('the playing chip scrolled sideways out of the part strip stops, and moves again once back', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topCenter,
            child: PartStrip(
              parts: [
                for (var i = 0; i < 12; i++)
                  Episode(bvid: 'BVp', cid: i, title: 'P${i + 1}', current: i == 0),
              ],
              onChoose: (_) {},
              onOpenList: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_ticking(tester), isTrue);

    final strip = tester.widget<ListView>(find.byType(ListView)).controller!;
    strip.jumpTo(IntroListTheme.partChipWidth + IntroListTheme.partChipGap + BiliMetrics.gutter + 1);
    await _moved(tester);
    expect(find.byType(RawLottie, skipOffstage: false), findsOneWidget, reason: 'kept within the cache extent');
    expect(_ticking(tester), isFalse);

    strip.jumpTo(0);
    await _moved(tester);
    expect(_ticking(tester), isTrue);
  });

  testWidgets('Reduce Motion holds it without watching where it is', (tester) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Center(child: PlayingBars(color: _grey)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(_progress(tester), IntroListTheme.barsStill);
  });
}
