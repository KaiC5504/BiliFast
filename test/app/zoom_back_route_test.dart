import 'dart:async';

import 'package:bilifast/app/zoom_back_route.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Swipes are dragged at about a thumb's speed (1500 px/s). The screen is KaiC's iPhone, 440×956.
void main() {
  const screen = Size(440, 956);
  const cardKey = ValueKey('card');
  const pageKey = ValueKey('page');
  const cardRect = Rect.fromLTWH(14, 300, 200, 240);

  late int flights;
  late Future<void> opened;

  Widget countFlights(BuildContext _, Animation<double> _, HeroFlightDirection _, BuildContext _, BuildContext to) {
    flights++;
    return (to.widget as Hero).child;
  }

  Widget page({bool canPop = true}) => PopScope(
    canPop: canPop,
    child: Scaffold(
      key: pageKey,
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Hero(
            tag: 'cover',
            flightShuttleBuilder: countFlights,
            child: const ColoredBox(color: Colors.black, child: SizedBox(height: 250, width: double.infinity)),
          ),
          Builder(
            builder: (context) => TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('〈')),
          ),
          const Text('视频页'),
        ],
      ),
    ),
  );

  /// Home with one card at [cardRect]; opens the page from it unless [source] stands in for the card's own.
  Future<void> open(WidgetTester tester, {bool canPop = true, ZoomSource? source, bool still = false}) async {
    flights = 0;
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => still
            ? MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!)
            : child!,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fromRect(
                rect: cardRect,
                child: ZoomSourceBox(
                  builder: (context, own) => GestureDetector(
                    onTap: () => opened = Navigator.of(
                      context,
                    ).push(ZoomBackPageRoute<void>(builder: (_) => page(canPop: canPop), source: source ?? own)),
                    child: Hero(
                      tag: 'cover',
                      flightShuttleBuilder: countFlights,
                      child: const ColoredBox(key: cardKey, color: Colors.blue),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(cardKey));
    await tester.pumpAndSettle();
    expect(find.text('视频页'), findsOneWidget);
    expect(flights, 1, reason: 'the cover flew in from the card');
  }

  Rect pageRect(WidgetTester tester) => tester.getRect(find.byKey(pageKey));

  void expectRect(Rect actual, Rect expected, {String? reason}) {
    for (final (a, e) in [
      (actual.left, expected.left),
      (actual.top, expected.top),
      (actual.width, expected.width),
      (actual.height, expected.height),
    ]) {
      expect(a, closeTo(e, 0.5), reason: '$actual against $expected${reason == null ? '' : ': $reason'}');
    }
  }

  double cardOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.byKey(cardKey, skipOffstage: false), matching: find.byType(Opacity, skipOffstage: false))
            .first,
      )
      .opacity;

  Future<void> expectHome(WidgetTester tester) async {
    expect(find.text('视频页'), findsNothing);
    expect(cardOpacity(tester), 1, reason: 'the card is back');
    var done = false;
    unawaited(opened.then((_) => done = true));
    await tester.pump();
    expect(done, isTrue, reason: 'the route popped');
  }

  /// Drags from the left edge in 16 ms steps, ending where [to] is from the touch down.
  Future<TestGesture> dragOut(WidgetTester tester, Offset to, {Offset from = const Offset(5, 478)}) async {
    final gesture = await tester.startGesture(from);
    const steps = 10;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(from + to * (i / steps), timeStamp: Duration(milliseconds: 16 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  group('the drag', () {
    test('the scale falls slowly to 0.8, quickly to 0.6, then holds', () {
      expect(ZoomBackPageRoute.scaleFor(0, 440), 1);
      expect(ZoomBackPageRoute.scaleFor(80, 440), closeTo(0.90, 0.01));
      expect(ZoomBackPageRoute.scaleFor(161, 440), closeTo(0.80, 0.01));
      expect(ZoomBackPageRoute.scaleFor(187, 440), closeTo(0.69, 0.01));
      expect(ZoomBackPageRoute.scaleFor(210, 440), closeTo(ZoomBackTheme.minScale, 0.01));
      expect(ZoomBackPageRoute.scaleFor(400, 440), ZoomBackTheme.minScale);
    });

    testWidgets('starts only from the left edge', (tester) async {
      await open(tester);
      await tester.timedDragFrom(const Offset(200, 478), const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('视频页'), findsOneWidget);
      expectRect(pageRect(tester), Offset.zero & screen);

      await tester.timedDragFrom(const Offset(5, 478), const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await expectHome(tester);
    });

    testWidgets('the page shrinks as the finger moves right, follows it up and down, and grows back', (tester) async {
      await open(tester);
      final gesture = await dragOut(tester, const Offset(100, 0));
      expectRect(pageRect(tester), ZoomBackPageRoute.rectFor(const Offset(100, 0), screen));
      expect(pageRect(tester).width, closeTo(440 * ZoomBackPageRoute.scaleFor(100, 440), 0.5));

      await gesture.moveBy(const Offset(200, -120), timeStamp: const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 16));
      final far = pageRect(tester);
      expect(far.width, closeTo(440 * ZoomBackTheme.minScale, 0.5));
      expect(far.left, closeTo(300, 0.5));
      expect(far.center.dy, closeTo(478 - 120, 0.5));

      await gesture.moveBy(const Offset(-280, 120), timeStamp: const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 16));
      expectRect(pageRect(tester), ZoomBackPageRoute.rectFor(const Offset(20, 0), screen), reason: 'back out again');
      await gesture.up(timeStamp: const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();
    });

    testWidgets('home sits still under the dim while the page is shrunk', (tester) async {
      await open(tester);
      final gesture = await dragOut(tester, const Offset(100, 0));
      expect(tester.getRect(find.byKey(cardKey)), cardRect, reason: 'not slid aside as under a pushed page');
      final scale = ZoomBackPageRoute.scaleFor(100, 440);
      final dim = Color.lerp(ZoomBackTheme.dim, ZoomBackTheme.dimShrunk, (1 - scale) / (1 - ZoomBackTheme.minScale))!;
      final colours = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).map((box) => box.color);
      expect(colours.where((colour) => colour.r == 0 && (colour.a - dim.a).abs() < 0.001), hasLength(1));
      await gesture.up(timeStamp: const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();
    });

    testWidgets('let go early, it springs back to full screen', (tester) async {
      await open(tester);
      final gesture = await dragOut(tester, const Offset(200, 60));
      // Back towards the edge at 1500 px/s, so the release is heading left.
      for (var i = 1; i <= 5; i++) {
        await gesture.moveBy(const Offset(-24, -12), timeStamp: Duration(milliseconds: 160 + 16 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up(timeStamp: const Duration(milliseconds: 256));
      await tester.pump(ZoomBackTheme.settle ~/ 2);
      final halfway = pageRect(tester);
      expect(halfway.width, inExclusiveRange(440 * 0.8, 440));
      await tester.pumpAndSettle();
      expect(find.text('视频页'), findsOneWidget);
      expectRect(pageRect(tester), Offset.zero & screen);
      expect(cardOpacity(tester), 1);
      expect(tester.state<NavigatorState>(find.byType(Navigator)).userGestureInProgress, isFalse);

      // Still interactive afterwards.
      await tester.timedDragFrom(const Offset(5, 478), const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await expectHome(tester);
    });

    testWidgets('a page that cannot pop (full screen, an open panel) does not start it', (tester) async {
      await open(tester, canPop: false);
      final gesture = await dragOut(tester, const Offset(200, 0));
      expectRect(pageRect(tester), Offset.zero & screen);
      await gesture.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('视频页'), findsOneWidget);
    });
  });

  group('letting go', () {
    testWidgets('flies into the card it came from, then pops with no second animation', (tester) async {
      await open(tester);
      final gesture = await dragOut(tester, const Offset(250, 0));
      final released = pageRect(tester);
      await gesture.up(timeStamp: const Duration(milliseconds: 176));
      await tester.pump();
      expect(cardOpacity(tester), 0, reason: 'the card stays empty while the page is away');

      await tester.pump(ZoomBackTheme.fly ~/ 2);
      final midway = pageRect(tester);
      expect(find.byType(RawImage), findsOneWidget, reason: "the page has turned into the card's picture");
      expect(midway.left, inExclusiveRange(cardRect.left, released.left));
      expect(midway.width, inExclusiveRange(cardRect.width, released.width));

      await tester.pump(ZoomBackTheme.fly ~/ 2 - const Duration(milliseconds: 1));
      expect(pageRect(tester).topLeft.dx, closeTo(cardRect.left, 1));
      expect(pageRect(tester).topLeft.dy, closeTo(cardRect.top, 1));
      expect(pageRect(tester).width, closeTo(cardRect.width, 1));

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 16));
      await expectHome(tester);
      expect(flights, 1, reason: 'the cover never flew back on its own');
    });

    testWidgets('the cover Hero does not fly while dragging or landing', (tester) async {
      await open(tester);
      final gesture = await dragOut(tester, const Offset(120, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(flights, 1);
      await gesture.moveBy(const Offset(150, 0), timeStamp: const Duration(milliseconds: 260));
      await gesture.up(timeStamp: const Duration(milliseconds: 270));
      await tester.pumpAndSettle();
      await expectHome(tester);
      expect(flights, 1);
    });

    testWidgets('with the card gone, the page shrinks towards the middle as it fades', (tester) async {
      await open(tester, source: () => null);
      await tester.timedDragFrom(const Offset(5, 478), const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pump(ZoomBackTheme.fly * 0.9);
      final page = pageRect(tester);
      expect(page.center.dx, closeTo(220, 40));
      expect(page.width, lessThan(440 * ZoomBackTheme.minScale));
      final fading = tester.widget<Opacity>(
        find.ancestor(of: find.byKey(pageKey), matching: find.byType(Opacity)).first,
      );
      expect(fading.opacity, lessThan(0.2));
      await tester.pumpAndSettle();
      await expectHome(tester);
    });

    testWidgets('with Reduce Motion, the drag still follows the finger and the page fades where it is', (tester) async {
      await open(tester, still: true);
      final gesture = await dragOut(tester, const Offset(250, 0));
      final released = pageRect(tester);
      expect(released.width, closeTo(440 * ZoomBackTheme.minScale, 0.5));
      await gesture.up(timeStamp: const Duration(milliseconds: 176));
      await tester.pump();
      await tester.pump(ZoomBackTheme.fade ~/ 2);
      expectRect(pageRect(tester), released, reason: 'no fly');
      final fading = tester.widget<Opacity>(
        find.ancestor(of: find.byKey(pageKey), matching: find.byType(Opacity)).first,
      );
      expect(fading.opacity, closeTo(0.5, 0.05));
      await tester.pump(ZoomBackTheme.fade ~/ 2 + const Duration(milliseconds: 16));
      await expectHome(tester);
    });
  });

  group('back by the button', () {
    testWidgets('flies the full page into the card, with no Hero flight', (tester) async {
      await open(tester);
      await tester.tap(find.text('〈'));
      await tester.pump();
      await tester.pump();
      expect(cardOpacity(tester), 0);
      await tester.pump(ZoomBackTheme.flyFromFull ~/ 2);
      final midway = pageRect(tester);
      expect(midway.left, inExclusiveRange(0, cardRect.left));
      expect(midway.width, inExclusiveRange(cardRect.width, 440));
      await tester.pumpAndSettle();
      await expectHome(tester);
      expect(flights, 1);
    });

    testWidgets('with Reduce Motion, the page fades over the card as it is', (tester) async {
      await open(tester, still: true);
      await tester.tap(find.text('〈'));
      await tester.pump();
      await tester.pump(ZoomBackTheme.fade ~/ 2);
      expectRect(pageRect(tester), Offset.zero & screen);
      expect(cardOpacity(tester), 1);
      await tester.pump(ZoomBackTheme.fade ~/ 2 + const Duration(milliseconds: 16));
      await expectHome(tester);
      expect(flights, 1);
    });

    testWidgets('popped mid-drag, the page flies from where it is and the gesture ends', (tester) async {
      await open(tester);
      final gesture = await dragOut(tester, const Offset(60, 0));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.userGestureInProgress, isTrue);
      navigator.pop();
      await tester.pump();
      expect(pageRect(tester).width, lessThan(440), reason: 'not snapped back to full size first');
      await gesture.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await expectHome(tester);
      expect(navigator.userGestureInProgress, isFalse);
      expect(flights, 1);
    });

    testWidgets('with the card gone, it is the plain slide', (tester) async {
      await open(tester, source: () => null);
      await tester.tap(find.text('〈'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final page = pageRect(tester);
      expect(page.width, closeTo(440, 0.01), reason: 'not shrunk');
      expect(page.left, greaterThan(0), reason: 'sliding off to the right');
      await tester.pumpAndSettle();
      expect(find.text('视频页'), findsNothing);
    });
  });

  group('ZoomSourceBox', () {
    testWidgets("gives its card's global rect, and null once off screen or gone", (tester) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late ZoomSource source;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 100),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    children: [
                      const SizedBox(height: 50),
                      ZoomSourceBox(
                        builder: (context, own) {
                          source = own;
                          return const SizedBox(key: cardKey, height: 200);
                        },
                      ),
                      const SizedBox(height: 3000),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(source(), const Rect.fromLTWH(0, 150, 440, 200));
      scroll.jumpTo(240);
      await tester.pump();
      expect(source(), const Rect.fromLTWH(0, -90, 440, 200), reason: 'still showing at the top');
      scroll.jumpTo(260);
      await tester.pump();
      expect(source(), isNull, reason: 'scrolled up under the header');
      scroll.jumpTo(2000);
      await tester.pump();
      expect(source(), isNull, reason: 'recycled by the list');
    });
  });
}
