import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/follow_tab/follow_top.dart';
import 'package:bilifast/shared/paced_gif.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Made up: two live faces, then ten others, more than the row's width.
const _live = [
  DynamicLiveUp(mid: 201, name: '晚星直播', face: '', roomId: 30001),
  DynamicLiveUp(mid: 202, name: '月下直播', face: '', roomId: 30002),
];
final _ups = [for (var i = 0; i < 10; i++) DynamicUp(mid: 300 + i, name: '演示$i', face: '')];

/// The live pill's moving bars of [mid]: does its gif take frames?
bool _ticking(WidgetTester tester, int mid) => TickerMode.valuesOf(
  tester.element(
    find.descendant(
      of: find.byKey(ValueKey('follow-live-pill-$mid'), skipOffstage: false),
      matching: find.byType(PacedGif, skipOffstage: false),
    ),
  ),
).enabled;

/// The check runs after the frame that moved it; its TickerMode lands in the next.
Future<void> _moved(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  late ScrollController page;
  late ScrollController faces;

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    page = ScrollController();
    faces = ScrollController();
    addTearDown(page.dispose);
    addTearDown(faces.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: page,
          slivers: [
            SliverToBoxAdapter(
              child: FollowTop(
                type: DynamicFeedType.all,
                ups: _ups,
                liveUps: _live,
                dot: (up) => up.hasUpdate,
                onSelect: (_) {},
                onOpenFace: (_) {},
                onMore: () {},
                onNearEnd: () {},
                facesController: faces,
                facesKey: GlobalKey(),
              ),
            ),
            SliverList.builder(itemCount: 40, itemBuilder: (context, index) => const SizedBox(height: 120)),
          ],
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the 直播中 pills stop once 关注\'s top is scrolled away, and move again when it is back', (tester) async {
    await show(tester);
    expect(_ticking(tester, 201), isTrue);
    expect(_ticking(tester, 202), isTrue);

    page.jumpTo(DynamicFeedTheme.top + 400);
    await _moved(tester);
    expect(_ticking(tester, 201), isFalse);
    expect(_ticking(tester, 202), isFalse);

    // The bars sit 82 + 26 + 21 - 8 down the top: 100 up, they still show at the screen's top.
    page.jumpTo(100);
    await _moved(tester);
    expect(_ticking(tester, 201), isTrue);
  });

  testWidgets('a pill scrolled sideways out of the faces row stops; the one still in it keeps moving', (tester) async {
    await show(tester);
    // The first live slot is 8 + 74 wide: past it, only the second pill shows.
    faces.jumpTo(DynamicFeedTheme.facesInset + DynamicFeedTheme.facePitch + 1);
    await _moved(tester);
    expect(_ticking(tester, 201), isFalse);
    expect(_ticking(tester, 202), isTrue);

    faces.jumpTo(0);
    await _moved(tester);
    expect(_ticking(tester, 201), isTrue);
  });
}
