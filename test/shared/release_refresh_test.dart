import 'dart:async';

import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/release_refresh.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// What's above the list, as a page's bar is.
const _bar = 100.0;

/// A frame at 60 Hz, and how far a finger at about 1500 px/s moves in one.
const _frame = Duration(microseconds: 16667);
const _step = 25.0;

void main() {
  late List<Completer<void>> refreshes;
  late List<RefreshIndicatorMode> modes;

  /// What the list heard: each refresh, and with [show]'s `early` each arming and disarming.
  late List<String> heard;

  /// The list under the bar; [around] puts something over or around it.
  Future<void> show(
    WidgetTester tester, {
    int rows = 30,
    Widget Function(Widget list)? around,
    bool early = false,
  }) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    refreshes = [];
    modes = [];
    heard = [];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(440, 956)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              const SizedBox(key: ValueKey('bar'), height: _bar),
              Expanded(
                child: (around ?? (list) => list)(
                  CustomScrollView(
                    key: const ValueKey('list'),
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      ReleaseRefreshControl(
                        onArmed: early ? () => heard.add('armed') : null,
                        onDisarmed: early ? () => heard.add('disarmed') : null,
                        onRefresh: () {
                          heard.add('refresh');
                          final refresh = Completer<void>();
                          refreshes.add(refresh);
                          return refresh.future;
                        },
                        builder: (context, mode, pulled, trigger, extent) {
                          if (modes.lastOrNull != mode) modes.add(mode);
                          return loadingTvRefreshIndicator(context, mode, pulled, trigger, extent);
                        },
                      ),
                      SliverList.builder(
                        itemCount: rows,
                        itemBuilder: (context, index) => SizedBox(key: ValueKey('row-$index'), height: 80),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double pulled(WidgetTester tester) =>
      -tester.state<ScrollableState>(find.byType(Scrollable, skipOffstage: false)).position.pixels;
  double firstRowTop(WidgetTester tester) => tester.getTopLeft(find.byKey(const ValueKey('row-0'))).dy;
  bool playing(WidgetTester tester) => tester.widget<LoadingTv>(find.byType(LoadingTv)).playing;

  /// Moves [finger] by [dy] at about 1500 px/s, a frame at a time.
  Future<void> drag(WidgetTester tester, TestGesture finger, double dy) async {
    final steps = (dy.abs() / _step).ceil();
    for (var i = 0; i < steps; i++) {
      await finger.moveBy(Offset(0, dy / steps));
      await tester.pump(_frame);
    }
  }

  Future<TestGesture> pullDown(WidgetTester tester, double dy) async {
    final finger = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('list'))));
    await drag(tester, finger, dy);
    return finger;
  }

  Future<void> wait(WidgetTester tester, [Duration time = const Duration(seconds: 1)]) async {
    for (var waited = Duration.zero; waited < time; waited += const Duration(milliseconds: 50)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Ends the refreshes still running and lets the gap close, so no TV is left cycling.
  Future<void> finish(WidgetTester tester) async {
    for (final refresh in refreshes) {
      if (!refresh.isCompleted) refresh.complete();
    }
    await wait(tester);
    expect(find.byType(LoadingTv), findsNothing);
    expect(firstRowTop(tester), _bar);
  }

  testWidgets('held past the trigger it arms but refreshes nothing until the finger lifts', (tester) async {
    await show(tester);
    final finger = await pullDown(tester, 300);
    expect(pulled(tester), greaterThan(100));
    expect(modes.last, RefreshIndicatorMode.armed);
    await wait(tester, const Duration(seconds: 2));
    expect(refreshes, isEmpty, reason: 'held for 2 s past the trigger');
    expect(modes.last, RefreshIndicatorMode.armed);
    await finger.up();
    expect(refreshes, hasLength(1), reason: 'as the finger lifts');
    await wait(tester);
    expect(refreshes, hasLength(1));
    await finish(tester);
  });

  testWidgets('released past the trigger it refreshes once, holding the gap until done, then closes', (tester) async {
    await show(tester);
    final finger = await pullDown(tester, 300);
    await finger.up();
    await wait(tester);
    expect(refreshes, hasLength(1));
    expect(modes.last, RefreshIndicatorMode.refresh);
    expect(firstRowTop(tester), _bar + LoadingTvTheme.size, reason: 'the gap holds the TV');
    final tv = tester.getRect(find.byType(LoadingTv));
    expect((tv.top, tv.height, tv.center.dx), (_bar, LoadingTvTheme.size, 220));
    expect(playing(tester), isTrue);
    await wait(tester, const Duration(seconds: 3));
    expect(firstRowTop(tester), _bar + LoadingTvTheme.size, reason: 'still refreshing');

    refreshes.single.complete();
    await tester.pump();
    await wait(tester);
    expect(refreshes, hasLength(1));
    expect(
      modes,
      containsAllInOrder(const [
        RefreshIndicatorMode.drag,
        RefreshIndicatorMode.armed,
        RefreshIndicatorMode.refresh,
        RefreshIndicatorMode.done,
      ]),
    );
    await finish(tester);
  });

  testWidgets('pulled past the trigger and back under before lifting, nothing happens', (tester) async {
    await show(tester);
    final finger = await pullDown(tester, 300);
    expect(modes.last, RefreshIndicatorMode.armed);
    await drag(tester, finger, -150);
    expect(pulled(tester), inExclusiveRange(0, 100));
    expect(modes.last, RefreshIndicatorMode.drag);
    expect(playing(tester), isFalse, reason: 'back on the first face');
    await finger.up();
    await wait(tester);
    expect(refreshes, isEmpty);
    expect(pulled(tester), 0);
    expect(find.byType(LoadingTv), findsNothing);
  });

  testWidgets('back under the trigger and lifted within one frame, nothing happens', (tester) async {
    await show(tester);
    final finger = await pullDown(tester, 300);
    expect(modes.last, RefreshIndicatorMode.armed);
    await finger.moveBy(const Offset(0, -150));
    await finger.up();
    await wait(tester);
    expect(refreshes, isEmpty);
    expect(find.byType(LoadingTv), findsNothing);
  });

  testWidgets('a pull while it refreshes starts no other; once closed the next pull does', (tester) async {
    await show(tester);
    var finger = await pullDown(tester, 300);
    await finger.up();
    await wait(tester);
    expect(refreshes, hasLength(1));

    finger = await pullDown(tester, 300);
    expect(modes.last, RefreshIndicatorMode.refresh);
    await finger.up();
    await wait(tester);
    expect(refreshes, hasLength(1));
    expect(firstRowTop(tester), _bar + LoadingTvTheme.size);

    // Still pulled as it ends: lifting then starts nothing either.
    finger = await pullDown(tester, 300);
    refreshes.single.complete();
    await wait(tester);
    expect(modes.last, RefreshIndicatorMode.done);
    await finger.up();
    await wait(tester);
    expect(refreshes, hasLength(1));
    await finish(tester);

    finger = await pullDown(tester, 300);
    await finger.up();
    expect(refreshes, hasLength(2));
    await finish(tester);
  });

  testWidgets('the TV holds its first face short of the trigger and plays once armed and while refreshing', (
    tester,
  ) async {
    await show(tester);
    final finger = await pullDown(tester, 75);
    expect(pulled(tester), inExclusiveRange(0, 100));
    expect(modes.last, RefreshIndicatorMode.drag);
    expect(playing(tester), isFalse);
    expect(tester.getRect(find.byType(LoadingTv)).bottom, firstRowTop(tester), reason: 'just above the rows');
    expect(tester.getRect(find.byType(LoadingTv)).top, lessThan(_bar), reason: 'coming out from under the bar');
    await drag(tester, finger, 225);
    expect(modes.last, RefreshIndicatorMode.armed);
    expect(playing(tester), isTrue);
    await finger.up();
    await wait(tester);
    expect(playing(tester), isTrue);
    await finish(tester);
  });

  testWidgets('a short list and an empty one refresh on release too', (tester) async {
    for (final rows in [2, 0]) {
      await show(tester, rows: rows);
      final finger = await pullDown(tester, 300);
      await wait(tester);
      expect(refreshes, isEmpty, reason: '$rows rows, held');
      await finger.up();
      await wait(tester);
      expect(refreshes, hasLength(1), reason: '$rows rows');
      if (rows > 0) expect(firstRowTop(tester), _bar + LoadingTvTheme.size);
      for (final refresh in refreshes) {
        refresh.complete();
      }
      await wait(tester);
      expect(find.byType(LoadingTv), findsNothing);
      expect(pulled(tester), 0);
    }
  });

  testWidgets('a bounce past the trigger with no finger arms nothing', (tester) async {
    await show(tester);
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(-150);
    await tester.pump();
    expect(modes.last, RefreshIndicatorMode.drag);
    await wait(tester);
    expect(refreshes, isEmpty);
    expect(pulled(tester), 0);
  });

  testWidgets('a finger resting outside the list does not hold back the release', (tester) async {
    await show(tester);
    final elsewhere = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('bar'))));
    final finger = await pullDown(tester, 300);
    await finger.up();
    expect(refreshes, hasLength(1));
    await elsewhere.up();
    expect(refreshes, hasLength(1));
    await finish(tester);
  });

  testWidgets('a touch the system cancels refreshes nothing', (tester) async {
    await show(tester);
    final finger = await pullDown(tester, 300);
    expect(modes.last, RefreshIndicatorMode.armed);
    await finger.cancel();
    await wait(tester);
    expect(refreshes, isEmpty);
    expect(find.byType(LoadingTv), findsNothing);
  });

  group('told early', () {
    testWidgets('held past the trigger it says armed once; the release refreshes with no disarm', (tester) async {
      await show(tester, early: true);
      final finger = await pullDown(tester, 300);
      await wait(tester);
      expect(heard, ['armed']);
      await finger.up();
      await wait(tester);
      expect(heard, ['armed', 'refresh']);
      await finish(tester);
      expect(heard, ['armed', 'refresh']);
    });

    testWidgets('short of the trigger it says nothing', (tester) async {
      await show(tester, early: true);
      final finger = await pullDown(tester, 75);
      await finger.up();
      await wait(tester);
      expect(heard, isEmpty);
    });

    testWidgets('back under the trigger with the finger down it disarms, armed again past it, and lifted under it '
        'nothing more', (tester) async {
      await show(tester, early: true);
      final finger = await pullDown(tester, 300);
      await drag(tester, finger, -150);
      await tester.pump();
      expect(heard, ['armed', 'disarmed']);
      await drag(tester, finger, 150);
      await tester.pump();
      expect(heard, ['armed', 'disarmed', 'armed']);
      await drag(tester, finger, -150);
      await finger.up();
      await wait(tester);
      expect(heard, ['armed', 'disarmed', 'armed', 'disarmed']);
      expect(refreshes, isEmpty);
    });

    testWidgets('back under and lifted within one frame it disarms', (tester) async {
      await show(tester, early: true);
      final finger = await pullDown(tester, 300);
      await finger.moveBy(const Offset(0, -150));
      await finger.up();
      await wait(tester);
      expect(heard, ['armed', 'disarmed']);
      expect(refreshes, isEmpty);
    });

    testWidgets('a touch the system cancels disarms', (tester) async {
      await show(tester, early: true);
      final finger = await pullDown(tester, 300);
      await finger.cancel();
      await wait(tester);
      expect(heard, ['armed', 'disarmed']);
    });

    testWidgets('the list going while armed disarms', (tester) async {
      await show(tester, early: true);
      final finger = await pullDown(tester, 300);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(heard, ['armed', 'disarmed']);
      await finger.up();
    });

    testWidgets('a bounce past the trigger with no finger says nothing', (tester) async {
      await show(tester, early: true);
      tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(-150);
      await tester.pump();
      await wait(tester);
      expect(heard, isEmpty);
    });

    testWidgets('a pull while it refreshes says nothing', (tester) async {
      await show(tester, early: true);
      var finger = await pullDown(tester, 300);
      await finger.up();
      await wait(tester);
      finger = await pullDown(tester, 300);
      await finger.up();
      await wait(tester);
      expect(heard, ['armed', 'refresh']);
      await finish(tester);
    });
  });

  /// Leaves the list bouncing back from 150 pt past its top, with no finger on it.
  Future<void> bounce(WidgetTester tester) async {
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(-150);
    await tester.pump();
    expect(pulled(tester), greaterThan(100));
  }

  testWidgets('a touch on a sheet over the list is not a finger on the list', (tester) async {
    await show(
      tester,
      around: (list) => Stack(
        children: [
          list,
          Positioned.fill(
            child: GestureDetector(key: const ValueKey('sheet'), behavior: HitTestBehavior.opaque, onTap: () {}),
          ),
        ],
      ),
    );
    await bounce(tester);
    final finger = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('sheet'))));
    await tester.pump();
    expect(modes.last, RefreshIndicatorMode.drag, reason: 'armed by nothing');
    await finger.up();
    await wait(tester);
    expect(refreshes, isEmpty);
    expect(pulled(tester), 0);
  });

  testWidgets('a list hidden in an IndexedStack takes no finger from the page over it', (tester) async {
    var hidden = false;
    late StateSetter setHidden;
    await show(
      tester,
      around: (list) => StatefulBuilder(
        builder: (context, setState) {
          setHidden = setState;
          return IndexedStack(
            index: hidden ? 1 : 0,
            sizing: StackFit.expand,
            children: [
              TickerMode(enabled: !hidden, child: list),
              const ColoredBox(key: ValueKey('other'), color: Color(0xFFFFFFFF)),
            ],
          );
        },
      ),
    );
    await bounce(tester);
    setHidden(() => hidden = true);
    await tester.pump();
    final frozen = pulled(tester);
    expect(frozen, greaterThan(100), reason: 'its bounce stopped with its ticker');
    final finger = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('other'))));
    await wait(tester, const Duration(milliseconds: 200));
    await finger.up();
    await wait(tester);
    expect(refreshes, isEmpty);
    expect(pulled(tester), frozen);
    expect(modes.last, RefreshIndicatorMode.drag);

    setHidden(() => hidden = false);
    await wait(tester);
    expect(refreshes, isEmpty, reason: 'shown again, it settles without refreshing');
    expect(pulled(tester), 0);
  });

  testWidgets('a list whose tickers are off takes no finger, even where it shows', (tester) async {
    await show(tester, around: (list) => TickerMode(enabled: false, child: list));
    await bounce(tester);
    final finger = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('list'))));
    await finger.up();
    await wait(tester);
    expect(refreshes, isEmpty);
  });
}
