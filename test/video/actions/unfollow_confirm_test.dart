import 'package:bilifast/video/actions/unfollow_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<String>> pumpConfirm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(440, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final calls = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UnfollowConfirm(onConfirm: () => calls.add('confirm'), onCancel: () => calls.add('cancel')),
      ),
    ),
  );
  return calls;
}

void main() {
  testWidgets('asks 确定不再关注？ with 取消 and 确定, centred', (tester) async {
    await pumpConfirm(tester);
    expect(find.text('确定不再关注？'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
    expect(tester.getCenter(find.byKey(const ValueKey('unfollow-alert'))), const Offset(220, 478));
  });

  testWidgets('确定 confirms and 取消 cancels', (tester) async {
    final calls = await pumpConfirm(tester);
    await tester.tap(find.text('确定'));
    await tester.tap(find.text('取消'));
    expect(calls, ['confirm', 'cancel']);
  });

  testWidgets('a tap on the dim outside the alert cancels; one on the alert does nothing', (tester) async {
    final calls = await pumpConfirm(tester);
    await tester.tapAt(const Offset(220, 120));
    expect(calls, ['cancel']);
    await tester.tap(find.text('确定不再关注？'));
    expect(calls, ['cancel']);
  });

  testWidgets('both buttons answer accessibility presses', (tester) async {
    final handle = tester.ensureSemantics();
    final calls = await pumpConfirm(tester);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('unfollow-确定'))),
      matchesSemantics(label: '确定', isButton: true, hasTapAction: true),
    );
    tester.semantics.tap(find.semantics.byLabel('确定'));
    tester.semantics.tap(find.semantics.byLabel('取消').first);
    expect(calls, ['confirm', 'cancel']);
    handle.dispose();
  });

  testWidgets('it grows in and fades with the motion it is given', (tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final motion = AnimationController(vsync: const TestVSync(), value: 0);
    addTearDown(motion.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnfollowConfirm(onConfirm: () {}, onCancel: () {}, motion: motion),
      ),
    );
    double opacity() => tester
        .widget<Opacity>(
          find.ancestor(of: find.byKey(const ValueKey('unfollow-alert')), matching: find.byType(Opacity)),
        )
        .opacity;
    expect(opacity(), 0);
    motion.value = 1;
    await tester.pump();
    expect(opacity(), 1);
  });
}
