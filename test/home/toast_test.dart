import 'package:bilifast/shared/toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a toast replaced by another, and the one that runs out, both release their overlay entries', (
    tester,
  ) async {
    final created = <Object>{};
    final disposed = <Object>{};
    void track(ObjectEvent event) {
      if (event.object is! OverlayEntry) return;
      if (event is ObjectCreated) created.add(event.object);
      if (event is ObjectDisposed) disposed.add(event.object);
    }

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.expand())));
    FlutterMemoryAllocations.instance.addListener(track);
    addTearDown(() => FlutterMemoryAllocations.instance.removeListener(track));

    final context = tester.element(find.byType(Scaffold));
    showToast(context, '第一条');
    await tester.pump(const Duration(milliseconds: 500));
    showToast(context, '第二条');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('toast')), findsNothing);
    expect(created, hasLength(2));
    expect(disposed, created);
  });
}
