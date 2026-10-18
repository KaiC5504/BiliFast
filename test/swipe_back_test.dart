import 'package:bilifast/app/swipe_back_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Swipes are dragged at about a thumb's speed (1500 px/s), not XCTest's slow `.fast`.
void main() {
  Future<void> push(WidgetTester tester, Widget page, String shown) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => page)),
              child: const Text('首页'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text(shown), findsOneWidget);
  }

  Future<void> pushDetail(WidgetTester tester) => push(
    tester,
    Scaffold(body: ListView(children: [for (var i = 0; i < 30; i++) ListTile(title: Text('评论 $i'))])),
    '评论 0',
  );

  // The video page when its titles are too short to scroll: nothing below the player has a drag recogniser, and the
  // player's tap and double tap give up after the touch slop.
  const playerPoint = Offset(400, 60);
  const titlesPoint = Offset(400, 300);
  Future<void> pushShortPage(WidgetTester tester) => push(
    tester,
    Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () {},
            onDoubleTap: () {},
            child: const ColoredBox(color: Colors.black, child: SizedBox(height: 250)),
          ),
          const Expanded(child: Column(children: [Text('标题'), Text('UP主')])),
        ],
      ),
    ),
    '标题',
  );

  void expectBack(WidgetTester tester) {
    expect(find.text('标题'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  }

  testWidgets('a swipe from the left edge goes back', (tester) async {
    await pushDetail(tester);
    await tester.timedDragFrom(const Offset(5, 300), const Offset(300, 0), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('评论 0'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a swipe from the middle of the content does not go back', (tester) async {
    await pushDetail(tester);
    await tester.timedDragFrom(const Offset(300, 300), const Offset(300, 0), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('评论 0'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a short slow swipe springs back', (tester) async {
    await pushDetail(tester);
    await tester.timedDragFrom(const Offset(5, 300), const Offset(120, 0), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('评论 0'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a leftward drag and a vertical scroll do not go back', (tester) async {
    await pushDetail(tester);
    await tester.timedDragFrom(const Offset(500, 300), const Offset(-300, 0), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.timedDragFrom(const Offset(300, 500), const Offset(0, -300), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a vertical drag with a small sideways wobble does not move the page', (tester) async {
    await pushShortPage(tester);
    for (final start in [playerPoint, titlesPoint]) {
      final resting = tester.getTopLeft(find.text('标题'));
      final gesture = await tester.startGesture(start);
      // Drifts 30 px right over 300 px down: past the slop sideways, but far more down than across.
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(Offset(i.isEven ? 7 : -2, 25), timeStamp: Duration(milliseconds: 16 * (i + 1)));
        await tester.pump();
        expect(tester.getTopLeft(find.text('标题')), resting, reason: 'from $start, move $i');
      }
      await gesture.up(timeStamp: const Duration(milliseconds: 16 * 13));
      await tester.pumpAndSettle();
      expect(find.text('标题'), findsOneWidget);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a mostly vertical flick down and to the right does not go back', (tester) async {
    await pushShortPage(tester);
    // 1000 px/s sideways, more than a screen width a second.
    for (final start in [const Offset(200, 20), const Offset(200, 280)]) {
      await tester.timedDragFrom(start, const Offset(150, 300), const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.text('标题'), findsOneWidget, reason: 'from $start');
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a clear horizontal swipe from the middle of a short page does not go back, over the player either',
      (tester) async {
    await pushShortPage(tester);
    for (final start in [playerPoint, titlesPoint]) {
      await tester.timedDragFrom(start, const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('标题'), findsOneWidget, reason: 'from $start');
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a swipe from the left edge of a short page goes back, over the player too', (tester) async {
    for (final start in [Offset(5, playerPoint.dy), Offset(5, titlesPoint.dy)]) {
      await pushShortPage(tester);
      await tester.timedDragFrom(start, const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expectBack(tester);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a drag turned down for heading down does not stop the next swipe over a list', (tester) async {
    await push(
      tester,
      Scaffold(
        body: Column(
          children: [
            const SizedBox(height: 200),
            Expanded(child: ListView(children: [for (var i = 0; i < 30; i++) ListTile(title: Text('评论 $i'))])),
          ],
        ),
      ),
      '评论 0',
    );
    await tester.timedDragFrom(const Offset(400, 100), const Offset(40, 300), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('评论 0'), findsOneWidget);
    await tester.timedDragFrom(const Offset(5, 400), const Offset(300, 0), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('评论 0'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
