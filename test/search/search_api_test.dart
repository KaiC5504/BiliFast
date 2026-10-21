import 'package:bili_core/api.dart';
import 'package:bilifast/search/search_api.dart';
import 'package:bilifast/search/search_filters.dart';
import 'package:flutter_test/flutter_test.dart';

const _empty = SearchPage<SearchVideo>(items: [], page: 1, pages: 1);

/// Answers like [BiliClient]'s search calls, recording what each was asked.
class RecordingCalls {
  final asked = <String>[];
  Object? cookieFailure;
  ({SearchOrder order, SearchDuration duration, DateTime? from, DateTime? to})? videoQuery;

  SearchCalls get calls => SearchCalls(
    riskCookies: () async {
      asked.add('riskCookies');
      if (cookieFailure case final failure?) throw failure;
    },
    defaultWord: () async {
      asked.add('defaultWord');
      return '默认';
    },
    hotWords: () async {
      asked.add('hotWords');
      return const [HotWord(keyword: '热', showName: '热')];
    },
    discovery: () async {
      asked.add('discovery');
      return const [DiscoveryWord(keyword: '发现', showName: '发现')];
    },
    suggestions: (term) async {
      asked.add('suggestions $term');
      return const [];
    },
    all: ({required keyword, page = 1}) async {
      asked.add('all $keyword $page');
      return _empty;
    },
    videos:
        ({
          required keyword,
          page = 1,
          order = SearchOrder.totalrank,
          duration = SearchDuration.any,
          publishedFrom,
          publishedTo,
        }) async {
          asked.add('videos $keyword $page');
          videoQuery = (order: order, duration: duration, from: publishedFrom, to: publishedTo);
          return _empty;
        },
    users: ({required keyword, page = 1}) async {
      asked.add('users $keyword $page');
      return const SearchPage(items: [], page: 1, pages: 1);
    },
  );
}

void main() {
  final now = DateTime.utc(2026, 10, 21, 8, 30);
  late RecordingCalls client;
  late ClientSearchApi api;

  setUp(() {
    client = RecordingCalls();
    api = ClientSearchApi.calls(client.calls);
  });

  test('综合 without 筛选 asks the mixed search', () async {
    await api.videos('猫', page: 2, filters: const SearchFilters(), asOf: now);
    expect(client.asked, ['riskCookies', 'all 猫 2']);
  });

  test('综合 with 筛选 asks the video search with its order and length, and no dates for 不限', () async {
    await api.videos(
      '猫',
      page: 1,
      filters: const SearchFilters(order: FilterOrder.danmaku, length: FilterLength.from10to30),
      asOf: now,
    );
    expect(client.asked, ['riskCookies', 'videos 猫 1']);
    expect(client.videoQuery, (order: SearchOrder.dm, duration: SearchDuration.from10to30, from: null, to: null));
  });

  test('60-120 and 120+ both ask for over 60 minutes', () async {
    for (final length in [FilterLength.from60to120, FilterLength.over120]) {
      await api.videos('猫', page: 1, filters: SearchFilters(length: length), asOf: now);
      expect(client.videoQuery?.duration, SearchDuration.over60);
    }
  });

  test('发布时间 asks from that long before the moment given until it', () async {
    for (final (published, back) in [
      (FilterPublished.day, const Duration(days: 1)),
      (FilterPublished.week, const Duration(days: 7)),
      (FilterPublished.halfYear, const Duration(days: 182)),
    ]) {
      await api.videos('猫', page: 3, filters: SearchFilters(published: published), asOf: now);
      expect(client.videoQuery, (
        order: SearchOrder.totalrank,
        duration: SearchDuration.any,
        from: now.subtract(back),
        to: now,
      ));
    }
    expect(client.asked, [
      for (var i = 0; i < 3; i++) ...['riskCookies', 'videos 猫 3'],
    ]);
  });

  test('a later page given the same moment asks the same window, whatever the clock says', () async {
    const week = SearchFilters(published: FilterPublished.week);
    await api.videos('猫', page: 1, filters: week, asOf: now);
    final first = client.videoQuery;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await api.videos('猫', page: 2, filters: week, asOf: now);
    expect(client.videoQuery, first);
    expect(client.videoQuery?.to, now);
  });

  test('the other calls go straight through, the web search ones after the fingerprint cookies', () async {
    expect(await api.defaultWord(), '默认');
    expect(await api.hotWords(), hasLength(1));
    expect(await api.discovery(), hasLength(1));
    await api.suggestions('猫');
    await api.users('猫', page: 4);
    expect(client.asked, [
      'riskCookies',
      'defaultWord',
      'hotWords',
      'discovery',
      'suggestions 猫',
      'riskCookies',
      'users 猫 4',
    ]);
  });

  test('a search whose cookies could not be had fails without being sent', () async {
    client.cookieFailure = const BiliError.http(503);
    await expectLater(
      api.videos('猫', page: 1, filters: const SearchFilters(), asOf: now),
      throwsA(const BiliError.http(503)),
    );
    await expectLater(api.users('猫', page: 1), throwsA(const BiliError.http(503)));
    expect(client.asked, ['riskCookies', 'riskCookies']);
  });

  test('a call that throws before its request still fails as a future', () async {
    final throwing = ClientSearchApi.calls(
      SearchCalls(
        riskCookies: () async {},
        defaultWord: () => throw UnimplementedError(),
        hotWords: () => throw UnimplementedError(),
        discovery: () => throw UnimplementedError(),
        suggestions: (_) => throw UnimplementedError(),
        all: ({required keyword, page = 1}) => throw UnimplementedError(),
        videos: ({
          required keyword,
          page = 1,
          order = SearchOrder.totalrank,
          duration = SearchDuration.any,
          publishedFrom,
          publishedTo,
        }) => throw UnimplementedError(),
        users: ({required keyword, page = 1}) => throw UnimplementedError(),
      ),
    );
    final Future<Object?> answer = throwing.suggestions('猫');
    await expectLater(answer, throwsUnimplementedError);
    await expectLater(
      throwing.videos('猫', page: 1, filters: const SearchFilters(), asOf: now),
      throwsUnimplementedError,
    );
  });
}
