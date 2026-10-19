import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/logic.dart' show TimeFormat;
import 'package:flutter/foundation.dart';

import '../home/feed_model.dart' show requestFailureMessage;
import '../video/page_api.dart';
import '../video/video_route.dart';

/// One day group of 历史记录: 今天, 昨天, or everything older under 更早 (the official 45-47).
@immutable
final class HistorySection {
  const HistorySection(this.title, this.items);

  final String title;
  final List<HistoryItem> items;
}

/// 历史记录 (BiliNative `HistoryModel.swift`): pages through the cursor, groups by day, and knows where each video
/// resumes.
class HistoryModel extends ChangeNotifier {
  HistoryModel({required this.api, required this.isLoggedIn, DateTime Function()? now, this.utcOffset, Logger? logger})
    : _now = now ?? DateTime.now,
      _logger = logger ?? Logger.shared;

  static const today = '今天';
  static const yesterday = '昨天';
  static const earlier = '更早';
  static const deleteFailed = '删除失败，请稍后重试';

  /// Pages in a row that may add nothing (every row already listed) before a load more stops asking.
  static const _emptyPagesAllowed = 3;

  final PageApi api;
  final bool Function() isLoggedIn;

  /// The calendar the days are counted in; null is the device's.
  final Duration? utcOffset;
  final DateTime Function() _now;
  final Logger _logger;

  List<HistoryItem> _items = const [];
  bool _loading = false;
  bool _refreshing = false;
  String? _error;
  bool _isEnd = false;
  bool _needsLogin = false;
  HistoryCursor? _cursor;

  /// Rows deleted here: a page still in flight, or the server answering before its delete lands, must not bring one
  /// back.
  final Set<String> _deleted = {};

  /// Bumped by a reload, so a load more still running cannot append to the new list.
  int _generation = 0;

  /// Bumped by [signOut], so a delete answering for the account that left changes nothing in the next one's list.
  int _signOuts = 0;
  bool _disposed = false;

  List<HistoryItem> get items => _items;
  bool get loading => _loading;

  /// A pull to refresh is running; the rows already shown stay until it answers.
  bool get refreshing => _refreshing;

  /// Why the next page (or, with no rows, the first) failed; nothing asks again until [loadMore].
  String? get error => _error;
  bool get isEnd => _isEnd;

  /// Logged out, or Bilibili answered -101.
  bool get needsLogin => _needsLogin;

  bool get canLoadMore => !_loading && !_isEnd && !_needsLogin && _error == null;

  List<HistorySection> get sections {
    final todayStart = _dayOf(_now());
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final groups = <String, List<HistoryItem>>{today: [], yesterday: [], earlier: []};
    for (final item in _items) {
      final day = _dayOf(DateTime.fromMillisecondsSinceEpoch(item.viewAt * 1000, isUtc: true));
      final String title;
      if (!day.isBefore(todayStart)) {
        title = today;
      } else if (!day.isBefore(yesterdayStart)) {
        title = yesterday;
      } else {
        title = earlier;
      }
      groups[title]!.add(item);
    }
    return [
      for (final MapEntry(key: title, value: rows) in groups.entries)
        if (rows.isNotEmpty) HistorySection(title, rows),
    ];
  }

  /// The wall-clock day of [instant] at [utcOffset], as a UTC midnight.
  DateTime _dayOf(DateTime instant) {
    final wall = instant.toUtc().add(utcOffset ?? instant.toLocal().timeZoneOffset);
    return DateTime.utc(wall.year, wall.month, wall.day);
  }

