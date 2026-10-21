import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool still = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: still),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

int _face(WidgetTester tester) {
  for (var face = 0; face < LoadingTv.frames.length; face++) {
    if (find.byKey(ValueKey('loading-tv-$face')).evaluate().isNotEmpty) return face;
  }
  fail('no face drawn');
}

void main() {
  testWidgets('cycles its four faces, one per frame time', (tester) async {
    await tester.pumpWidget(_host(const LoadingTv()));
    final seen = <int>[_face(tester)];
    for (var step = 0; step < 4; step++) {
      await tester.pump(LoadingTvTheme.frame);
      seen.add(_face(tester));
    }
    expect(seen, [0, 1, 2, 3, 0]);
    expect(tester.getSize(find.byType(Image)), const Size.square(LoadingTvTheme.size));
  });

  testWidgets('Reduce Motion holds the first face', (tester) async {
    await tester.pumpWidget(_host(const LoadingTv(), still: true));
    await tester.pump(LoadingTvTheme.frame * 2);
    expect(_face(tester), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a held TV shows its first face and starts when played', (tester) async {
    await tester.pumpWidget(_host(const LoadingTv(playing: false)));
    await tester.pump(LoadingTvTheme.frame * 2);
    expect(_face(tester), 0);
    await tester.pumpWidget(_host(const LoadingTv()));
    await tester.pump(LoadingTvTheme.frame);
    expect(_face(tester), 1);
  });

  testWidgets('a muted ticker stops it', (tester) async {
    await tester.pumpWidget(_host(const TickerMode(enabled: false, child: LoadingTv())));
    await tester.pump(LoadingTvTheme.frame * 2);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the first-load state reads 正在努力加载...', (tester) async {
    await tester.pumpWidget(_host(const LoadingTvState()));
    expect(find.text(LoadingTvState.message), findsOneWidget);
    expect(find.byType(LoadingTv), findsOneWidget);
  });

  testWidgets('the refresh indicator holds while dragged and cycles while refreshing', (tester) async {
    Widget indicator(RefreshIndicatorMode mode, double pulled) => _host(
      SizedBox(
        width: 100,
        height: pulled,
        child: Builder(builder: (context) => loadingTvRefreshIndicator(context, mode, pulled, 100, 60)),
      ),
    );
    await tester.pumpWidget(indicator(RefreshIndicatorMode.inactive, 0));
    expect(find.byType(LoadingTv), findsNothing);
    await tester.pumpWidget(indicator(RefreshIndicatorMode.drag, 30));
    await tester.pump(LoadingTvTheme.frame * 2);
    expect(_face(tester), 0);
    await tester.pumpWidget(indicator(RefreshIndicatorMode.refresh, 60));
    await tester.pump(LoadingTvTheme.frame);
    expect(_face(tester), 1);
  });
}
