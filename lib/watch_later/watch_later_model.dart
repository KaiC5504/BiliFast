import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../home/feed_model.dart' show requestFailureMessage;
import '../video/video_route.dart';
import 'watch_later_api.dart';

/// 稍后再看 (85, 86, 95, 96): the chosen chip and order, the list a page at a time, the edit mode's choice, and the
/// calls that change the list.
///
/// One list call is out at a time: changing the chip or the order while one is out lets it finish, drops its answer
/// and then asks once for the latest choice. A failure waits for 重试, so nothing loops against the account.
class WatchLaterModel extends ChangeNotifier {
  WatchLaterModel({required this.api, required this.isLoggedIn, required this.accountMid, Logger? logger})
    : _logger = logger ?? Logger.shared;

  static const copied = '复制成功';
  static const moved = '移动成功';

  final WatchLaterApi api;
  final bool Function() isLoggedIn;

  /// The account's mid, which 复制到 names; null while it isn't known.
  final int? Function() accountMid;
  final Logger _logger;

  WatchLaterFilter _filter = WatchLaterFilter.all;
  bool _oldestFirst = false;
  List<WatchLaterItem> _items = const [];
  int _nextPage = 1;
  bool _hasMore = true;
  bool _loading = false;
  bool _refreshing = false;
  bool _loaded = false;
  bool _restartPending = false;

  /// The next call asks for page 1: the list started again, and the rows shown (kept through a pull) are the old ones.
  bool _fromTop = true;
  String? _error;
  bool _needsLogin = false;
  bool _editing = false;
  Set<int> _chosen = const {};

  /// Rows removed here: a page still in flight must not bring one back.
  final Set<int> _removed = {};

  /// Bumped whenever the list starts again, so an answer for the list before is dropped.
  int _generation = 0;
  bool _disposed = false;

  WatchLaterFilter get filter => _filter;
  bool get oldestFirst => _oldestFirst;
  List<WatchLaterItem> get items => _items;
  bool get hasMore => _hasMore;
  bool get loading => _loading;

  /// A pull to refresh is running; the rows shown stay until it answers.
  bool get refreshing => _refreshing;

  /// The first page of the current list has answered.
  bool get loaded => _loaded;

  /// Why the next page (or, with no rows, the first) failed.
  String? get error => _error;
  bool get needsLogin => _needsLogin;
  bool get editing => _editing;
  Set<int> get chosen => _chosen;
  bool get allChosen => _items.isNotEmpty && _items.every((item) => _chosen.contains(item.aid));

  /// 管理, the sort and 播放全部 work only on a list with rows.
  bool get hasRows => _items.isNotEmpty;
  bool get canLoadMore => !_loading && _hasMore && !_needsLogin && _error == null && _loaded;

  Future<void> start() async {
    if (!isLoggedIn()) {
      _needsLogin = true;
      _notify();
      return;
    }
    _load();
  }

  void selectFilter(WatchLaterFilter filter) {
    if (_editing || filter == _filter) return;
    _filter = filter;
    _restart();
  }

  void toggleOrder() {
    if (_editing || !hasRows) return;
    _oldestFirst = !_oldestFirst;
    _restart();
  }

  void loadMore() {
    if (!canLoadMore) return;
    _load();
  }

  void retry() {
    if (_loading) return;
    _error = null;
    _load();
  }

  /// Starts over, as on pull to refresh, after a login and after 一键清除 or 移动到; the rows shown stay until the
  /// first page answers. A failure then keeps them and comes back as words for a toast.
  Future<String?> reload() {
    _needsLogin = false;
    _refreshing = _items.isNotEmpty;
    final done = Completer<String?>();
    _reloads.add(done);
    _restart(keepRows: true);
    return done.future;
  }

  final List<Completer<String?>> _reloads = [];

  void _restart({bool keepRows = false}) {
    _generation++;
    _fromTop = true;
    if (!keepRows) {
      _items = const [];
      _refreshing = false;
      _nextPage = 1;
      _hasMore = true;
      _loaded = false;
    }
    _error = null;
    if (_loading) {
      _restartPending = true;
      _notify();
    } else {
      _load();
    }
  }

