import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../home/feed_model.dart' show requestFailureMessage;
import '../search/results/video_row.dart' show searchLogReason;
import '../space/follow_book.dart';
import '../video/actions/actions_model.dart' show ActionsModel;
import 'friends_api.dart';
import 'friends_route.dart';

/// One of the page's lists, its rows so far, pages answered and the call out.
final class RelationLane {
  const RelationLane({
    this.users = const [],
    this.page = 0,
    this.total = 0,
    this.hasMore = true,
    this.loading = false,
    this.error,
  });

  final List<RelationUser> users;

  /// Pages answered; the next asked is one more.
  final int page;

  /// The whole list's size as the first answer counted it (我的关注 14人).
  final int total;
  final bool hasMore;
  final bool loading;

  /// Why the last call failed, in the user's words.
  final String? error;

  bool get loaded => page > 0;
  bool get canLoadMore => loaded && hasMore && !loading && error == null;

  RelationLane copyWith({bool? loading, String? error}) => RelationLane(
    users: users,
    page: page,
    total: total,
    hasMore: hasMore,
    loading: loading ?? this.loading,
    error: error,
  );

  /// [answer] under the rows, without anyone already there (a follow between pages shifts them). A page that adds
  /// nobody ends the lane, so nothing asks on and on.
  RelationLane appended(RelationPage answer, int page) {
    final seen = {for (final user in users) user.mid};
    final added = [
      for (final user in answer.users)
        if (seen.add(user.mid)) user,
    ];
    return RelationLane(
      users: [...users, ...added],
      page: page,
      total: this.page == 0 ? answer.total : total,
      hasMore: answer.hasMore && added.isNotEmpty,
    );
  }
}

/// 我的好友 (163-168): the followings in the chosen order and 搜索我的关注's results, the fans once their tab shows, and
/// 关注 changed from either.
///
/// The order is 最近关注 or 最近访问, a tap swapping them. The search goes once typing pauses for [searchPause], one
/// call at a time: text that changes while one is out waits for its answer, which is dropped, and then only the latest
/// text goes. The text is never logged.
///
/// A row reads followed as [isFollowing] says: a change still out, else [FollowBook]'s (so a space's 关注 shows here
/// too), else the list's answer. Nothing is asked until [mid] answers; [start] runs again once the account is known.
class FriendsModel extends ChangeNotifier {
  FriendsModel({
    required this._api,
    required this.mid,
    required this._book,
    required this._toast,
    required this._requestLogin,
    this.searchPause = const Duration(milliseconds: 300),
    Logger? logger,
  }) : _logger = logger ?? Logger.shared;

  final FriendsApi _api;

  /// The account's, read as each call goes out; null while the account is unknown or logged out.
  final int? Function() mid;
  final FollowBook _book;
  final void Function(String message) _toast;
  final VoidCallback _requestLogin;
  final Duration searchPause;
  final Logger _logger;

  FollowingOrder _order = FollowingOrder.recent;
  RelationLane _following = const RelationLane();
  RelationLane _results = const RelationLane();
  RelationLane _fans = const RelationLane();
  bool _started = false;
  bool _fansWanted = false;
  bool _disposed = false;

  /// Bumped when a list must start again (the order changed, the account left), so an answer for the old one is
  /// dropped.
  int _followingRound = 0;
  int _fansRound = 0;

  String _typed = '';
  String _query = '';
  Timer? _pauseTimer;
  bool _searchOut = false;
  bool _searchAgain = false;

  /// 关注 changes still out, by mid: what the row shows meanwhile.
  final _pending = <int, bool>{};
  List<RelationTag>? _groups;

  FollowingOrder get order => _order;
  RelationLane get following => _following;
  RelationLane get results => _results;
  RelationLane get fans => _fans;

  /// A search is showing: the field had text and its pause has passed.
  bool get searching => _query.isNotEmpty;

  /// The list [tab] shows.
  RelationLane lane(FriendsTab tab) => switch (tab) {
    FriendsTab.following => searching ? _results : _following,
    FriendsTab.fans => _fans,
  };

  bool isFollowing(RelationUser user) => _pending[user.mid] ?? _book.following(user.mid) ?? user.following;

  /// A 关注 change for [user] is out.
  bool isBusy(RelationUser user) => _pending.containsKey(user.mid);

  /// The followings, any search typed meanwhile and the fans if their tab has shown, once there is a mid; again after
  /// [signOut].
  void start() {
    if (_disposed || _started || mid() == null) return;
    _started = true;
    unawaited(_loadFollowing());
    if (_fansWanted) unawaited(_loadFans());
    if (_typed.isNotEmpty) _askSearch();
  }

  /// 粉丝 showed: its first page, once.
  void showFans() {
    if (_disposed) return;
    _fansWanted = true;
    if (_started && !_fans.loaded && !_fans.loading && _fans.error == null) unawaited(_loadFans());
  }

