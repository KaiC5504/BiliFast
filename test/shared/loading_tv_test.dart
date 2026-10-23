import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin_loading_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../skin/skin_loading_fixtures.dart';

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

  testWidgets('a muted ticker holds it on its first face, and it goes on when unmuted', (tester) async {
    await tester.pumpWidget(_host(const TickerMode(enabled: false, child: LoadingTv())));
    await tester.pump(LoadingTvTheme.frame * 2);
    expect(_face(tester), 0);
    await tester.pumpWidget(_host(const TickerMode(enabled: true, child: LoadingTv())));
    await tester.pump(LoadingTvTheme.frame);
    expect(_face(tester), 1);
    await tester.pumpWidget(_host(const TickerMode(enabled: false, child: LoadingTv())));
    await tester.pump(LoadingTvTheme.frame * 2);
    expect(_face(tester), 0);
  });

  testWidgets('asks for a frame only when its face changes', (tester) async {
    await tester.pumpWidget(_host(const LoadingTv()));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(LoadingTvTheme.frame - const Duration(milliseconds: 16));
    expect(_face(tester), 1);
  });

  testWidgets('the first-load state reads 正在努力加载... at 14 pt, one stop for VoiceOver', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(const LoadingTvState()));
    expect(find.text(LoadingTvState.message), findsOneWidget);
    expect(find.byType(LoadingTv), findsOneWidget);
    expect(tester.widget<Text>(find.text(LoadingTvState.message)).style?.fontSize, 14);
    expect(find.bySemanticsLabel('加载中'), findsNothing);
    semantics.dispose();
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

  group("the 装扮's 加载动画 in a refresh", () {
    Widget indicator(AppServices services, RefreshIndicatorMode mode, double pulled, {double room = 60}) => AppScope(
      services: services,
      child: _host(
        SizedBox(
          width: 100,
          height: pulled,
          child: Builder(builder: (context) => loadingTvRefreshIndicator(context, mode, pulled, 100, room)),
        ),
      ),
    );

    RawImage drawn(WidgetTester tester) =>
        tester.widget<RawImage>(find.descendant(of: find.byType(SkinLoadingView), matching: find.byType(RawImage)));

    testWidgets("takes the TV's place: its first frame while dragged, playing while refreshing", (tester) async {
      final (services, skin) = (await tester.runAsync(skinOnlyServices))!;
      final animation = await standInLoading(tester);
      skin.shownLoading.value = animation;

      await tester.pumpWidget(indicator(services, RefreshIndicatorMode.drag, 30, room: SkinLoadingTheme.room));
      expect(find.byType(LoadingTv), findsNothing);
      expect(tester.widget<SkinLoadingView>(find.byType(SkinLoadingView)).playing, isFalse);
      expect(identical(drawn(tester).image, animation.first), isTrue);
      expect(tester.getSize(find.byType(SkinLoadingView)).height, SkinLoadingTheme.size);
      final pulled = tester.getRect(find.byType(ClipRect));
      expect(pulled.height, 30);
      expect(
        tester.getBottomLeft(find.byType(SkinLoadingView)).dy,
        pulled.bottom,
        reason: 'it comes down from under what is above, its foot first',
      );

      await tester.pumpWidget(
        indicator(services, RefreshIndicatorMode.refresh, SkinLoadingTheme.room, room: SkinLoadingTheme.room),
      );
      expect(tester.widget<SkinLoadingView>(find.byType(SkinLoadingView)).playing, isTrue);
      for (var round = 0; round < 3; round++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(identical(drawn(tester).image, animation.first), isFalse, reason: 'its next frames');

      skin.shownLoading.value = null;
      await tester.pump();
      expect(find.byType(SkinLoadingView), findsNothing);
      expect(find.byType(LoadingTv), findsOneWidget, reason: 'taken off: the TV again');
    });

    testWidgets("in a list that keeps the TV's 60 pt room, it draws in the room", (tester) async {
      final (services, skin) = (await tester.runAsync(skinOnlyServices))!;
      skin.shownLoading.value = await standInLoading(tester);
      await tester.pumpWidget(indicator(services, RefreshIndicatorMode.refresh, 60));
      expect(tester.getSize(find.byType(SkinLoadingView)).height, 60);
      expect(tester.widget<SkinLoadingView>(find.byType(SkinLoadingView)).size, 60);
    });

    testWidgets('without one, or outside AppScope, the TV', (tester) async {
      final (services, _) = (await tester.runAsync(skinOnlyServices))!;
      await tester.pumpWidget(indicator(services, RefreshIndicatorMode.refresh, 60));
      expect(find.byType(LoadingTv), findsOneWidget);
      expect(find.byType(SkinLoadingView), findsNothing);
      await tester.pumpWidget(_host(const RefreshLoading()));
      expect(find.byType(LoadingTv), findsOneWidget);
    });

    testWidgets("a page's first load keeps the TV", (tester) async {
      final (services, skin) = (await tester.runAsync(skinOnlyServices))!;
      skin.shownLoading.value = await standInLoading(tester);
      await tester.pumpWidget(AppScope(services: services, child: _host(const LoadingTvState())));
      expect(find.byType(LoadingTv), findsOneWidget);
      expect(find.byType(SkinLoadingView), findsNothing);
    });

    testWidgets("a state with SkinRefreshRoom holds the 加载动画's room while one is worn", (tester) async {
      final (services, skin) = (await tester.runAsync(skinOnlyServices))!;
      await tester.pumpWidget(AppScope(services: services, child: const _Room()));
      expect(find.text('${LoadingTvTheme.size}'), findsOneWidget);
      skin.shownLoading.value = await standInLoading(tester);
      await tester.pump();
      expect(find.text('${SkinLoadingTheme.room}'), findsOneWidget);
      skin.shownLoading.value = null;
      await tester.pump();
      expect(find.text('${LoadingTvTheme.size}'), findsOneWidget);
    });
  });
}

class _Room extends StatefulWidget {
  const _Room();

  @override
  State<_Room> createState() => _RoomState();
}

class _RoomState extends State<_Room> with SkinRefreshRoom {
  @override
  Widget build(BuildContext context) => Text('$refreshRoom', textDirection: TextDirection.ltr);
}