  void _load() {
    if (_loading) return;
    _loading = true;
    _error = null;
    _notify();
    unawaited(_fetch(_generation, _filter, _oldestFirst, _fromTop ? 1 : _nextPage));
  }

  Future<void> _fetch(int generation, WatchLaterFilter filter, bool oldestFirst, int page) async {
    final replacing = page == 1;
    try {
      final answer = await api.list(filter: filter, oldestFirst: oldestFirst, page: page);
      if (!_answered(generation)) return;
      final kept = replacing ? <WatchLaterItem>[] : [..._items];
      final seen = {for (final item in kept) item.aid, ..._removed};
      for (final item in answer.items) {
        if (seen.add(item.aid)) kept.add(item);
      }
      _items = kept;
      _fromTop = false;
      _nextPage = page + 1;
      _hasMore = answer.hasMore;
      _loaded = true;
      _refreshing = false;
      if (_editing) _chosen = _chosen.where((aid) => _items.any((item) => item.aid == aid)).toSet();
      _finishReloads(null);
    } catch (error) {
      if (!_answered(generation)) return;
      _logger.warn(LogCategory.ui, 'watch later failed', {'error': '${error.runtimeType}'});
      _refreshing = false;
      if (error is BiliError && error.needsLogin) {
        _loggedOut();
        _finishReloads(null);
      } else {
        final message = requestFailureMessage(error);
        if (replacing && _items.isNotEmpty && _reloads.isNotEmpty) {
          // A pull to refresh that failed keeps the rows, and paging goes on from where they end.
          _fromTop = false;
          _finishReloads(message);
        } else {
          if (replacing) _items = const [];
          _error = message;
          _finishReloads(null);
        }
      }
    }
    _notify();
  }

  void _finishReloads(String? message) {
    for (final done in _reloads) {
      done.complete(message);
    }
    _reloads.clear();
  }

  /// Ends the call that was out, and says whether its answer belongs to the list shown. When the list started again
  /// meanwhile, the answer is dropped and the new list's first page asked for.
  bool _answered(int generation) {
    if (_disposed) return false;
    _loading = false;
    if (generation == _generation) return true;
    if (_restartPending) {
      _restartPending = false;
      _load();
    }
    return false;
  }

  void signOut() {
    _generation++;
    _loading = false;
    _restartPending = false;
    _removed.clear();
    _loggedOut();
    _finishReloads(null);
    _notify();
  }

  void _loggedOut() {
    _needsLogin = true;
    _items = const [];
    _fromTop = true;
    _nextPage = 1;
    _hasMore = true;
    _loaded = false;
    _error = null;
    _editing = false;
    _chosen = const {};
  }

  void setEditing(bool on) {
    if (on && !hasRows) return;
    _editing = on;
    _chosen = const {};
    _notify();
  }

  void toggleChosen(WatchLaterItem item) {
    if (!_editing) return;
    final next = {..._chosen};
    if (!next.remove(item.aid)) next.add(item.aid);
    _chosen = next;
    _notify();
  }

  /// 全选: every row loaded so far, or none once they all are.
  void toggleAll() {
    if (!_editing) return;
    _chosen = allChosen ? const {} : {for (final item in _items) item.aid};
    _notify();
  }

  void clearChoice() {
    _chosen = const {};
    _notify();
  }

  /// ⋮'s 删除: the row goes at once; if the call fails it comes back where it was and the words for a toast are
  /// returned (null on success).
  Future<String?> remove(WatchLaterItem item) => _removeAll([item]);

  /// The edit bar's 删除: the chosen rows in one call, leaving edit mode.
  Future<String?> removeChosen() {
    final rows = [
      for (final item in _items)
        if (_chosen.contains(item.aid)) item,
    ];
    if (rows.isEmpty) return Future.value();
    _editing = false;
    _chosen = const {};
    return _removeAll(rows);
  }

