import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../home/feed_model.dart' show requestFailureMessage;
import 'search_api.dart';
import 'search_filters.dart';
import 'search_history_store.dart';

/// What the page shows under the field: the empty page (52-54), suggestions (55), or results (56-61).
enum SearchStage { home, typing, results }

/// The result tabs built so far.
enum SearchTab {
  all('综合'),
  users('用户');

  const SearchTab(this.label);

  final String label;
}

/// One tab's rows. [loaded] is false until its first page has answered or failed.
@immutable
class SearchResults<T> {
  const SearchResults({
    this.items = const [],
    this.loading = false,
    this.error,
    this.exhausted = false,
    this.loaded = false,
    this.stalled = false,
  });

  final List<T> items;
  final bool loading;

  /// Why the last page failed, in words for the user.
  final String? error;
  final bool exhausted;
  final bool loaded;

  /// A load asked for its pages and none added a row (a 筛选 cut them all): nothing more is asked for by itself,
  /// only when the user asks ([SearchModel.loadMore] from the footer).
  final bool stalled;

  /// No results, as opposed to not asked yet or failed.
  bool get isEmpty => loaded && items.isEmpty && error == null && !loading;

  bool get canLoadMore => loaded && !loading && !exhausted && error == null && !stalled;
}

/// 搜索's state, one per search page.
///
/// Search calls go out one at a time, whatever asks for them: Bilibili answers -412 to a search sent too soon after
/// another, and it is KaiC's account. A page asked for while another is out waits its turn. If it goes stale first (a
/// new search, 筛选 changed) it is never sent; one already out is answered and dropped. Suggestions share that one
/// line: a page waits for a suggestion call that is out (whose answer a search then drops), and a suggestion waits
/// for a page that is out.
///
/// A page also goes no sooner than [searchGap] after the last page answered, so a load that asks on through pages
/// the 筛选 cut, or a user scrolling fast, doesn't send them back to back. A page asked for later than that, a new
/// search's first one included, goes at once. Suggestions neither wait for the gap nor start it.
class SearchModel extends ChangeNotifier {
  SearchModel({
    required this._api,
    required this.history,
    String? placeholder,
    this.debounce = const Duration(milliseconds: 300),
    this.searchGap = const Duration(milliseconds: 500),
    DateTime Function()? now,
    Logger? logger,
  }) : _placeholder = placeholder ?? '',
       _placeholderGiven = placeholder != null && placeholder.isNotEmpty,
       _now = now ?? DateTime.now,
       _logger = logger ?? Logger.shared;

  /// Pages one load may ask for while each adds no row: 内容时长's 60-120 and 120+ are cut on our side, so a page
  /// can lose every row. A load that adds none leaves the tab [SearchResults.stalled].
  static const pagesPerLoad = 3;

  final SearchApi _api;
  final SearchHistoryStore history;

  /// How long typing must pause before suggestions are asked for.
  final Duration debounce;

  /// The least time between one page answering and the next being sent.
  final Duration searchGap;

  final DateTime Function() _now;
  final Logger _logger;
  String _placeholder;
  final bool _placeholderGiven;
  SearchStage _stage = SearchStage.home;
  String _keyword = '';
  int _searches = 0;
  List<HotWord> _hotWords = const [];
  List<DiscoveryWord> _discovery = const [];
  List<SearchSuggestion> _suggestions = const [];
  SearchTab _tab = SearchTab.all;
  SearchFilters _filters = const SearchFilters();
  final _videos = _Lane<SearchVideo>(SearchTab.all);
  final _users = _Lane<SearchUser>(SearchTab.users);
  bool _disposed = false;

  /// The trimmed text suggestions are for.
  String _typed = '';
  Timer? _debounceTimer;
  bool _suggesting = false;
  bool _suggestAgain = false;
  Future<bool>? _discoveryLoad;

  final List<_Load> _queue = [];
  _Load? _running;

  /// When the last page answered; null once a rest for [searchGap] has run since.
  DateTime? _searchEnded;
  Timer? _gapTimer;
  Completer<void>? _rested;

  /// The moment 发布时间's window counts back from, fixed per search and 筛选 so every page asks the same window.
  DateTime? _asOf;
  bool _answered = false;

  /// The grey word in the empty field, which 搜索 searches; '' until known.
  String get placeholder => _placeholder;
  SearchStage get stage => _stage;