  /// The account left: everything shown goes, and the next [start] begins again. The field's text stays.
  void signOut() {
    if (_disposed || !_started) return;
    _started = false;
    _followingRound++;
    _fansRound++;
    _following = const RelationLane();
    _results = const RelationLane();
    _fans = const RelationLane();
    _query = '';
    _searchAgain = false;
    _pending.clear();
    _groups = null;
    _notify();
  }

  /// 最近关注 ⇄ 最近访问, reloading the list from its first page.
  void toggleOrder() {
    if (_disposed) return;
    _order = _order == FollowingOrder.mostVisited ? FollowingOrder.recent : FollowingOrder.mostVisited;
    _followingRound++;
    _following = const RelationLane();
    _notify();
    if (_started) unawaited(_loadFollowing());
  }

  Future<void> _loadFollowing() async {
    final mid = this.mid();
    if (mid == null || _following.loading) return;
    final round = _followingRound;
    final order = _order;
    final page = _following.page + 1;
    _following = _following.copyWith(loading: true);
    _notify();
    try {
      final answer = await _api.followings(mid, order: order, page: page);
      if (_disposed || round != _followingRound) return;
      _following = _following.appended(answer, page);
    } catch (error) {
      if (_disposed || round != _followingRound) return;
      _logger.warn(LogCategory.ui, 'friends following failed', {
        'order': order.name,
        'page': page,
        'error': searchLogReason(error),
      });
      _following = _following.copyWith(loading: false, error: requestFailureMessage(error));
    }
    _notify();
  }

  Future<void> _loadFans() async {
    final mid = this.mid();
    if (mid == null || _fans.loading) return;
    final round = _fansRound;
    final page = _fans.page + 1;
    _fans = _fans.copyWith(loading: true);
    _notify();
    try {
      final answer = await _api.fans(mid, page: page);
      if (_disposed || round != _fansRound) return;
      _fans = _fans.appended(answer, page);
    } catch (error) {
      if (_disposed || round != _fansRound) return;
      _logger.warn(LogCategory.ui, 'friends fans failed', {'page': page, 'error': searchLogReason(error)});
      _fans = _fans.copyWith(loading: false, error: requestFailureMessage(error));
    }
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
      _results = const RelationLane();
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
    if (_disposed || _typed.isEmpty || !_started) return;
    if (_searchOut) {
      _searchAgain = true;
      return;
    }
    _query = _typed;
    _results = const RelationLane();
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
        _results = _results.appended(answer, page);
        _notify();
      }
    } catch (error) {
      if (current()) {
        _logger.warn(LogCategory.ui, 'friends search failed', {'page': page, 'error': searchLogReason(error)});
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

  /// [tab]'s next page, once its last answered; nothing while one is out, after a failure or at the end.
  void loadMore(FriendsTab tab) {
    if (_disposed || !lane(tab).canLoadMore) return;
    switch (tab) {
      case FriendsTab.fans:
        unawaited(_loadFans());
      case FriendsTab.following when searching:
        if (!_searchOut) unawaited(_search());
      case FriendsTab.following:
        unawaited(_loadFollowing());
    }
  }

  /// Asks again for what failed in [tab]: its first page or its next.
  void retry(FriendsTab tab) {
    final shown = lane(tab);
    if (_disposed || mid() == null || shown.error == null || shown.loading) return;
    switch (tab) {
      case FriendsTab.fans:
        _fans = _fans.copyWith();
        unawaited(_loadFans());
      case FriendsTab.following when searching:
        if (_searchOut) return;
        _results = _results.copyWith();
        unawaited(_search());
      case FriendsTab.following:
        _following = _following.copyWith();
        unawaited(_loadFollowing());
    }
  }

  /// 关注 (the pink pill) or 取消关注 (166). The row shows the change at once and takes it back if Bilibili refuses;
  /// one call per person at a time. Accepted, it goes to [FollowBook] for every page.
  Future<void> setFollowing(RelationUser user, {required bool on}) async {
    final mid = user.mid;
    if (_disposed || _pending.containsKey(mid)) return;
    _pending[mid] = on;
    _notify();
    try {
      await _api.follow(mid, on: on);
      _book.changed(mid, following: on);
      if (!_disposed) _toast(on ? '关注成功' : '取消关注成功');
    } catch (error) {
      _logger.warn(LogCategory.api, 'friends follow failed', {'on': on, 'error': searchLogReason(error)});
      if (_disposed) return;
      if (error is BiliError && error.needsLogin) {
        _requestLogin();
      } else {
        _toast(ActionsModel.failureMessage(error));
      }
    } finally {
      _pending.remove(mid);
      _notify();
    }
  }

  /// The account's 分组, asked once a page and kept; a failure is asked again next time.
  Future<List<RelationTag>> groups() async => _groups ??= await _api.tags();

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