  Future<String?> _removeAll(List<WatchLaterItem> rows) async {
    final before = _items;
    final aids = {for (final item in rows) item.aid};
    if (!before.any((item) => aids.contains(item.aid))) return null;
    _items = [
      for (final item in before)
        if (!aids.contains(item.aid)) item,
    ];
    _removed.addAll(aids);
    _notify();
    try {
      await api.remove(aids: aids.toList());
      return null;
    } catch (error) {
      _logger.warn(LogCategory.ui, 'watch later remove failed', {'error': '${error.runtimeType}'});
      _removed.removeAll(aids);
      if (_disposed) return null;
      if (error is BiliError && error.needsLogin) {
        _generation++;
        _loading = false;
        _loggedOut();
        _notify();
        return null;
      }
      // Put each back before the first row that followed it, or at the end.
      final restored = [..._items];
      for (final item in rows) {
        if (restored.any((row) => row.aid == item.aid)) continue;
        final at = before.indexWhere((row) => row.aid == item.aid);
        final after = before.skip(at + 1).map((row) => row.aid).toSet();
        final index = restored.indexWhere((row) => after.contains(row.aid));
        restored.insert(index < 0 ? restored.length : index, item);
      }
      _items = restored;
      _notify();
      return requestFailureMessage(error);
    }
  }

  /// 一键清除: the server clears, then the list starts over. Returns the words for a toast on failure.
  Future<String?> clear(WatchLaterClean kind) async {
    try {
      await api.clear(kind);
    } catch (error) {
      _logger.warn(LogCategory.ui, 'watch later clear failed', {'error': '${error.runtimeType}'});
      if (error is BiliError && error.needsLogin && !_disposed) {
        signOut();
        return null;
      }
      return requestFailureMessage(error);
    }
    if (!_disposed) unawaited(reload());
    return null;
  }

  /// 复制到 or 移动到 [folder] with the chosen rows. On success edit mode ends and the list starts over; returns the
  /// words for a toast either way.
  Future<String> sendChosen(FavFolder folder, {required bool move}) async {
    final aids = [
      for (final item in _items)
        if (_chosen.contains(item.aid)) item.aid,
    ];
    if (aids.isEmpty) return requestFailureMessage(StateError('nothing chosen'));
    try {
      if (move) {
        await api.moveToFolder(aids: aids, folderId: folder.id);
      } else {
        final mid = accountMid();
        if (mid == null) throw const BiliError.api(code: -101, message: '账号未登录');
        await api.copyToFolder(aids: aids, folderId: folder.id, mid: mid);
      }
    } catch (error) {
      _logger.warn(LogCategory.ui, 'watch later ${move ? 'move' : 'copy'} failed', {'error': '${error.runtimeType}'});
      return requestFailureMessage(error);
    }
    if (_disposed) return move ? moved : copied;
    _editing = false;
    _chosen = const {};
    unawaited(reload());
    return move ? moved : copied;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _finishReloads(null);
    super.dispose();
  }

  /// Opens at the progress, as 历史记录's rows do; a finished video (-1) starts from the beginning.
  static VideoRoute route(WatchLaterItem item) => VideoRoute(
    bvid: item.bvid,
    cid: item.cid == 0 ? null : item.cid,
    start: item.progress < 0 ? 0 : item.progress.toDouble(),
    title: item.title,
    cover: item.cover.isEmpty ? null : item.cover,
  );

  /// `00:01 / 06:52` once started, 已看完 at the end, else the length.
  static String progressLabel(WatchLaterItem item) {
    if (item.progress < 0) return '已看完';
    if (item.progress == 0) return _clock(item.duration);
    return '${_clock(item.progress)} / ${_clock(item.duration)}';
  }

  static String _clock(int seconds) {
    final total = seconds < 0 ? 0 : seconds;
    final h = total ~/ 3600, m = total % 3600 ~/ 60, s = total % 60;
    return h > 0 ? '${_two(h)}:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
  }

  static String _two(int n) => n < 10 ? '0$n' : '$n';
}