  /// The search the results are for.
  String get keyword => _keyword;

  /// Counts [search] calls, so the results can go back to the top when the same word is searched again.
  int get searches => _searches;
  List<HotWord> get hotWords => _hotWords;
  List<DiscoveryWord> get discovery => _discovery;
  List<SearchSuggestion> get suggestions => _suggestions;
  SearchTab get tab => _tab;
  SearchFilters get filters => _filters;
  SearchResults<SearchVideo> get videos => _videos.results;
  SearchResults<SearchUser> get users => _users.results;

  /// A new keyword whose first page hasn't answered yet: the official page shows only the loading TV under the field
  /// then, without the tab row (67). A 筛选 change or a tab switch doesn't count.
  bool get awaitingFirstPage => _stage == SearchStage.results && !_answered;

  /// 热搜, 搜索发现 and, without a placeholder, the default word, each on its own: one failing leaves its part empty.
  Future<void> loadHome() async {
    if (_disposed) return;
    await Future.wait([
      if (!_placeholderGiven)
        _homePart('default word', () async {
          final word = await _api.defaultWord();
          _placeholder = word ?? '';
        }),
      _homePart('hot words', () async {
        _hotWords = await _api.hotWords();
      }),
      refreshDiscovery(),
    ]);
  }

  /// 搜索发现's ↻; a press while it is being asked for waits for that answer. A failure keeps the words shown.
  /// False when it failed, for the page to say so.
  Future<bool> refreshDiscovery() {
    if (_disposed) return Future.value(false);
    return _discoveryLoad ??= _homePart('discovery', () async {
      _discovery = await _api.discovery();
    }).whenComplete(() => _discoveryLoad = null);
  }

  Future<bool> _homePart(String part, Future<void> Function() load) async {
    try {
      await load();
    } catch (error) {
      if (_disposed) return false;
      _logger.warn(LogCategory.ui, 'search home part failed', {'part': part, 'error': _reason(error)});
      return false;
    }
    _notify();
    return true;
  }

  /// The user edited the field: empty goes back to the empty page, anything else to suggestions, asked for once
  /// typing pauses for [debounce]. Not for text the page puts in the field itself.
  void textChanged(String text) {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final term = text.trim();
    _typed = term;
    if (term.isEmpty) {
      if (_stage == SearchStage.home && _suggestions.isEmpty) return;
      _stage = SearchStage.home;
      _suggestions = const [];
      _notify();
      return;
    }
    if (_stage != SearchStage.typing) {
      _stage = SearchStage.typing;
      _notify();
    }
    _debounceTimer = Timer(debounce, _askSuggestions);
  }

  bool get _callOut => _suggesting || _running != null;

  void _askSuggestions() {
    _debounceTimer = null;
    if (_disposed || _stage != SearchStage.typing || _typed.isEmpty) return;
    if (_callOut) {
      _suggestAgain = true;
      return;
    }
    _sendSuggestions();
  }

  void _sendSuggestions() {
    final term = _typed;
    _suggesting = true;
    unawaited(
      Future.sync(() => _api.suggestions(term))
          .then(
            (list) {
              // An answer for text that has changed since is dropped; the newer text's own is on its way.
              if (_disposed || _stage != SearchStage.typing || term != _typed) return;
              _suggestions = list;
              _notify();
            },
            onError: (Object error) {
              if (_disposed) return;
              _logger.warn(LogCategory.ui, 'search suggestions failed', {'error': _reason(error)});
            },
          )
          .whenComplete(() {
            _suggesting = false;
            _next();
          }),
    );
  }

  /// Sends whatever waits once nothing is out: suggestions asked for meanwhile first, then pages.
  void _next() {
    if (_disposed || _callOut) return;
    if (_suggestAgain) {
      _suggestAgain = false;
      if (_stage == SearchStage.typing && _typed.isNotEmpty) {
        _sendSuggestions();
        return;
      }
    }
    _pump();
  }

  /// Records [keyword] in history and shows its results from the first page, 综合 first.
  void search(String keyword) {
    if (_disposed) return;
    final word = keyword.trim();
    if (word.isEmpty) return;
    _searches++;
    history.add(word);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _suggestAgain = false;
    _keyword = word;
    _typed = word;
    _asOf = _now();
    _stage = SearchStage.results;
    _suggestions = const [];
    _tab = SearchTab.all;
    _answered = false;
    _reset(_videos);
    _reset(_users);
    _notify();
    unawaited(_request(_videos));
  }

