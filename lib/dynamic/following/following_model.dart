import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../home/feed_model.dart' show requestFailureMessage;
import '../dynamic_api.dart';

/// One list on the page, the account's followings or a search's: its rows so far, pages loaded, and the call out.
final class FollowingLane {
  const FollowingLane({this.users = const [], this.page = 0, this.hasMore = true, this.loading = false, this.error});

  final List<FollowingUser> users;

  /// Pages answered; the next asked is one more.
  final int page;
  final bool hasMore;
  final bool loading;

  /// Why the last call failed, in the user's words.
  final String? error;

  bool get loaded => page > 0;

  /// The first page is out, or waits for its turn.
  bool get firstLoading => !loaded && error == null;
  bool get canLoadMore => loaded && hasMore && !loading && error == null;

  FollowingLane copyWith({List<FollowingUser>? users, int? page, bool? hasMore, bool? loading, String? error}) =>
      FollowingLane(
        users: users ?? this.users,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        error: error,
      );
}

/// 我的关注 (129, 130): the account's followings in the chosen order, paged, and 搜索我的关注's results.
///
/// The search goes once typing pauses for [searchPause], and one search call at a time: text that changes while one is
/// out waits for its answer, which is dropped, and then only the latest text goes. The text is never logged. The pink
/// dots come from one [DynamicApi.ups] call when the lists start.
///
/// Nothing is asked until [mid] answers: the page can open while the launch's account check is still out, and calls
/// [start] again once the account is known.
class FollowingListModel extends ChangeNotifier {
  FollowingListModel({
    required this._api,
    required this.mid,
    this.searchPause = const Duration(milliseconds: 300),
    Logger? logger,
  }) : _logger = logger ?? Logger.shared;

  final DynamicApi _api;

  /// The account's, read as each call goes out; null while the account is unknown or logged out.
  final int? Function() mid;
  final Duration searchPause;
  final Logger _logger;

  FollowingOrder _order = FollowingOrder.recommended;
  FollowingLane _list = const FollowingLane();
  FollowingLane _results = const FollowingLane();
  Set<int> _updated = const {};
  bool _started = false;
  bool _disposed = false;

  /// Bumped when the order changes or the account leaves, so an answer for the old list is dropped.
  int _listRound = 0;

  /// Bumped when the account leaves, so the dots asked for it are dropped.
  int _session = 0;

  /// The trimmed text in the field, and the text [results] are for ('' while the list shows).
  String _typed = '';
  String _query = '';
  Timer? _pauseTimer;
  bool _searchOut = false;

  /// Text changed while a search was out: the latest goes once it answers.
  bool _searchAgain = false;

  FollowingOrder get order => _order;
  FollowingLane get list => _list;
  FollowingLane get results => _results;

  /// A search is showing: the field had text and its pause has passed.
  bool get searching => _query.isNotEmpty;

  /// The lane on screen.
  FollowingLane get shown => searching ? _results : _list;

  /// Whether [user] has posts the account hasn't seen: the pink dot.
  bool hasUpdate(int user) => _updated.contains(user);

  /// The first page, the dots and any search typed meanwhile, once there is a mid; again after [signOut]. Until then the
  /// list waits on its TV.
  void start() {
    if (_disposed || _started || mid() == null) return;
    _started = true;
    unawaited(_loadList());
    unawaited(_loadUpdates());
    if (_typed.isNotEmpty) _askSearch();
  }

  /// The account left: everything shown goes, and the next [start] begins again. The field's text stays.
  void signOut() {
    if (_disposed || !_started) return;
    _started = false;
    _listRound++;
    _session++;
    _list = const FollowingLane();
    _results = const FollowingLane();
    _query = '';
    _searchAgain = false;
    _updated = const {};
    _notify();
  }

  Future<void> _loadUpdates() async {
    final session = _session;
    try {
      final ups = await _api.ups();
      if (_disposed || session != _session) return;
      _updated = {
        for (final up in ups.ups)
          if (up.hasUpdate) up.mid,
      };
      _notify();
    } catch (error) {
      if (_disposed) return;
      _logger.warn(LogCategory.ui, 'following updates failed', {'error': _reason(error)});
    }
  }