  /// The first page, unless logged out (then the page shows 登录后查看历史记录 without asking Bilibili).
  Future<void> start() async {
    if (!isLoggedIn()) {
      _needsLogin = true;
      _notify();
      return;
    }
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_loading || _isEnd || _needsLogin) return;
    _error = null;
    await _load(replacing: false);
  }

  /// Starts over, as on pull to refresh and after logging in. The rows already shown stay until the first page
  /// answers; a failure then keeps them and comes back as words for a toast (null otherwise).
  Future<String?> reload() async {
    _generation++;
    _needsLogin = false;
    _error = null;
    _refreshing = _items.isNotEmpty;
    return _load(replacing: true);
  }

  Future<String?> _load({required bool replacing}) async {
    final mine = _generation;
    _loading = true;
    _notify();
    var next = replacing ? null : _cursor;
    var kept = replacing ? <HistoryItem>[] : [..._items];
    var end = false;
    try {
      for (var attempt = 0; attempt < _emptyPagesAllowed; attempt++) {
        final page = await api.history(after: next);
        if (mine != _generation || _disposed) return null;
        final seen = {for (final item in kept) item.id, ..._deleted};
        final fresh = [
          for (final item in page.items)
            if (seen.add(item.id)) item,
        ];
        kept = [...kept, ...fresh];
        next = page.next;
        end = page.next == null || page.items.isEmpty;
        if (fresh.isNotEmpty || end) break;
      }
      _items = kept;
      _cursor = next;
      _isEnd = end;
      _error = null;
      return null;
    } on BiliError catch (error) {
      if (mine != _generation || _disposed) return null;
      if (error.needsLogin) {
        _loggedOut();
        return null;
      }
      return _failed(error, replacing: replacing);
    } catch (error) {
      if (mine != _generation || _disposed) return null;
      return _failed(error, replacing: replacing);
    } finally {
      if (mine == _generation && !_disposed) {
        _loading = false;
        _refreshing = false;
        _notify();
      }
    }
  }

  /// The account logged out: its rows go at once, a page still loading lands nowhere, and [needsLogin] holds until
  /// the next [reload].
  void signOut() {
    _generation++;
    _signOuts++;
    _loading = false;
    _refreshing = false;
    _error = null;
    _deleted.clear();
    _loggedOut();
    _notify();
  }

  void _loggedOut() {
    _needsLogin = true;
    _items = const [];
    _cursor = null;
    _isEnd = false;
  }

  String? _failed(Object error, {required bool replacing}) {
    _logger.warn(LogCategory.ui, 'history failed', {'error': '$error'});
    final message = requestFailureMessage(error);
    if (replacing && _items.isNotEmpty) return message;
    _error = message;
    return null;
  }

  /// Takes [item] off at once and deletes it on the server; if that fails the row comes back where it was and the
  /// words for a toast are returned (null on success). A -101 instead turns the page to its login state.
  Future<String?> delete(HistoryItem item) async {
    final index = _items.indexWhere((row) => row.id == item.id);
    if (index < 0) return null;
    _items = [..._items]..removeAt(index);
    _deleted.add(item.id);
    _notify();
    final signOuts = _signOuts;
    try {
      await api.deleteHistory(item);
      return null;
    } catch (error) {
      _logger.warn(LogCategory.ui, 'history delete failed', {'error': '$error'});
      if (signOuts != _signOuts) return null;
      _deleted.remove(item.id);
      if (_disposed) return deleteFailed;
      if (error is BiliError && error.needsLogin) {
        // A page still loading would land in a list that is gone.
        _generation++;
        _loading = false;
        _refreshing = false;
        _loggedOut();
        _notify();
        return null;
      }
      if (!_items.any((row) => row.id == item.id)) {
        // Rows may have come and gone meanwhile; the list is newest first, so it goes back before the first older one.
        final at = _items.indexWhere((row) => row.viewAt < item.viewAt);
        _items = [..._items]..insert(at < 0 ? _items.length : at, item);
        _notify();
      }
      return deleteFailed;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// A finished video (progress -1) starts again from the beginning.
  static VideoRoute route(HistoryItem item) => VideoRoute(
    bvid: item.bvid,
    cid: item.cid == 0 ? null : item.cid,
    start: item.progress < 0 ? 0 : item.progress.toDouble(),
    title: item.title,
  );

  /// `00:02/07:27` on the cover (hours as `03:40:30`), or 已看完.
  static String progressLabel(HistoryItem item) =>
      item.progress < 0 ? '已看完' : '${_clock(item.progress)}/${_clock(item.duration)}';

  /// How much of the pink line under the cover is filled.
  static double progressFraction(HistoryItem item) {
    if (item.progress < 0) return 1;
    if (item.duration <= 0) return 0;
    return (item.progress / item.duration).clamp(0, 1).toDouble();
  }

  /// `2026年10月19日 03:02`, in every section.
  String timeLabel(HistoryItem item) => TimeFormat.publish(item.viewAt, utcOffset: utcOffset);

  /// The video's page on the web, for 分享.
  static Uri shareLink(HistoryItem item) => Uri.parse('https://www.bilibili.com/video/${item.bvid}');

  static String _clock(int seconds) {
    final total = seconds < 0 ? 0 : seconds;
    final h = total ~/ 3600, m = total % 3600 ~/ 60, s = total % 60;
    return h > 0 ? '${_two(h)}:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
  }

  static String _two(int n) => n < 10 ? '0$n' : '$n';
}