  /// Shows [tab], asking for its first page if it hasn't been.
  void selectTab(SearchTab tab) {
    if (_disposed || tab == _tab) return;
    _tab = tab;
    _notify();
    final lane = _lane(tab);
    if (!lane.results.loaded && lane.pending == null) unawaited(_request(lane));
  }

  /// 筛选 changed: 综合 again from its first page.
  void setFilters(SearchFilters filters) {
    if (_disposed || filters == _filters) return;
    _filters = filters;
    _asOf = _now();
    _reset(_videos);
    _notify();
    if (_tab == SearchTab.all) unawaited(_request(_videos));
  }

  /// The shown tab's next page. While one is waiting or out this is that one; after a failure (that is [retry]'s) or
  /// at the end, nothing. It asks even while the tab is [SearchResults.stalled]: that is the footer's 加载更多.
  Future<void> loadMore() {
    final lane = _lane(_tab);
    if (lane.results.error != null) return Future.value();
    return _request(lane);
  }

  /// The shown tab's failed page again.
  Future<void> retry() => _request(_lane(_tab));

  /// 关注 pressed on a 用户 row: the row shows [following] at once.
  void setFollowing(int mid, {required bool following}) {
    if (_disposed) return;
    final now = _users.results;
    final index = now.items.indexWhere((user) => user.mid == mid);
    if (index < 0 || now.items[index].following == following) return;
    _users.results = SearchResults(
      items: [...now.items]..[index] = _withFollowing(now.items[index], following: following),
      loading: now.loading,
      error: now.error,
      exhausted: now.exhausted,
      loaded: now.loaded,
      stalled: now.stalled,
    );
    _notify();
  }

  static SearchUser _withFollowing(SearchUser user, {required bool following}) => SearchUser(
    mid: user.mid,
    name: user.name,
    face: user.face,
    fans: user.fans,
    videos: user.videos,
    level: user.level,
    sign: user.sign,
    officialType: user.officialType,
    officialDesc: user.officialDesc,
    following: following,
  );

  _Lane<Object> _lane(SearchTab tab) => switch (tab) {
    SearchTab.all => _videos,
    SearchTab.users => _users,
  };

  /// Empties [lane] for a new search or new 筛选; a page of it already out is dropped when it answers.
  void _reset(_Lane<Object> lane) {
    lane.reset();
    final pending = lane.pending;
    lane.pending = null;
    if (pending != null && _queue.remove(pending)) pending.finish();
  }

  Future<void> _request(_Lane<Object> lane) {
    if (_disposed || _keyword.isEmpty) return Future.value();
    final pending = lane.pending;
    if (pending != null) return pending.done.future;
    final now = lane.results;
    if (now.exhausted) return Future.value();
    final load = _Load(lane.tab, lane.generation);
    lane
      ..pending = load
      ..start();
    _queue.add(load);
    _notify();
    _pump();
    return load.done.future;
  }

  /// Sends the next waiting page, the shown tab's first, if no call is out and the gap since the last page is over.
  void _pump() {
    if (_disposed || _callOut || _queue.isEmpty || _rested != null) return;
    final wait = _gapLeft();
    if (wait > Duration.zero) {
      unawaited(_rest(wait).then((_) => _next()));
      return;
    }
    final load = _queue.firstWhere((each) => each.tab == _tab, orElse: () => _queue.first);
    _queue.remove(load);
    _running = load;
    final keyword = _keyword;
    final asOf = _asOf ?? _now();
    final run = switch (load.tab) {
      SearchTab.all => _run(
        load,
        _videos,
        (page, filters) => _api.videos(keyword, page: page, filters: filters, asOf: asOf),
        (video, filters) => filters.length.admits(video.duration),
        (video) => video.bvid,
      ),
      SearchTab.users => _run(
        load,
        _users,
        (page, _) => _api.users(keyword, page: page),
        (_, _) => true,
        (user) => user.mid,
      ),
    };
    unawaited(
      run.whenComplete(() {
        _running = null;
        final lane = _lane(load.tab);
        if (identical(lane.pending, load)) lane.pending = null;
        load.finish();
        _next();
      }),
    );
  }

