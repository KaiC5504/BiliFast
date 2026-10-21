import 'package:bili_core/api.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/search/search_filters.dart';
import 'package:flutter_test/flutter_test.dart';

SearchUser user(int mid) => SearchUser(mid: mid, name: '用户$mid', face: '', fans: 0, videos: 0, level: 1, sign: '');

final _asOf = DateTime(2026, 10, 21, 12);

void main() {
  group('the fake', () {
    test('pages its rows and records the calls, the filters and the moments', () async {
      final api = FakeSearchApi(users: [for (var i = 1; i <= 5; i++) user(i)], pageSize: 2);
      final second = await api.users('猫', page: 2);
      expect([for (final row in second.items) row.mid], [3, 4]);
      expect(second.hasMore, isTrue);
      final third = await api.users('猫', page: 3);
      expect([for (final row in third.items) row.mid], [5]);
      expect(third.hasMore, isFalse);
      const newest = SearchFilters(order: FilterOrder.newest);
      final none = await api.videos('猫', page: 1, filters: newest, asOf: _asOf);
      expect(none.items, isEmpty);
      expect(none.hasMore, isFalse);
      expect(api.calls, ['users 猫 2', 'users 猫 3', 'videos 猫 1']);
      expect(api.videoFilters, [newest]);
      expect(api.videoMoments, [_asOf]);
    });

    test('holds the calls named until released, and counts the search calls out at once', () async {
      final api = FakeSearchApi(users: [user(1)])..held.addAll({'users', 'videos'});
      var answered = 0;
      final first = api.users('猫', page: 1).then((_) => answered++);
      final second = api.videos('猫', page: 1, filters: const SearchFilters(), asOf: _asOf).then((_) => answered++);
      await pumpEventQueue();
      expect(answered, 0);
      expect(api.waiting, 2);
      expect(api.maxSearchesOut, 2);
      api.release('videos');
      await second;
      expect(answered, 1);
      api.release();
      await first;
      expect(api.waiting, 0);
      expect(() => api.release(), throwsStateError);
      expect(api.maxSuggestionsOut, 0);
    });

    test('counts search and suggestion calls out at once together', () async {
      final api = FakeSearchApi(users: [user(1)])..held.addAll({'users', 'suggestions'});
      final suggesting = api.suggestions('猫');
      final searching = api.users('猫', page: 1);
      await pumpEventQueue();
      expect(api.maxSearchesOut, 1);
      expect(api.maxSuggestionsOut, 1);
      expect(api.maxCallsOut, 2);
      api
        ..release()
        ..release();
      await Future.wait([suggesting, searching]);
    });

    test('fails the next call of a method once, after its hold', () async {
      final api =
          FakeSearchApi(
              hotWords: [const HotWord(keyword: '热', showName: '热')],
            )
            ..failNext('hotWords', const BiliError.api(code: -412, message: '拦截'))
            ..held.add('hotWords');
      final failing = api.hotWords();
      await pumpEventQueue();
      api.release();
      await expectLater(failing, throwsA(const BiliError.api(code: -412, message: '拦截')));
      api.held.clear();
      expect(await api.hotWords(), hasLength(1));
    });
  });

  group('the demo', () {
    final now = DateTime(2026, 10, 21, 12);

    test(
      'has a default word, ten hot words with a few without a badge, and 12 discovery words that turn over',
      () async {
        final api = FakeSearchApi.demo(now: now);
        expect(await api.defaultWord(), isNotEmpty);
        final hot = await api.hotWords();
        expect(hot, hasLength(10));
        expect(hot.where((word) => word.icon == null), hasLength(inInclusiveRange(2, 4)));
        final found = await api.discovery();
        final again = await api.discovery();
        expect(found, hasLength(12));
        expect(again, hasLength(12));
        expect([for (final word in again) word.keyword], isNot([for (final word in found) word.keyword]));
        expect({for (final word in found) word.keyword}, hasLength(12));
      },
    );

    test('suggests words built on the typed term, the term marked', () async {
      final suggestions = await FakeSearchApi.demo(now: now).suggestions('露营');
      expect(suggestions, hasLength(greaterThanOrEqualTo(8)));
      for (final suggestion in suggestions) {
        expect(suggestion.keyword, contains('露营'));
        expect(suggestion.text.text, suggestion.keyword);
        expect(suggestion.text.runs.where((run) => run.highlighted).single.text, '露营');
      }
    });

    test('has 45 made-up videos with the keyword marked in every title, over three pages', () async {
      final api = FakeSearchApi.demo(now: now);
      final rows = <SearchVideo>[];
      for (var page = 1; page <= 3; page++) {
        final answer = await api.videos('露营', page: page, filters: const SearchFilters(), asOf: now);
        rows.addAll(answer.items);
        expect(answer.hasMore, page < 3);
      }
      expect(rows, hasLength(45));
      expect({for (final row in rows) row.bvid}, hasLength(45));
      for (final row in rows) {
        expect(row.title.runs.where((run) => run.highlighted).single.text, '露营');
        expect(row.cover, '');
        expect(row.bvid, hasLength(13), reason: 'a character longer than any real BV id');
        expect(row.author, isNotEmpty);
        expect(row.play, greaterThan(row.danmaku));
        expect(row.published!.isBefore(now), isTrue);
      }
      expect({for (final row in rows) row.duration ~/ 600}.length, greaterThan(4), reason: 'lengths for every 内容时长');
    });

    test('applies 筛选 as the video search would: its length buckets, 发布时间 and the order', () async {
      final api = FakeSearchApi.demo(now: now);
      Future<List<SearchVideo>> all(SearchFilters filters) async =>
          (await api.videos('猫', page: 1, filters: filters, asOf: now)).items;

      final long = await all(const SearchFilters(length: FilterLength.from60to120));
      expect(long, isNotEmpty);
      expect(long.every((row) => row.duration >= 3600), isTrue);
      expect(long.any((row) => row.duration >= 7200), isTrue, reason: '120+ is cut by the model, not the search');
      expect((await all(const SearchFilters(length: FilterLength.under10))).every((row) => row.duration < 600), isTrue);

      final today = await all(const SearchFilters(published: FilterPublished.day));
      expect(today, isNotEmpty);
      expect(today.every((row) => now.difference(row.published!) <= const Duration(days: 1)), isTrue);
      final later = (await api.videos(
        '猫',
        page: 1,
        filters: const SearchFilters(published: FilterPublished.day),
        asOf: now.add(const Duration(days: 2)),
      )).items;
      expect(later, isEmpty, reason: '发布时间 counts back from the moment given');

      final newest = await all(const SearchFilters(order: FilterOrder.newest));
      final plays = await all(const SearchFilters(order: FilterOrder.plays));
      for (var i = 1; i < newest.length; i++) {
        expect(newest[i - 1].published!.isBefore(newest[i].published!), isFalse);
        expect(plays[i - 1].play, greaterThanOrEqualTo(plays[i].play));
      }
    });

    test('has 25 made-up uploaders named around the keyword, at levels 1 to 6, some verified and followed', () async {
      final api = FakeSearchApi.demo(now: now);
      final rows = [...(await api.users('露营', page: 1)).items, ...(await api.users('露营', page: 2)).items];
      expect(rows, hasLength(25));
      expect({for (final row in rows) row.mid}, hasLength(25));
      expect(rows.every((row) => row.name.contains('露营')), isTrue);
      expect({for (final row in rows) row.level}, {1, 2, 3, 4, 5, 6});
      expect(rows.where((row) => row.officialType == 0), isNotEmpty);
      expect(rows.where((row) => row.officialType == 1), isNotEmpty);
      expect(rows.where((row) => row.officialType == null), isNotEmpty);
      expect(rows.where((row) => row.following), isNotEmpty);
      expect(rows.every((row) => row.face.isEmpty), isTrue);
    });
  });
}
