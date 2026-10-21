import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/search/search_filters.dart';
import 'package:bilifast/search/search_history_store.dart';
import 'package:bilifast/search/search_model.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

SearchVideo video(int i, {int duration = 300}) => SearchVideo(
  aid: i,
  bvid: 'BV$i',
  title: HighlightedText.plain('视频$i'),
  author: 'UP$i',
  mid: i,
  cover: '',
  play: 0,
  danmaku: 0,
  duration: duration,
  published: null,
);

SearchUser user(int mid, {bool following = false}) =>
    SearchUser(mid: mid, name: '用户$mid', face: '', fans: 0, videos: 0, level: 1, sign: '', following: following);

List<SearchVideo> videoRows(int count) => [for (var i = 1; i <= count; i++) video(i)];

List<SearchSuggestion> suggest(String term) => [
  SearchSuggestion(keyword: '$term教程', text: HighlightedText([HighlightRun(term, highlighted: true)])),
];

/// Every message and field value logged, as text.
List<String> logged(MemorySink logs) => [
  for (final event in logs.events) ...[event.msg, for (final value in event.f.values) '${value.toJson()}'],
];

void main() {
  late MemorySink logs;
  late SearchHistoryStore history;

  setUp(() {
    logs = MemorySink();
    history = SearchHistoryStore.memory(logger: Logger(session: 'test'));
  });

  // No gap unless a test asks for one, so pages answer within pumpEventQueue.
  SearchModel make(
    FakeSearchApi api, {
    String? placeholder,
    Duration gap = Duration.zero,
    DateTime Function()? now,
  }) => SearchModel(
    api: api,
    history: history,
    placeholder: placeholder,
    searchGap: gap,
    now: now,
    logger: Logger(session: 'test')..add(logs),
  );

  final start = DateTime(2026, 10, 21, 12);
  const gap = Duration(milliseconds: 500);
  const over120 = SearchFilters(length: FilterLength.over120);

  List<int> aids(SearchModel model) => [for (final row in model.videos.items) row.aid];

  group('suggestions', () {
    test('are asked for only once typing pauses for the debounce', () {
      fakeAsync((async) {
        final api = FakeSearchApi(suggest: suggest);
        final model = make(api);
        model.textChanged('猫');
        expect(model.stage, SearchStage.typing);
        async.elapse(const Duration(milliseconds: 200));
        model.textChanged('猫咪');
        async.elapse(const Duration(milliseconds: 299));
        expect(api.calls, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(api.calls, ['suggestions 猫咪']);
        async.flushMicrotasks();
        expect([for (final item in model.suggestions) item.keyword], ['猫咪教程']);
      });
    });

    test('an answer for older text is dropped, and the newer text is asked once it is in, one call at a time', () {
      fakeAsync((async) {
        final api = FakeSearchApi(suggest: suggest)..held.add('suggestions');
        final model = make(api);
        model.textChanged('a');
        async.elapse(const Duration(milliseconds: 300));
        model.textChanged('ab');
        async.elapse(const Duration(milliseconds: 300));
        expect(api.calls, ['suggestions a'], reason: 'the first is still out');

        api.release();
        async.flushMicrotasks();
        expect(model.suggestions, isEmpty, reason: "a's answer came after ab was typed");
        expect(api.calls, ['suggestions a', 'suggestions ab']);

        api.release();
        async.flushMicrotasks();
        expect([for (final item in model.suggestions) item.keyword], ['ab教程']);
        expect(api.maxSuggestionsOut, 1);
      });
    });

    test('empty text goes back to the empty page and clears them, and drops an answer still out', () {
      fakeAsync((async) {
        final api = FakeSearchApi(suggest: suggest);
        final model = make(api);
        model.textChanged('a');
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(model.suggestions, hasLength(1));

        model.textChanged('  ');
        expect(model.stage, SearchStage.home);
        expect(model.suggestions, isEmpty);

        api.held.add('suggestions');
        model.textChanged('b');
        async.elapse(const Duration(milliseconds: 300));
        model.textChanged('');
        api.release();
        async.flushMicrotasks();
        expect(model.stage, SearchStage.home);
        expect(model.suggestions, isEmpty);
      });
    });

    test('typing that pauses for less than the debounce asks nothing when the field is emptied', () {
      fakeAsync((async) {
        final api = FakeSearchApi(suggest: suggest);
        final model = make(api);
        model.textChanged('a');
        async.elapse(const Duration(milliseconds: 100));
        model.textChanged('');
        async.elapse(const Duration(seconds: 1));
        expect(api.calls, isEmpty);
      });
    });

    test('editing the field from the results goes back to typing; searching drops an answer still out', () {
      fakeAsync((async) {
        final api = FakeSearchApi(suggest: suggest, videos: videoRows(3));
        final model = make(api);
        model.search('猫');
        async.flushMicrotasks();
        expect(model.stage, SearchStage.results);

        model.textChanged('猫咪');
        expect(model.stage, SearchStage.typing);

        api.held.add('suggestions');
        async.elapse(const Duration(milliseconds: 300));
        model.search('猫咪');
        api.release();
        async.flushMicrotasks();
        expect(model.stage, SearchStage.results);
        expect(model.suggestions, isEmpty);
      });
    });

    test('a failed answer is logged without the text, and the next typing asks again', () {
      fakeAsync((async) {
        final api = FakeSearchApi(suggest: suggest)..failNext('suggestions');
        final model = make(api);
        model.textChanged('秘密');
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(model.suggestions, isEmpty);
        expect(logs.events.single.msg, 'search suggestions failed');
        expect(logged(logs).where((text) => text.contains('秘密')), isEmpty);

        model.textChanged('秘密2');
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(model.suggestions, hasLength(1));
      });
    });
  });

  group('search', () {
    test('trims, ignores blank, records history, selects 综合 and asks its first page', () async {
      final api = FakeSearchApi(videos: videoRows(3), users: [user(1)]);
      final model = make(api);
      model.search('   ');
      expect(api.calls, isEmpty);
      expect(model.stage, SearchStage.home);

      model.search('  猫 ');
      expect(model.keyword, '猫');
      expect(model.stage, SearchStage.results);
      expect(model.tab, SearchTab.all);
      expect(model.videos.loading, isTrue);
      expect(history.words, ['猫']);
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1']);
      expect(aids(model), [1, 2, 3]);
      expect(model.videos.loaded, isTrue);
      expect(model.videos.exhausted, isTrue);
      expect(model.users.loaded, isFalse, reason: '用户 waits until it is shown');
    });

    test('pages count 1, 2, 3 and the end follows hasMore', () async {
      final api = FakeSearchApi(videos: videoRows(45));
      final model = make(api)..search('猫');
      await pumpEventQueue();
      expect(model.videos.canLoadMore, isTrue);
      await model.loadMore();
      expect(model.videos.exhausted, isFalse);
      await model.loadMore();
      expect(aids(model), [for (var i = 1; i <= 45; i++) i]);
      expect(model.videos.exhausted, isTrue);
      expect(model.videos.canLoadMore, isFalse);
      await model.loadMore();
      expect(api.calls, ['videos 猫 1', 'videos 猫 2', 'videos 猫 3']);
    });

    test('a row already shown is not shown twice', () async {
      final api = FakeSearchApi(videos: [video(1), video(2), video(2), video(3)], pageSize: 2);
      final model = make(api)..search('猫');
      await pumpEventQueue();
      await model.loadMore();
      expect(aids(model), [1, 2, 3]);
    });

    test('用户 asks its first page when shown, and a new search empties both tabs and shows 综合', () async {
      final api = FakeSearchApi(videos: videoRows(3), users: [user(1), user(2)]);
      final model = make(api)..search('猫');
      await pumpEventQueue();
      model.selectTab(SearchTab.users);
      expect(model.tab, SearchTab.users);
      await pumpEventQueue();
      expect([for (final row in model.users.items) row.mid], [1, 2]);
      model.selectTab(SearchTab.all);
      model.selectTab(SearchTab.users);
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1', 'users 猫 1'], reason: 'a tab already loaded is not asked again');

      model.search('狗');
      expect(model.tab, SearchTab.all);
      expect(model.users.loaded, isFalse);
      expect(model.users.items, isEmpty);
      await pumpEventQueue();
      expect(api.calls.last, 'videos 狗 1');
      expect(history.words, ['狗', '猫']);
    });

    test("a new keyword awaits its first page until 综合 answers or fails; 筛选 and 用户 don't wait again", () async {
      final api = FakeSearchApi(videos: videoRows(3), users: [user(1)]);
      final model = make(api);
      expect(model.awaitingFirstPage, isFalse);
      model.search('猫');
      expect(model.awaitingFirstPage, isTrue);
      await pumpEventQueue();
      expect(model.awaitingFirstPage, isFalse);

      model.setFilters(const SearchFilters(order: FilterOrder.newest));
      expect(model.awaitingFirstPage, isFalse);
      model.selectTab(SearchTab.users);
      expect(model.awaitingFirstPage, isFalse);
      await pumpEventQueue();

      api.failNext('videos');
      model.search('狗');
      expect(model.awaitingFirstPage, isTrue);
      await pumpEventQueue();
      expect(model.videos.error, isNotNull);
      expect(model.awaitingFirstPage, isFalse, reason: 'the failure shows with the tab row');
      unawaited(model.retry());
      expect(model.awaitingFirstPage, isFalse, reason: '重试 keeps the tab row');
      await pumpEventQueue();

      model.search('狗');
      expect(model.awaitingFirstPage, isTrue, reason: 'the same word again is a new search');
      await pumpEventQueue();
      expect(model.awaitingFirstPage, isFalse);
    });

    test('searches counts every search, the same word again included, and nothing for a blank one', () async {
      final api = FakeSearchApi(videos: videoRows(3));
      final model = make(api);
      expect(model.searches, 0);
      model.search('猫');
      expect(model.searches, 1);
      model.search(' 猫');
      model.search('');
      expect(model.searches, 2);
      model.search('狗');
      expect(model.searches, 3);
      await pumpEventQueue();
    });
  });

  group('one call at a time, across suggestions and pages', () {
    test('搜索 pressed while a suggestion call is out waits for it, then drops its answer', () {
      fakeAsync((async) {
        final api = FakeSearchApi(suggest: suggest, videos: videoRows(3))..held.add('suggestions');
        final model = make(api);
        model.textChanged('猫');
        async.elapse(const Duration(milliseconds: 300));
        model.search('猫');
        async.flushMicrotasks();
        expect(api.calls, ['suggestions 猫'], reason: 'the page waits for the suggestion call');

        api.release();
        async.flushMicrotasks();
        expect(api.calls, ['suggestions 猫', 'videos 猫 1']);
        expect(model.suggestions, isEmpty);
        expect(model.stage, SearchStage.results);
        expect(aids(model), [1, 2, 3]);
        expect(api.maxCallsOut, 1);
      });
    });

    test('typing while a page is out asks for suggestions once the page has answered', () {
      fakeAsync((async) {
        final api = FakeSearchApi(suggest: suggest, videos: videoRows(3))..held.add('videos');
        final model = make(api)..search('猫');
        async.flushMicrotasks();
        model.textChanged('猫咪');
        async.elapse(const Duration(milliseconds: 300));
        expect(api.calls, ['videos 猫 1']);

        api.release();
        async.flushMicrotasks();
        expect(api.calls, ['videos 猫 1', 'suggestions 猫咪']);
        expect([for (final item in model.suggestions) item.keyword], ['猫咪教程']);
        expect(api.maxCallsOut, 1);
      });
    });
  });

  group('the gap between pages', () {
    test('a page goes no sooner than the gap after the last answered; later, or a first search, goes at once', () {
      fakeAsync((async) {
        final api = FakeSearchApi(videos: videoRows(100));
        final model = make(api, gap: gap, now: () => start.add(async.elapsed));
        model.search('猫');
        async.flushMicrotasks();
        expect(api.calls, ['videos 猫 1'], reason: 'nothing ran before it');

        unawaited(model.loadMore());
        async.elapse(const Duration(milliseconds: 499));
        expect(api.calls, hasLength(1));
        expect(model.videos.loading, isTrue);
        async.elapse(const Duration(milliseconds: 1));
        expect(api.calls.last, 'videos 猫 2');

        async.elapse(const Duration(seconds: 2));
        unawaited(model.loadMore());
        async.flushMicrotasks();
        expect(api.calls.last, 'videos 猫 3', reason: 'the gap had passed');

        model.search('狗');
        async.elapse(const Duration(milliseconds: 499));
        expect(api.calls, hasLength(3), reason: "a new search's first page waits out the gap too");
        async.elapse(const Duration(milliseconds: 1));
        expect(api.calls.last, 'videos 狗 1');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('pages one load asks on through are as far apart', () {
      fakeAsync((async) {
        final api = FakeSearchApi(videos: [for (var i = 1; i <= 10; i++) video(i, duration: 60)], pageSize: 1);
        final model = make(api, gap: gap, now: () => start.add(async.elapsed));
        model
          ..setFilters(over120)
          ..search('猫');
        async.flushMicrotasks();
        expect(api.calls, ['videos 猫 1']);
        async.elapse(const Duration(milliseconds: 499));
        expect(api.calls, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(api.calls, hasLength(2));
        async.elapse(gap);
        expect(api.calls, hasLength(3));
        async.elapse(const Duration(seconds: 5));
        expect(api.calls, hasLength(SearchModel.pagesPerLoad));
      });
    });

    test('suggestions neither wait for the gap nor start it', () {
      fakeAsync((async) {
        final api = FakeSearchApi(suggest: suggest, videos: videoRows(100));
        final model = make(api, gap: gap, now: () => start.add(async.elapsed));
        model.textChanged('猫');
        async.elapse(const Duration(milliseconds: 300));
        model.search('猫');
        async.flushMicrotasks();
        expect(api.calls, ['suggestions 猫', 'videos 猫 1']);

        async.elapse(const Duration(seconds: 1));
        model.textChanged('猫咪');
        async.elapse(const Duration(milliseconds: 300));
        unawaited(model.loadMore());
        async.flushMicrotasks();
        expect(api.calls.skip(2), ['suggestions 猫咪', 'videos 猫 2'], reason: "the suggestion didn't restart the gap");

        model.textChanged('猫咪咪');
        async.elapse(const Duration(milliseconds: 300));
        expect(api.calls.last, 'suggestions 猫咪咪', reason: '300 ms after a page, inside the gap');
      });
    });

    test('dispose during a rest sends nothing and ends the waiting load', () {
      fakeAsync((async) {
        final api = FakeSearchApi(videos: videoRows(100));
        final model = make(api, gap: gap, now: () => start.add(async.elapsed))..search('猫');
        async.flushMicrotasks();
        var done = false;
        unawaited(model.loadMore().then((_) => done = true));
        model.dispose();
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(api.calls, ['videos 猫 1']);
      });
    });
  });

  group('one search call at a time', () {
    test('a new search waits for the call that is out, whose answer is dropped', () async {
      final api = FakeSearchApi(videos: videoRows(3))..held.add('videos');
      final model = make(api)..search('猫');
      model.search('狗');
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1']);
      expect(model.videos.loading, isTrue);

      api.release();
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1', 'videos 狗 1']);
      expect(model.videos.items, isEmpty, reason: "猫's page is not 狗's");
      expect(model.videos.loading, isTrue);

      api.release();
      await pumpEventQueue();
      expect(aids(model), [1, 2, 3]);
      expect(model.keyword, '狗');
      expect(api.maxSearchesOut, 1);
    });

    test('a tab change, a filter change and load more wait for the call that is out too', () async {
      final api = FakeSearchApi(videos: videoRows(45), users: [user(1)])..held.addAll({'videos', 'users'});
      final model = make(api)..search('猫');
      model.selectTab(SearchTab.users);
      unawaited(model.loadMore());
      model.setFilters(const SearchFilters(order: FilterOrder.newest));
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1']);

      api.release();
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1', 'users 猫 1'], reason: '综合 waits until it is shown again');
      api.release();
      await pumpEventQueue();
      expect(model.users.items, hasLength(1));
      expect(model.videos.loaded, isFalse, reason: "the page for the old 筛选 was dropped");

      model.selectTab(SearchTab.all);
      unawaited(model.loadMore());
      unawaited(model.retry());
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1', 'users 猫 1', 'videos 猫 1']);
      expect(api.videoFilters.last.order, FilterOrder.newest);
      api.release();
      await pumpEventQueue();
      expect(aids(model), hasLength(20));
      expect(api.maxSearchesOut, 1);
    });

    test("the shown tab's waiting page goes first", () async {
      final api = FakeSearchApi(videos: videoRows(3), users: [user(1)])..held.addAll({'videos', 'users'});
      final model = make(api)..search('猫');
      model.setFilters(const SearchFilters(order: FilterOrder.plays));
      model.selectTab(SearchTab.users);
      api.release();
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1', 'users 猫 1']);
      api.release();
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1', 'users 猫 1', 'videos 猫 1']);
      api.release();
      await pumpEventQueue();
      expect(model.videos.items, hasLength(3), reason: "综合's new page loaded behind the shown tab");
    });

    test('load more while a page is out sends nothing more and waits for that page', () async {
      final api = FakeSearchApi(videos: videoRows(45))..held.add('videos');
      final model = make(api)..search('猫');
      api.release();
      await pumpEventQueue();
      final first = model.loadMore();
      final second = model.loadMore();
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1', 'videos 猫 2']);
      var done = false;
      unawaited(Future.wait([first, second]).then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse);
      api.release();
      await pumpEventQueue();
      expect(done, isTrue);
      expect(aids(model), hasLength(40));
    });
  });

  group('筛选', () {
    test('a change asks 综合 again from page 1 with the new filters; the same filters ask nothing', () async {
      final api = FakeSearchApi(videos: videoRows(45));
      final model = make(api)..search('猫');
      await pumpEventQueue();
      await model.loadMore();
      const newest = SearchFilters(order: FilterOrder.newest);
      model.setFilters(newest);
      expect(model.videos.items, isEmpty);
      expect(model.filters, newest);
      await pumpEventQueue();
      model.setFilters(newest);
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1', 'videos 猫 2', 'videos 猫 1']);
      expect(api.videoFilters, [const SearchFilters(), const SearchFilters(), newest]);
      expect(aids(model), hasLength(20));
    });

    test('a change while 用户 is shown asks 综合 only when it is shown again', () async {
      final api = FakeSearchApi(videos: videoRows(3), users: [user(1)]);
      final model = make(api)..search('猫');
      await pumpEventQueue();
      model.selectTab(SearchTab.users);
      await pumpEventQueue();
      model.setFilters(const SearchFilters(length: FilterLength.under10));
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1', 'users 猫 1']);
      model.selectTab(SearchTab.all);
      await pumpEventQueue();
      expect(api.calls.last, 'videos 猫 1');
      expect(api.videoFilters.last.length, FilterLength.under10);
    });

    test("60-120 and 120+ are cut on our side from the search's over-60 rows", () async {
      final rows = [
        video(2, duration: 3600),
        video(3, duration: 7199),
        video(4, duration: 7200),
        video(5, duration: 9000),
      ];
      final api = FakeSearchApi(videos: rows);
      final model = make(api)..search('猫');
      model.setFilters(const SearchFilters(length: FilterLength.from60to120));
      await pumpEventQueue();
      expect(aids(model), [2, 3]);
      model.setFilters(const SearchFilters(length: FilterLength.over120));
      await pumpEventQueue();
      expect(aids(model), [4, 5]);
    });

    test('a page the cut empties is followed by the next, up to three pages a load, then the tab stalls', () async {
      final short = [for (var i = 1; i <= 4; i++) video(i, duration: 60)];
      final api = FakeSearchApi(videos: [...short, video(5, duration: 8000), video(6, duration: 60)], pageSize: 1);
      final model = make(api);
      model.setFilters(over120);
      model.search('猫');
      await pumpEventQueue();
      expect(api.calls, ['videos 猫 1', 'videos 猫 2', 'videos 猫 3']);
      expect(model.videos.items, isEmpty);
      expect(model.videos.loaded, isTrue);
      expect(model.videos.exhausted, isFalse);
      expect(model.videos.stalled, isTrue);
      expect(model.videos.canLoadMore, isFalse);

      await model.loadMore();
      expect(api.calls.skip(3), ['videos 猫 4', 'videos 猫 5'], reason: 'it stops at the page that adds a row');
      expect(aids(model), [5]);
      expect(model.videos.stalled, isFalse, reason: 'the explicit load added a row');
      expect(model.videos.canLoadMore, isTrue);

      await model.loadMore();
      expect(api.calls.last, 'videos 猫 6');
      expect(model.videos.exhausted, isTrue);
      expect(aids(model), [5]);
    });
  });

  group('stalled', () {
    test('40 pages the cut empties: the automatic check stops after one load, an explicit load asks one more', () async {
      final api = FakeSearchApi(videos: [for (var i = 1; i <= 40; i++) video(i, duration: 60)], pageSize: 1);
      final model = make(api)
        ..setFilters(over120)
        ..search('猫');
      await pumpEventQueue();
      // What the results view does by itself while the end is on screen.
      for (var round = 0; round < 50 && model.videos.canLoadMore; round++) {
        await model.loadMore();
      }
      expect(api.calls, hasLength(SearchModel.pagesPerLoad));
      expect(model.videos.stalled, isTrue);
      expect(model.videos.exhausted, isFalse);

      await model.loadMore();
      expect(api.calls, hasLength(2 * SearchModel.pagesPerLoad));
      expect(api.calls.last, 'videos 猫 6');
      expect(model.videos.stalled, isTrue);
      expect(model.videos.canLoadMore, isFalse);
    });

    test('a new search and a 筛选 change clear it, and a failure is not a stall', () async {
      final api = FakeSearchApi(videos: [for (var i = 1; i <= 40; i++) video(i, duration: 60)], pageSize: 1);
      final model = make(api)
        ..setFilters(over120)
        ..search('猫');
      await pumpEventQueue();
      expect(model.videos.stalled, isTrue);

      model.setFilters(const SearchFilters(order: FilterOrder.newest, length: FilterLength.over120));
      expect(model.videos.stalled, isFalse);
      await pumpEventQueue();
      expect(model.videos.stalled, isTrue);

      model.search('狗');
      expect(model.videos.stalled, isFalse);
      await pumpEventQueue();
      expect(model.videos.stalled, isTrue);

      api.failNext('videos');
      await model.loadMore();
      expect(model.videos.error, isNotNull);
      expect(model.videos.stalled, isFalse);

      model.setFilters(const SearchFilters());
      await pumpEventQueue();
      expect(model.videos.stalled, isFalse);
      expect(aids(model), hasLength(1));
      expect(model.videos.canLoadMore, isTrue);
    });
  });

  group('发布时间', () {
    test('every page of one search and 筛选 asks the same window; a new search or 筛选 moves it', () {
      fakeAsync((async) {
        final api = FakeSearchApi(videos: videoRows(100));
        final model = make(api, now: () => start.add(async.elapsed));
        const week = SearchFilters(published: FilterPublished.week);
        model
          ..setFilters(week)
          ..search('猫');
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 5));
        unawaited(model.loadMore());
        async.flushMicrotasks();
        expect(api.calls, ['videos 猫 1', 'videos 猫 2']);
        expect(api.videoMoments, [start, start]);

        model.setFilters(const SearchFilters(published: FilterPublished.day));
        async.flushMicrotasks();
        final moved = start.add(const Duration(minutes: 5));
        expect(api.videoMoments.last, moved);
        async.elapse(const Duration(minutes: 1));
        model.selectTab(SearchTab.users);
        model.selectTab(SearchTab.all);
        unawaited(model.loadMore());
        async.flushMicrotasks();
        expect(api.videoMoments.last, moved, reason: 'a tab change keeps the window');

        model.search('狗');
        async.flushMicrotasks();
        expect(api.videoMoments.last, start.add(const Duration(minutes: 6)));
      });
    });
  });

  group('errors', () {
    test('a failed page keeps the rows, waits for retry, and retry asks that page again', () async {
      final api = FakeSearchApi(videos: videoRows(45));
      final model = make(api)..search('猫');
      await pumpEventQueue();
      api.failNext('videos', const BiliError.api(code: -412, message: '请求被拦截'));
      await model.loadMore();
      expect(aids(model), hasLength(20));
      expect(model.videos.error, '请求过于频繁，请稍后再试');
      expect(model.videos.loading, isFalse);
      expect(model.videos.canLoadMore, isFalse);
      expect(model.videos.isEmpty, isFalse);

      await model.loadMore();
      expect(api.calls, ['videos 猫 1', 'videos 猫 2'], reason: 'endless scroll does not ask again by itself');

      final retrying = model.retry();
      expect(model.videos.error, isNull, reason: 'the spinner shows instead');
      expect(model.videos.loading, isTrue);
      await retrying;
      expect(api.calls, ['videos 猫 1', 'videos 猫 2', 'videos 猫 2']);
      expect(aids(model), hasLength(40));
      expect(model.videos.error, isNull);
    });

    test('a failed first page shows its message, and retry asks page 1', () async {
      final api = FakeSearchApi(users: [user(1)])..failNext('users', TimeoutException('slow'));
      final model = make(api)..search('猫');
      await pumpEventQueue();
      model.selectTab(SearchTab.users);
      await pumpEventQueue();
      expect(model.users.loaded, isTrue);
      expect(model.users.error, '网络连接失败，请检查网络后重试');
      expect(model.users.isEmpty, isFalse);
      await model.retry();
      expect(api.calls.last, 'users 猫 1');
      expect(model.users.items, hasLength(1));
    });

    test('pages and failures are logged without the keyword', () async {
      final api = FakeSearchApi(videos: videoRows(45))
        ..failNext('videos', Exception('GET https://api.bilibili.com/x/web-interface/wbi/search/all/v2?keyword=秘密'));
      final model = make(api)..search('秘密');
      await pumpEventQueue();
      await model.retry();
      expect([for (final event in logs.events) event.msg], ['search page failed', 'search page']);
      expect(logs.events.first.f['page']?.toJson(), 1);
      expect(logged(logs).where((text) => text.contains('秘密')), isEmpty);
    });
  });

  group('the empty page', () {
    test('loadHome asks the default word only without a placeholder, and fills 热搜 and 搜索发现', () async {
      final hot = [const HotWord(keyword: '热', showName: '热词')];
      final found = [const DiscoveryWord(keyword: '发现', showName: '发现')];
      final given = FakeSearchApi(defaultWord: '默认', hotWords: hot, discovery: found);
      final withPlaceholder = make(given, placeholder: '首页的词');
      await withPlaceholder.loadHome();
      expect(given.calls, unorderedEquals(['hotWords', 'discovery']));
      expect(withPlaceholder.placeholder, '首页的词');

      final asked = FakeSearchApi(defaultWord: '默认', hotWords: hot, discovery: found);
      final model = make(asked);
      var notified = 0;
      model.addListener(() => notified++);
      await model.loadHome();
      expect(model.placeholder, '默认');
      expect(model.hotWords, hot);
      expect(model.discovery, found);
      expect(notified, 3, reason: 'each part shows as it comes');
    });

    test('a part that fails stays empty and is logged, and the others still come', () async {
      final api = FakeSearchApi(
        defaultWord: '默认',
        hotWords: [const HotWord(keyword: '热', showName: '热')],
        discovery: [const DiscoveryWord(keyword: '发现', showName: '发现')],
      )..failNext('hotWords');
      final model = make(api);
      await model.loadHome();
      expect(model.hotWords, isEmpty);
      expect(model.placeholder, '默认');
      expect(model.discovery, hasLength(1));
      expect(logs.events.single.msg, 'search home part failed');
      expect(logs.events.single.f['part']?.toJson(), 'hot words');
    });

    test('refreshDiscovery replaces 搜索发现, once however often it is pressed, and a failure keeps the words', () async {
      final api = FakeSearchApi.demo(now: DateTime(2026, 10, 21, 12));
      final model = make(api);
      await model.loadHome();
      final before = [for (final word in model.discovery) word.keyword];

      api.held.add('discovery');
      final first = model.refreshDiscovery();
      final second = model.refreshDiscovery();
      api.release();
      expect(await Future.wait([first, second]), [true, true]);
      expect(api.calls.where((call) => call == 'discovery'), hasLength(2));
      final after = [for (final word in model.discovery) word.keyword];
      expect(after, isNot(before));
      expect(after, hasLength(12));

      api
        ..held.clear()
        ..failNext('discovery');
      expect(await model.refreshDiscovery(), isFalse, reason: 'for the page to say so');
      expect([for (final word in model.discovery) word.keyword], after);
      expect(await model.refreshDiscovery(), isTrue);
    });
  });

  test('setFollowing shows the row in its new state at once, and nothing for no change', () async {
    final api = FakeSearchApi(users: [user(1), user(2), user(3, following: true)]);
    final model = make(api)
      ..search('猫')
      ..selectTab(SearchTab.users);
    await pumpEventQueue();
    var notified = 0;
    model.addListener(() => notified++);
    final untouched = model.users.items[0];

    model.setFollowing(2, following: true);
    expect([for (final row in model.users.items) row.following], [false, true, true]);
    expect(identical(model.users.items[0], untouched), isTrue);
    expect(model.users.items[1].name, '用户2');
    expect(notified, 1);

    model
      ..setFollowing(2, following: true)
      ..setFollowing(99, following: true);
    expect(notified, 1);
    model.setFollowing(3, following: false);
    expect([for (final row in model.users.items) row.following], [false, true, false]);
    expect(model.users.loaded, isTrue);
  });

  test('after dispose nothing is notified or asked, and no timer is left', () {
    fakeAsync((async) {
      final api = FakeSearchApi(suggest: suggest, videos: videoRows(45), users: [user(1)])..held.add('videos');
      final model = make(api)..search('猫');
      model.selectTab(SearchTab.users);
      model.textChanged('狗');
      var notified = 0;
      model.addListener(() => notified++);
      model.dispose();
      expect(async.pendingTimers, isEmpty);

      api.release();
      async.elapse(const Duration(seconds: 1));
      expect(api.calls, ['videos 猫 1'], reason: 'neither the waiting 用户 page nor the suggestions go out');
      expect(notified, 0);
      model
        ..textChanged('猫咪')
        ..search('鱼');
      unawaited(model.loadHome());
      async.elapse(const Duration(seconds: 1));
      expect(api.calls, ['videos 猫 1']);
      expect(async.pendingTimers, isEmpty);
    });
  });
}