  Duration _gapLeft() {
    final ended = _searchEnded;
    if (ended == null) return Duration.zero;
    final wait = searchGap - _now().difference(ended);
    // A clock set back would otherwise stretch the wait by as much.
    return wait > searchGap ? searchGap : wait;
  }

  /// Once a rest has run the gap counts as served, whatever the clock says: in widget tests the timer runs on fake
  /// time while [_now] may be the real clock.
  Future<void> _rest(Duration wait) {
    final rested = Completer<void>();
    _rested = rested;
    _gapTimer = Timer(wait, _endRest);
    return rested.future;
  }

  void _endRest() {
    _gapTimer?.cancel();
    _gapTimer = null;
    _searchEnded = null;
    final rested = _rested;
    _rested = null;
    rested?.complete();
  }

  /// Asks for [lane]'s next page, and on while a page adds no row and more remain, up to [pagesPerLoad]. Rows already
  /// shown are skipped, as are rows [admits] refuses. A load that adds no row though more remain stalls the tab.
  Future<void> _run<T>(
    _Load load,
    _Lane<T> lane,
    Future<SearchPage<T>> Function(int page, SearchFilters filters) fetch,
    bool Function(T row, SearchFilters filters) admits,
    Object Function(T row) key,
  ) async {
    final filters = _filters;
    bool current() => !_disposed && lane.generation == load.generation;
    final seen = {for (final row in lane.results.items) key(row)};
    var number = lane.page + 1;
    try {
      var added = <T>[];
      var more = true;
      for (var asked = 0; asked < pagesPerLoad && added.isEmpty && more; asked++) {
        if (asked > 0) {
          final wait = _gapLeft();
          if (wait > Duration.zero) {
            await _rest(wait);
            if (!current()) return;
          }
        }
        number = lane.page + 1;
        final SearchPage<T> page;
        try {
          page = await fetch(number, filters);
        } finally {
          _searchEnded = _now();
        }
        if (!current()) return;
        lane.page = number;
        more = page.hasMore;
        added = [
          for (final row in page.items)
            if (admits(row, filters) && seen.add(key(row))) row,
        ];
        _logger.info(LogCategory.ui, 'search page', {
          'tab': load.tab.name,
          'page': number,
          'pages': page.pages,
          'got': page.items.length,
          'added': added.length,
          if (!filters.isDefault && load.tab == SearchTab.all)
            'filters': '${filters.order.name}/${filters.published.name}/${filters.length.name}',
        });
      }
      lane.results = SearchResults(
        items: [...lane.results.items, ...added],
        exhausted: !more,
        loaded: true,
        stalled: added.isEmpty && more,
      );
      _answered = true;
    } catch (error) {
      if (!current()) return;
      _logger.warn(LogCategory.ui, 'search page failed', {
        'tab': load.tab.name,
        'page': number,
        'error': _reason(error),
      });
      lane.results = SearchResults(items: lane.results.items, error: requestFailureMessage(error), loaded: true);
      _answered = true;
    }
    _notify();
  }

  /// The error without anything that might quote the request: a failed request's text can carry its URL, whose
  /// query is what the user typed, and a decoding error can quote the answer.
  static String _reason(Object error) => switch (error) {
    BiliHTTPError(:final status) => 'http $status',
    BiliAPIError(:final code) => 'api $code',
    _ => '${error.runtimeType}',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _endRest();
    for (final load in _queue) {
      load.finish();
    }
    _queue.clear();
    super.dispose();
  }
}

/// A tab's rows and paging; [generation] counts its resets, so a page asked for before one is dropped.
class _Lane<T> {
  _Lane(this.tab);

  final SearchTab tab;
  SearchResults<T> results = SearchResults<T>();
  int generation = 0;

  /// The last page answered.
  int page = 0;

  /// This generation's page, waiting or out.
  _Load? pending;

  void reset() {
    generation += 1;
    page = 0;
    results = SearchResults<T>();
  }

  /// The rows stay while the next page loads; a failure's message gives way to the spinner.
  void start() => results = SearchResults<T>(items: results.items, loading: true, loaded: results.loaded);
}

class _Load {
  _Load(this.tab, this.generation);

  final SearchTab tab;
  final int generation;
  final done = Completer<void>();

  void finish() {
    if (!done.isCompleted) done.complete();
  }
}