  /// Reloads the list from its first page in [order]; the same order changes nothing.
  void setOrder(FollowingOrder order) {
    if (_disposed || order == _order) return;
    _order = order;
    _listRound++;
    _list = const FollowingLane();
    _notify();
    if (_started) unawaited(_loadList());
  }

  Future<void> _loadList() async {
    final mid = this.mid();
    if (mid == null || _list.loading) return;
    final round = _listRound;
    final order = _order;
    final page = _list.page + 1;
    _list = _list.copyWith(loading: true);
    _notify();
    final FollowingPage answer;
    try {
      answer = await _api.followings(mid, order: order, page: page);
    } catch (error) {
      if (_disposed || round != _listRound) return;
      _logger.warn(LogCategory.ui, 'following list failed', {
        'order': order.name,
        'page': page,
        'error': _reason(error),
      });
      _list = _list.copyWith(loading: false, error: requestFailureMessage(error));
      _notify();
      return;
    }
    if (_disposed || round != _listRound) return;
    _list = _appended(_list, answer, page);
    _notify();
  }

  /// The field's text changed: empty shows the list again at once, anything else searches once typing pauses.
  void textChanged(String text) {
    if (_disposed) return;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    final term = text.trim();
    _typed = term;
    if (term.isEmpty) {
      _searchAgain = false;
      if (_query.isEmpty) return;
      _query = '';
      _results = const FollowingLane();
      _notify();
      return;
    }
    if (term == _query) return;
    _pauseTimer = Timer(searchPause, _askSearch);
  }

  /// The keyboard's 搜索: no need to wait for the pause.
  void submit() {
    if (_disposed || _typed.isEmpty) return;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    if (_typed != _query) _askSearch();
  }

  void _askSearch() {
    _pauseTimer = null;
    // Before the account is known the text waits for [start].
    if (_disposed || _typed.isEmpty || !_started) return;
    if (_searchOut) {
      _searchAgain = true;
      return;
    }
    _query = _typed;
    _results = const FollowingLane();
    _notify();
    unawaited(_search());
  }

  Future<void> _search() async {
    final mid = this.mid();
    if (mid == null || _searchOut) return;
    final query = _query;
    final page = _results.page + 1;
    _searchOut = true;
    _results = _results.copyWith(loading: true);
    _notify();
    // An answer for text that has changed since, or a search cleared, is dropped.
    bool current() => !_disposed && query == _query && !(_searchAgain && _typed.isNotEmpty && _typed != query);
    try {
      final answer = await _api.searchFollowings(mid, query, page: page);
      if (current()) {
        _results = _appended(_results, answer, page);
        _notify();
      }
    } catch (error) {
      if (current()) {
        _logger.warn(LogCategory.ui, 'following search failed', {'page': page, 'error': _reason(error)});
        _results = _results.copyWith(loading: false, error: requestFailureMessage(error));
        _notify();
      }
    } finally {
      _searchOut = false;
      if (!_disposed && _searchAgain) {
        _searchAgain = false;
        if (_typed.isNotEmpty && _typed != _query) _askSearch();
      }
    }
  }

  /// The shown lane's next page, once its last answered; nothing while one is out, after a failure or at the end.
  void loadMore() {
    if (_disposed || !shown.canLoadMore) return;
    if (searching) {
      if (!_searchOut) unawaited(_search());
    } else {
      unawaited(_loadList());
    }
  }

  /// Asks again for what failed: the shown lane's first page or its next.
  void retry() {
    if (_disposed || mid() == null || shown.error == null || shown.loading) return;
    if (searching) {
      if (_searchOut) return;
      _results = _results.copyWith();
      unawaited(_search());
    } else {
      _list = _list.copyWith();
      unawaited(_loadList());
    }
  }

  /// [answer] added under [lane]'s rows, without anyone already there (a follow between pages shifts them). A page
  /// that adds nobody ends the lane, so nothing asks on and on.
  static FollowingLane _appended(FollowingLane lane, FollowingPage answer, int page) {
    final seen = {for (final user in lane.users) user.mid};
    final added = [
      for (final user in answer.users)
        if (seen.add(user.mid)) user,
    ];
    return FollowingLane(users: [...lane.users, ...added], page: page, hasMore: answer.hasMore && added.isNotEmpty);
  }

  /// The error without anything that might quote the request: its URL carries the search's text.
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
    _pauseTimer?.cancel();
    _pauseTimer = null;
    super.dispose();
  }
}
