import 'dart:math' show pi;

import 'package:bili_core/devlog.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'turn_page_harness.dart';

/// 自绘 as the phone runs it: asked for with iOS's animations off, the screen turns inside the request, so the turn
/// can reach the page before the build that follows the change of presentation, and it reports the turn as taking no
/// time.
void main() {
  late MemorySink logs;

  setUp(() {
    logs = MemorySink();
    Logger.shared.add(logs);
    addTearDown(() => Logger.shared.remove(logs));
  });

  Iterable<LogEvent> lines(String kind) => logs.events.where((line) => line.msg == 'turn $kind');

  /// How far the player box has grown, from the small player's width (0) to full screen's (1).
  double grown(WidgetTester tester) {
    final width = tester.widget<Positioned>(TurnPage.box).width!;
    return (width - portrait.width) / (landscape.width - portrait.width);
  }

  /// The drawn turn's angle and grow over the official 300 ms from the build that began it, whatever iOS reported.
  Future<void> expectOfficialTurn(WidgetTester tester, {required double from}) async {
    expect(TurnPage.angle(tester), closeTo(from, 1e-9), reason: 'starts at −angle');
    final grow0 = grown(tester);
    await tester.pump(const Duration(milliseconds: 150));
    expect(TurnPage.angle(tester), closeTo(from / 2, 0.02), reason: 'halfway at 150 ms');
    expect(grown(tester), closeTo((grow0 + (from < 0 ? 1 : 0)) / 2, 0.02), reason: 'the box halfway at 150 ms');
    await tester.pump(const Duration(milliseconds: 140));
    expect(TurnPage.angle(tester), isNot(0), reason: 'still turning at 290 ms');
    await tester.pump(const Duration(milliseconds: 10));
    expect(TurnPage.angle(tester), 0, reason: 'upright at 300 ms');
    await tester.pump();
  }

  group('the turn reaching the page before its build', () {
    testWidgets('with the size after it: waited for, then drawn from the build at the new shape', (tester) async {
      final page = TurnPage();
      await page.open(tester);
      page.orientation.enterLandscape();
      final id = page.host.startTurn(pi / 2, duration: Duration.zero);
      expect(lines('started').single.f['outcome'], const LogString('pending'), reason: 'not unasked');
      await tester.pump();
      expect(TurnPage.angle(tester), 0, reason: 'nothing turned before the size');
      expect(tester.getRect(TurnPage.box), smallBox);
      await tester.pump(const Duration(milliseconds: 16));
      expect(page.host.drawnTurns, isEmpty, reason: 'the picture stays up for the turn still to be drawn');

      page.screen(tester, landscape);
      await tester.pump();
      expect(lines('began').single.f['ms'], const LogDouble(300), reason: 'the length drawn');
      expect(lines('started').single.f['ms'], const LogDouble(0), reason: 'the length iOS reported');
      await expectOfficialTurn(tester, from: -pi / 2);
      expect(tester.getRect(TurnPage.area), fullBox);
      expect(page.host.drawnTurns, [id], reason: 'once');
      await page.leave(tester);
    });

    testWidgets('with the size before it: drawn from the first build', (tester) async {
      final page = TurnPage();
      await page.open(tester);
      page.orientation.enterLandscape();
      page.screen(tester, landscape);
      final id = page.host.startTurn(pi / 2, duration: Duration.zero);
      await tester.pump();
      expect(lines('started').single.f['outcome'], const LogString('pending'));
      expect(page.host.drawnTurns, isEmpty, reason: 'not before the frame is on the screen');
      await expectOfficialTurn(tester, from: -pi / 2);
      expect(tester.getRect(TurnPage.area), fullBox);
      expect(page.host.drawnTurns, [id]);
      await page.leave(tester);
    });

    testWidgets('back to the small player', (tester) async {
      final page = TurnPage();
      await page.open(tester);
      await page.turnToLandscape(tester);
      await tester.pump(const Duration(milliseconds: 400));
      page.orientation.exitToInline();
      final id = page.host.startTurn(-pi / 2, duration: Duration.zero);
      page.screen(tester, portrait);
      await tester.pump();
      expect(lines('started').last.f['outcome'], const LogString('pending'));
      await expectOfficialTurn(tester, from: pi / 2);
      expect(tester.getRect(TurnPage.area), Rect.fromLTWH(0, 62, 440, 440 / BiliMetrics.videoAspect));
      expect(page.host.drawnTurns, [1, id]);
      await page.leave(tester);
    });
  });

  testWidgets('the build before the turn, as before: a turn of no length is drawn over 300 ms', (tester) async {
    final page = TurnPage();
    await page.open(tester);
    final id = await page.turnToLandscape(tester, duration: Duration.zero);
    expect(lines('started').single.f['outcome'], const LogString('pending'));
    await expectOfficialTurn(tester, from: -pi / 2);
    expect(tester.getRect(TurnPage.area), fullBox);
    expect(page.host.drawnTurns, [id]);
    await page.leave(tester);
  });

  testWidgets('a turn the page did not ask for is still not drawn, only reported drawn', (tester) async {
    final page = TurnPage();
    await page.open(tester);
    final id = page.host.startTurn(pi / 2, duration: Duration.zero);
    expect(lines('started').single.f['outcome'], const LogString('unasked'));
    await tester.pump();
    expect(TurnPage.angle(tester), 0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(page.host.drawnTurns, [id]);
    expect(tester.getRect(TurnPage.box), smallBox);
    await page.leave(tester);
  });

  testWidgets('a covered page, which no longer owns the orientation, ignores the turn', (tester) async {
    final page = TurnPage();
    await page.open(tester);
    await page.cover(tester);
    page.orientation.enterLandscape();
    page.host.startTurn(pi / 2, duration: Duration.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(lines('started'), isEmpty);
    expect(lines('presentation'), isEmpty);
    expect(page.host.drawnTurns, isEmpty, reason: "another page's to draw");
    await page.uncover(tester);
    expect(TurnPage.angle(tester), 0);
    await page.leave(tester);
  });

  testWidgets('with Reduce Motion the turn jumps and is reported drawn', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final page = TurnPage();
    await page.open(tester);
    page.orientation.enterLandscape();
    final id = page.host.startTurn(pi / 2, duration: Duration.zero);
    page.screen(tester, landscape);
    await tester.pump();
    expect(TurnPage.angle(tester), 0);
    expect(tester.getRect(TurnPage.area), fullBox);
    expect(lines('began'), isEmpty);
    await tester.pump(const Duration(milliseconds: 16));
    expect(page.host.drawnTurns, [id]);
    await page.leave(tester);
  });
}
