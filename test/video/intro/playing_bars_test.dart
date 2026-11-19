import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/collection_row.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bars_ink.dart';

const _boundary = ValueKey('boundary');

/// Room around the mark's box, which a full stretch reaches past.
const _margin = 2.0;

Future<void> _show(WidgetTester tester, Widget bars, {bool reduceMotion = false}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: _boundary,
            child: Padding(padding: const EdgeInsets.all(_margin), child: bars),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<List<Bar>> _bars(WidgetTester tester) => barsIn(tester, find.byKey(_boundary));

List<double> _heights(List<Bar> bars) => [for (final bar in bars) bar.height];

void main() {
  const grey = Color(0xFF9499A0);

  group('moving', () {
    setUp(() => PlayingBars.debugHoldStill = false);

    testWidgets('rises and falls out of step, and keeps going past the loop', (tester) async {
      await _show(tester, const PlayingBars(color: grey));
      final first = _heights(await _bars(tester));
      await tester.pump(const Duration(milliseconds: 250));
      final later = _heights(await _bars(tester));
      expect(first, hasLength(3));
      expect(later, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect((later[i] - first[i]).abs(), greaterThan(0.5), reason: 'bar $i moves');
      }
      await tester.pump(const Duration(seconds: 10));
      expect(tester.hasRunningAnimations, isTrue);
      final heights = <double>{};
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 165));
        heights.add((_heights(await _bars(tester))[1] * 4).roundToDouble() / 4);
      }
      expect(heights.length, greaterThan(3), reason: 'still moving ten seconds on');
    });

    testWidgets('every bar spans the full stretch, 12.43 at its tallest and 5.16 at its shortest', (tester) async {
      await _show(tester, const PlayingBars(color: grey));
      final tallest = [0.0, 0.0, 0.0];
      final shortest = [99.0, 99.0, 99.0];
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(microseconds: 1000000 ~/ 60));
        for (final (index, height) in _heights(await _bars(tester)).indexed) {
          tallest[index] = tallest[index] < height ? height : tallest[index];
          shortest[index] = shortest[index] > height ? height : shortest[index];
        }
      }
      for (var i = 0; i < 3; i++) {
        expect(tallest[i], closeTo(71 * IntroListTheme.barStep / 24, 0.15));
        expect(shortest[i], closeTo(29.5 * IntroListTheme.barStep / 24, 0.15));
      }
    });

    testWidgets('a muted ticker stops it, as on a covered page', (tester) async {
      await _show(tester, const TickerMode(enabled: false, child: PlayingBars(color: grey)));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets('Reduce Motion holds it on font-check 02\'s frame: tall, short, nearly tall, 1.75 wide and 4.2 apart', (
    tester,
  ) async {
    PlayingBars.debugHoldStill = false;
    await _show(tester, const PlayingBars(color: grey), reduceMotion: true);
    expect(tester.hasRunningAnimations, isFalse);
    final bars = await _bars(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(_heights(await _bars(tester)), _heights(bars));

    expect(bars, hasLength(3));
    expect(bars[0].height, closeTo(11.87, 0.15));
    expect(bars[1].height, closeTo(5.73, 0.15));
    expect(bars[2].height, closeTo(11.03, 0.15));
    for (final bar in bars) {
      expect(bar.width, closeTo(IntroListTheme.barWidth, 0.1));
      expect(bar.y, closeTo(_margin + IntroListTheme.barsHeight / 2, 0.05));
    }
    const centre = _margin + IntroListTheme.barsWidth / 2;
    expect(bars[0].x, closeTo(centre - IntroListTheme.barStep, 0.05));
    expect(bars[1].x, closeTo(centre, 0.05));
    expect(bars[2].x, closeTo(centre + IntroListTheme.barStep, 0.05));
  });

  testWidgets('its box is the bars\' box at the given height, the mark scaled with it', (tester) async {
    const height = 11.05;
    const scale = height / IntroListTheme.barsHeight;
    await _show(tester, const PlayingBars(color: grey, height: height), reduceMotion: true);
    expect(tester.getSize(find.byType(PlayingBars)), const Size(IntroListTheme.barsWidth * scale, height));
    final bars = await _bars(tester);
    expect(bars[1].x - bars[0].x, closeTo(IntroListTheme.barStep * scale, 0.05));
    expect(bars[1].x, closeTo(_margin + IntroListTheme.barsWidth * scale / 2, 0.05));
    expect(bars[0].height, closeTo(11.87 * scale, 0.15));
  });

  testWidgets('draws in the colour it is given, and takes a new one when rebuilt', (tester) async {
    await _show(tester, const PlayingBars(color: Color(0xFF2E8B57)));
    for (final bar in await _bars(tester)) {
      expect(bar.ink, const Color(0xFF2E8B57));
    }
    await _show(tester, const PlayingBars(color: Color(0xFFD44E7D)));
    for (final bar in await _bars(tester)) {
      expect(bar.ink, const Color(0xFFD44E7D));
    }
  });
}
