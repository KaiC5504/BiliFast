import 'dart:async';

import 'package:bili_core/api.dart' hide SearchPage;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/search/results/results_view.dart';
import 'package:bilifast/search/search_history_store.dart';
import 'package:bilifast/search/search_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import 'results/results_support.dart' show video;

/// 搜索 end to end: the page's own model and results over a seeded fake, from typing to a video page and back.
void main() {
  testWidgets('type, search, scroll, open row 12, come back: the list stays put and nothing is asked again', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final api = FakeSearchApi(
      hotWords: const [HotWord(keyword: 'hot', showName: '热词')],
      suggest: (term) => [SearchSuggestion(keyword: '$term联动', text: HighlightedText.plain('$term联动'))],
      videos: [for (var i = 1; i <= 40; i++) video(i)],
    );
    final history = SearchHistoryStore.memory();
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      searchApi: api,
      searchHistory: history,
    );
    final navigator = GlobalKey<NavigatorState>();
    final routes = <VideoRoute>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const Text('home'),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => SearchPage(
            placeholder: '默认词',
            openVideo: (context, route) {
              routes.add(route);
              unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(body: Center(child: Text('视频页 ${route.bvid}'))),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await settle(tester);

    final field = find.byKey(const ValueKey('search-field'));
    for (final text in ['测', '测试']) {
      await tester.enterText(field, text);
    }
    await settle(tester);
    expect(find.text('测试联动'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(find.byType(ResultsView), findsOneWidget);
    expect(api.calls.where((call) => call.startsWith('videos')), ['videos 测试 1']);

    final list = find.byKey(const ValueKey('search-list-all'));
    await tester.drag(list, const Offset(0, -1200));
    await settle(tester, 40);
    final position = tester
        .state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)))
        .position;
    final scrolled = position.pixels;
    expect(scrolled, greaterThan(1000));
    final calls = api.calls.length;

    final row = find.byKey(const ValueKey('search-video-BV1search12'));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await settle(tester);
    expect(routes.single.bvid, 'BV1search12');
    expect(routes.single.title, '测试视频标题 12');
    expect(find.text('视频页 BV1search12'), findsOneWidget);

    navigator.currentState!.pop();
    await settle(tester);
    expect(find.text('视频页 BV1search12'), findsNothing);
    expect(find.byType(ResultsView), findsOneWidget);
    expect(
      tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable))).position.pixels,
      scrolled,
    );
    expect(api.calls.length, calls, reason: 'coming back asks for nothing');
    expect(history.words, ['测试']);
  });
}

Future<void> settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
