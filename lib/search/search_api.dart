import 'package:bili_core/api.dart';
import 'package:flutter/foundation.dart';

import 'search_filters.dart';

/// 搜索's calls. Following and 稍后再看 go through `PageApi`, as on the video page.
abstract interface class SearchApi {
  Future<String?> defaultWord();

  Future<List<HotWord>> hotWords();

  Future<List<DiscoveryWord>> discovery();

  Future<List<SearchSuggestion>> suggestions(String term);

  /// 综合: the mixed search with default [filters], the video search otherwise. 发布时间's window ends at [asOf], which
  /// the caller keeps the same for every page of one search and 筛选, so a later page doesn't ask a shifted window.
  Future<SearchPage<SearchVideo>> videos(
    String keyword, {
    required int page,
    required SearchFilters filters,
    required DateTime asOf,
  });

  Future<SearchPage<SearchUser>> users(String keyword, {required int page});
}

typedef VideoSearchCall = Future<SearchPage<SearchVideo>> Function({
  required String keyword,
  int page,
  SearchOrder order,
  SearchDuration duration,
  DateTime? publishedFrom,
  DateTime? publishedTo,
});

/// [BiliClient]'s search calls as they are, so tests can answer them in its place.
@visibleForTesting
final class SearchCalls {
  const SearchCalls({
    required this.riskCookies,
    required this.defaultWord,
    required this.hotWords,
    required this.discovery,
    required this.suggestions,
    required this.all,
    required this.videos,
    required this.users,
  });

  SearchCalls.of(BiliClient client)
    : riskCookies = client.ensureRiskCookies,
      defaultWord = client.searchDefaultWord,
      hotWords = client.hotWords,
      discovery = client.discoveryWords,
      suggestions = client.searchSuggestions,
      all = client.searchAll,
      videos = client.searchVideos,
      users = client.searchUsers;

  /// The website's fingerprint cookies. The web search answers -412 without them, in its JSON, which the client's
  /// retry on HTTP 412 never sees.
  final Future<void> Function() riskCookies;
  final Future<String?> Function() defaultWord;
  final Future<List<HotWord>> Function() hotWords;
  final Future<List<DiscoveryWord>> Function() discovery;
  final Future<List<SearchSuggestion>> Function(String term) suggestions;
  final Future<SearchPage<SearchVideo>> Function({required String keyword, int page}) all;
  final VideoSearchCall videos;
  final Future<SearchPage<SearchUser>> Function({required String keyword, int page}) users;
}

class ClientSearchApi implements SearchApi {
  ClientSearchApi(BiliClient client) : this.calls(SearchCalls.of(client));

  @visibleForTesting
  ClientSearchApi.calls(this._calls);

  final SearchCalls _calls;

  // Every call is async, so one that throws before its request still fails as a future.

  @override
  Future<String?> defaultWord() async {
    await _calls.riskCookies();
    return _calls.defaultWord();
  }

  @override
  Future<List<HotWord>> hotWords() async => _calls.hotWords();

  @override
  Future<List<DiscoveryWord>> discovery() async => _calls.discovery();

  @override
  Future<List<SearchSuggestion>> suggestions(String term) async => _calls.suggestions(term);

  @override
  Future<SearchPage<SearchVideo>> videos(
    String keyword, {
    required int page,
    required SearchFilters filters,
    required DateTime asOf,
  }) async {
    await _calls.riskCookies();
    if (filters.isDefault) return _calls.all(keyword: keyword, page: page);
    final within = filters.published.within;
    return _calls.videos(
      keyword: keyword,
      page: page,
      order: filters.order.order,
      duration: filters.length.duration,
      publishedFrom: within == null ? null : asOf.subtract(within),
      publishedTo: within == null ? null : asOf,
    );
  }

  @override
  Future<SearchPage<SearchUser>> users(String keyword, {required int page}) async {
    await _calls.riskCookies();
    return _calls.users(keyword: keyword, page: page);
  }
}
