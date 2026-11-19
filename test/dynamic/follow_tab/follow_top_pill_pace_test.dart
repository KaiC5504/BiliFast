import 'dart:ui' as ui;

import 'package:bilifast/shared/paced_gif.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 直播中's bars: 20 pictures of 30 ms.
const _gif = 'assets/images/live/live_ing.gif';

Future<void> _show(WidgetTester tester, {bool ticking = true, bool still = false}) async {
  await tester.runAsync(() => PacedGif.load(_gif));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: TickerMode(
        enabled: ticking,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: PacedGif(_gif, size: Size.square(16))),
        ),
      ),
    ),
  );
  await tester.pump();
}

ui.Image? _shown(WidgetTester tester) => tester.widget<RawImage>(find.byType(RawImage)).image;

/// Over [seconds] on a 60 Hz display, where a frame asked for is drawn at the next vsync: the frames drawn, and how
/// many of them showed another picture.
Future<({int drawn, int pictures})> _run(WidgetTester tester, int seconds) async {
  const vsync = 1000000 ~/ 60;
  var now = 0;
  var drawn = 0;
  var pictures = 0;
  var last = _shown(tester);
  while (now < seconds * 1000000) {
    await tester.binding.delayed(const Duration(milliseconds: 1));
    now += 1000;
    if (!tester.binding.hasScheduledFrame) continue;
    final next = (now ~/ vsync + 1) * vsync;
    await tester.binding.delayed(Duration(microseconds: next - now));
    now = next;
    await tester.pump();
    drawn++;
    final shown = _shown(tester);
    if (!identical(shown, last)) pictures++;
    last = shown;
  }
  return (drawn: drawn, pictures: pictures);
}

void main() {
  testWidgets('one frame of the app per picture, 30 a second, where Image asked for two', (tester) async {
    await _show(tester);
    expect(_shown(tester), isNotNull);
    final run = await _run(tester, 2);
    expect(run.drawn / 2, closeTo(30, 2));
    expect(run.pictures, run.drawn, reason: 'no frame shows the picture it already had');
  });

  testWidgets('a muted TickerMode asks for no frame and holds its picture; unmuted it moves again', (tester) async {
    await _show(tester, ticking: false);
    final held = _shown(tester);
    expect((await _run(tester, 1)).drawn, 0);
    expect(_shown(tester), same(held));

    await _show(tester);
    expect((await _run(tester, 1)).pictures, greaterThan(20));
  });

  testWidgets('Reduce Motion holds the first picture', (tester) async {
    await _show(tester, still: true);
    final first = (await tester.runAsync(() => PacedGif.load(_gif)))!.first.image;
    expect(_shown(tester), same(first));
    expect((await _run(tester, 1)).drawn, 0);
  });
}
