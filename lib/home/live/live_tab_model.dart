import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../live/live_api.dart';
import '../feed_model.dart' show feedLogFields, requestFailureMessage;

/// One area's rooms (推荐's come from the feed), a page at a time.
class _AreaList {
  List<LiveCard> cards = const [];
  int page = 0;
  bool hasMore = true;
  bool answered = false;
  String? error;
  Future<void>? out;
  int outPage = 0;

  /// Bumped by a refresh, so a page asked before it is dropped.
  int generation = 0;
}

/// 首页's 直播 (205): the feed's carousel, 我的关注 strip and area tabs, and the rooms of the area chosen. Each list has
/// one call out at a time; a page that adds no room ends it, and a failure waits for 重试, so nothing loops.
class LiveTabModel extends ChangeNotifier {
  LiveTabModel({required this._api, Logger? logger}) : _logger = logger ?? Logger.shared;

  final LiveApi _api;
  final Logger _logger;

  List<LiveBigCard> get bigCards => _bigCards;
  List<LiveBigCard> _bigCards = const [];

  List<LiveCard> get following => _following;
  List<LiveCard> _following = const [];

  int get followingTotal => _followingTotal;
  int _followingTotal = 0;

  /// 推荐 first, then the feed's areas.
  List<LiveArea> get areas => _areas;
  List<LiveArea> _areas = const [LiveArea.recommend];

  LiveArea get selected => _selected;
  LiveArea _selected = LiveArea.recommend;

  final _lists = <(int, int), _AreaList>{};

  _AreaList _list(LiveArea area) => _lists.putIfAbsent((area.id, area.parentId), _AreaList.new);
  _AreaList get _recommend => _list(LiveArea.recommend);
  _AreaList get _shown => _list(_selected);

  /// The rooms of the area chosen.
  List<LiveCard> get cards => _shown.cards;

  bool get started => _started;
  bool _started = false;

  /// The feed has answered once: the page's top is known.
  bool get fed => _recommend.answered;

  /// The feed's first page is out with nothing shown.
  bool get loadingFirst => !fed && _recommend.out != null;

  /// Why the feed's first page failed while nothing shows.
  String? get error => fed ? null : _recommend.error;

  /// The area chosen is asking its first page.
  bool get areaLoading => fed && _shown.cards.isEmpty && _shown.out != null;

  /// The next page of the area chosen is out, under its rooms.
  bool get loadingMore => _shown.out != null && _shown.outPage > 1;

  /// Why the area chosen stopped: its first page or a later one.
  String? get listError => fed ? _shown.error : null;

  bool get exhausted => _shown.answered && !_shown.hasMore && _shown.out == null && _shown.error == null;

  bool get canLoadMore =>
      _shown.cards.isNotEmpty && _shown.hasMore && _shown.error == null && _shown.out == null && _refreshing == null;

  Future<String?>? _refreshing;
  bool get refreshing => _refreshing != null;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The feed's first page, once.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_fetch(LiveArea.recommend, 1));
  }

  /// Another area: its first page unless it has one already.
  void select(LiveArea area) {
    if (area.id == _selected.id && area.parentId == _selected.parentId) return;
    _selected = area;
    final list = _shown;
    if (fed && !list.answered && list.out == null && list.error == null) unawaited(_fetch(area, 1));
    _changed();
  }

  /// The feed's first page again, then the area chosen's if it isn't 推荐; the other areas ask again when chosen.
  /// Completes with why it failed while rooms stay on screen, for a toast.
  Future<String?> refresh() {
    _started = true;
    if (_refreshing case final running?) return running;
    final first = _recommend;
    if (!first.answered && first.out != null) return first.out!.then((_) => null);
    return _refreshing = _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _refresh() async {
    final first = _recommend;
    first.generation++;
    for (var out = first.out; out != null; out = first.out) {
      await out;
    }
    if (_disposed) return null;
    final failure = await _fetch(LiveArea.recommend, 1);
    if (failure != null || _disposed || !fed) return failure;
    final area = _selected;
    _lists.removeWhere((key, _) => key != (0, 0) && key != (area.id, area.parentId));
    if (area.isRecommend) return null;
    final list = _shown;
    list.generation++;
    for (var out = list.out; out != null; out = list.out) {
      await out;
    }
    if (_disposed || !identical(list, _list(area))) return null;
    return _fetch(area, 1);
  }

  Future<void> loadMore() async {
    if (!canLoadMore) return;
    await _fetch(_selected, _shown.page + 1);
  }

  /// 重试: the feed if it never answered, else the area chosen's first page or the one that failed.
  Future<void> retry() async {
    if (_refreshing != null) return;
    if (!fed) {
      if (_recommend.out == null) await _fetch(LiveArea.recommend, 1);
      return;
    }
    final list = _shown;
    if (list.out != null) return;
    await _fetch(_selected, list.cards.isEmpty ? 1 : list.page + 1);
  }

  Future<String?> _fetch(LiveArea area, int page) async {
    final list = _list(area);
    final generation = list.generation;
    final done = Completer<void>();
    list
      ..out = done.future
      ..outPage = page
      ..error = null;
    _changed();
    try {
      final List<LiveCard> answered;
      final bool hasMore;
      if (area.isRecommend) {
        final answer = await _api.feed(page: page);
        if (generation != list.generation || _disposed) return null;
        if (page == 1) _takeTop(answer);
        answered = answer.cards;
        hasMore = answer.hasMore;
      } else {
        final answer = await _api.area(area, page: page);
        if (generation != list.generation || _disposed) return null;
        answered = answer.cards;
        hasMore = answer.hasMore;
      }
      final seen = page == 1 ? <int>{} : {for (final card in list.cards) card.roomId};
      final fresh = [
        for (final card in answered)
          if (seen.add(card.roomId)) card,
      ];
      list
        ..cards = page == 1 ? fresh : [...list.cards, ...fresh]
        ..page = page
        ..answered = true
        // A page that adds nothing ends the list, so an answer repeating itself can't keep it asking.
        ..hasMore = hasMore && fresh.isNotEmpty;
      return null;
    } catch (error) {
      _logger.warn(LogCategory.ui, 'live tab page failed', {...feedLogFields(error), 'area': area.id, 'page': page});
      if (generation != list.generation || _disposed) return null;
      final message = requestFailureMessage(error);
      final shown = area.isRecommend ? fed : list.cards.isNotEmpty;
      if (page == 1 && shown) return message;
      list.error = message;
      return null;
    } finally {
      list.out = null;
      done.complete();
      _changed();
    }
  }

  void _takeTop(LiveFeedPage answer) {
    _bigCards = answer.bigCards;
    _following = answer.following;
    _followingTotal = answer.followingTotal;
    final areas = [LiveArea.recommend, ...answer.areas.where((area) => !area.isRecommend)];
    _areas = areas;
    // An area the new feed no longer offers leaves for 推荐.
    if (!areas.any((area) => area.id == _selected.id && area.parentId == _selected.parentId)) {
      _selected = LiveArea.recommend;
    }
  }
}
