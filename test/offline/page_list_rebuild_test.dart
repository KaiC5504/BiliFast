import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:bilifast/offline/page/offline_page_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The offline page's list listens to the library, which ticks about once a second while anything downloads: the
/// rows are rebuilt only when the finished parts change.
void main() {
  Future<FakeOfflineLibrary> pump(WidgetTester tester) async {
    final library = FakeOfflineLibrary.demo();
    await tester.pumpWidget(
      MaterialApp(
        home: OfflinePageList(library: library, playing: null, status: null, onPlay: (_) {}, onMore: (_) {}),
      ),
    );
    return library;
  }

  Widget row(WidgetTester tester, int cid) => tester.widget(find.byKey(ValueKey('offline-row-$cid')));

  OfflineItem downloading(FakeOfflineLibrary library) =>
      library.items.firstWhere((item) => item.state == OfflineState.downloading);

  testWidgets('a progress tick leaves the rows as they were', (tester) async {
    final library = await pump(tester);
    final done = library.items.firstWhere((item) => item.isDone).cid;
    final before = row(tester, done);
    final part = downloading(library);
    library.put(part.copyWith(bytes: part.bytes + 2400000));
    await tester.pump();
    expect(identical(row(tester, done), before), isTrue);
  });

  testWidgets('a part finishing adds its row', (tester) async {
    final library = await pump(tester);
    final part = downloading(library);
    expect(find.byKey(ValueKey('offline-row-${part.cid}')), findsNothing);
    library.put(part.copyWith(state: OfflineState.done, bytes: part.totalBytes));
    await tester.pump();
    expect(find.byKey(ValueKey('offline-row-${part.cid}')), findsOneWidget);
  });
}
