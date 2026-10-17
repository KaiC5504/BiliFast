import 'package:bili_flutter_spike/ui/swipe_back_route.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Swipes are dragged at about a thumb's speed (1500 px/s), not XCTest's slow `.fast`.
void main() {
  Future<void> pushDetail(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(SwipeBackPageRoute<void>(
                builder: (_) => Scaffold(
                  body: ListView(children: [for (var i = 0; i < 30; i++) ListTile(title: Text('评论 $i'))]),
                ),
              )),
              child: const Text('首页'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('评论 0'), findsOneWidget);
  }

  testWidgets('a swipe from the left edge goes back', (tester) async {
    await pushDetail(tester);
    await tester.timedDragFrom(const Offset(5, 300), const Offset(300, 0), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('评论 0'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a swipe from the middle of the content goes back', (tester) async {
    await pushDetail(tester);
    await tester.timedDragFrom(const Offset(300, 300), const Offset(300, 0), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('评论 0'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Flutter\'s own CupertinoPageRoute only goes back from the edge', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => const Scaffold(body: Text('详情')))),
            child: const Text('首页'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    await tester.timedDragFrom(const Offset(300, 300), const Offset(300, 0), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('详情'), findsOneWidget);
    await tester.timedDragFrom(const Offset(5, 300), const Offset(300, 0), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('详情'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a short slow swipe springs back', (tester) async {
    await pushDetail(tester);
    await tester.timedDragFrom(const Offset(300, 300), const Offset(120, 0), const Duration(milliseconds: 800));
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
}
