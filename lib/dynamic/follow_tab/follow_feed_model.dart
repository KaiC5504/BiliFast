import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../home/feed_model.dart' show requestFailureMessage;
import '../dynamic_api.dart';

/// One list of posts paged by `offset`: 关注's 全部 or 视频, or one person's in the face sheet. One call at a time, but
/// for a refresh that drops a next page still out; it stops at `has_more` false, an empty offset, or a page that adds
/// no post it doesn't already have.
class FollowFeed extends ChangeNotifier {
  FollowFeed({required this.name, required this.load, Logger? logger}) : _logger = logger ?? Logger.shared;

  /// What the log calls it: `all`, `video` or `space`.
  final String name;
  final Future<DynamicPage> Function(String? offset) load;
  final Logger _logger;

  List<DynamicItem> _items = const [];
  bool _started = false;
  bool _loading = false;
  bool _refreshing = false;
  bool _isEnd = false;
  String? _error;
  bool _needsLogin = false;
  String? _offset;

  /// The first page while it is out (the first show's or a refresh's): a refresh meanwhile waits on it.
  final _first = _Shared<String?>();

  /// Bumped by a reload or a sign-out, so a page still in flight lands nowhere.
  int _generation = 0;
  bool _disposed = false;

  List<DynamicItem> get items => _items;
  bool get started => _started;
  bool get loading => _loading;

  /// A pull or a tap's refresh is running over posts already shown.
  bool get refreshing => _refreshing;
  bool get isEnd => _isEnd;

  /// Why the next page (or, with no posts, the first) failed; nothing asks again until [retry] or a refresh.
  String? get error => _error;

  /// Bilibili answered that the login is gone (-101) when the list had no posts.
  bool get needsLogin => _needsLogin;

  bool get canLoadMore => _started && !_loading && !_isEnd && _error == null;

  /// The first page, once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _first.run(() => _load(replacing: true));
  }

  Future<void> loadMore() async {
    if (!_started || _loading || _isEnd) return;
    _error = null;
    await _load(replacing: false);
  }

  /// 重试: the first page again while no post shows (after an empty list too, which [loadMore] takes as the end), else
  /// the next page that failed.
  Future<void> retry() async {
    if (_items.isEmpty) {
      await reload();
    } else {
      await loadMore();
    }
  }

  /// Starts over. The posts shown stay until the first page answers; a failure then keeps them and comes back as
  /// words for a toast (null otherwise). A first page already out answers for this one; a next page out is dropped.
  Future<String?> reload() => _first.run(() {
    _generation++;
    _started = true;
    _error = null;
    _refreshing = _items.isNotEmpty;
    return _load(replacing: true);
  });

  /// The account left: its posts go at once, and the list starts over when next shown.
  void clear() {
    _generation++;
    _items = const [];
    _started = false;
    _loading = false;
    _refreshing = false;
    _isEnd = false;
    _error = null;
    _needsLogin = false;
    _offset = null;
    _first.forget();
    _notify();
  }

  Future<String?> _load({required bool replacing}) async {
    final mine = _generation;
    _loading = true;
    _notify();
    final watch = Stopwatch()..start();
    try {
      final page = await load(replacing ? null : _offset);
      if (mine != _generation || _disposed) return null;
      final kept = replacing ? <DynamicItem>[] : [..._items];
      final seen = {for (final item in kept) item.id};
      final fresh = [
        for (final item in page.items)
          if (seen.add(item.id)) item,
      ];
      _items = [...kept, ...fresh];
      _offset = page.offset;
      _isEnd = !page.hasMore || page.offset.isEmpty || fresh.isEmpty;
      _error = null;
      _needsLogin = false;
      _logger.info(LogCategory.api, 'dynamic feed', {
        'type': name,
        'count': page.items.length,
        'added': fresh.length,
        'more': !_isEnd,
        'skipped': _skipped(page.skipped),
        'ms': watch.elapsedMilliseconds,
      });
      return null;
    } catch (error) {
      if (mine != _generation || _disposed) return null;
      _logger.warn(LogCategory.api, 'dynamic feed failed', {
        'type': name,
        'error': '${error.runtimeType}',
        'ms': watch.elapsedMilliseconds,
      });
      final message = requestFailureMessage(error);
      if (replacing && _items.isNotEmpty) return message;
      _error = message;
      _needsLogin = error is BiliError && error.needsLogin;
      return null;
    } finally {
      if (mine == _generation && !_disposed) {
        _loading = false;
        _refreshing = false;
        _notify();
      }
    }
  }

  /// `DYNAMIC_TYPE_LIVE:2,…`: kinds only, never a post's words.
  static String _skipped(Map<String, int> skipped) =>
      [for (final MapEntry(:key, :value) in skipped.entries) '$key:$value'].join(',');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The 关注 tab's lists: 全部 and 视频 (each kept while the other shows), 最常访问's faces and, on 视频, 我的追番 · 追剧.
/// Faces opened in the face sheet lose their dot for the run.
class FollowTabModel extends ChangeNotifier {
  FollowTabModel({required this.api, required this.mid, Logger? logger}) : _logger = logger ?? Logger.shared {
    all = FollowFeed(
      name: DynamicFeedType.all.rawValue,
      load: (offset) => api.feed(DynamicFeedType.all, offset: offset),
      logger: _logger,
    )..addListener(notifyListeners);
    video = FollowFeed(
      name: DynamicFeedType.video.rawValue,
      load: (offset) => api.feed(DynamicFeedType.video, offset: offset),
      logger: _logger,
    )..addListener(notifyListeners);
  }

  final DynamicApi api;

  /// The account's mid, for 我的追番 · 追剧; null logged out.
  final int? Function() mid;
  final Logger _logger;

  late final FollowFeed all;
  late final FollowFeed video;

  DynamicFeedType _type = DynamicFeedType.all;
  List<DynamicUp> _ups = const [];
  String _upsOffset = '';
  bool _upsMore = false;
  bool _upsLoading = false;
  bool _upsStarted = false;

  /// A later page of faces failed: the row asks for no more until a refresh's faces answer, or every scroll at its
  /// end would ask again.
  bool _upsFailed = false;
  final _firstUps = _Shared<void>();
  List<FollowedBangumi> _bangumi = const [];
  bool _bangumiStarted = false;
  final _bangumiCall = _Shared<void>();
  final _seen = <int>{};

  /// Bumped by a sign-out, so answers in flight land nowhere; [_upsGeneration] also by a refresh's faces, which drop
  /// a later page still out.
  int _generation = 0;
  int _upsGeneration = 0;
  bool _disposed = false;

  DynamicFeedType get type => _type;
  FollowFeed get current => _type == DynamicFeedType.video ? video : all;
  List<DynamicUp> get ups => _ups;
  bool get started => _upsStarted;

  /// Shown only on 视频, and only when the account follows any.
  List<FollowedBangumi> get bangumi => _type == DynamicFeedType.video ? _bangumi : const [];

  bool hasUpdate(DynamicUp up) => up.hasUpdate && !_seen.contains(up.mid);

  void markSeen(int mid) {
    if (_seen.add(mid)) _notify();
  }

  /// The first show: 最常访问 and the list on screen.
  Future<void> start() async {
    if (_upsStarted) return;
    _upsStarted = true;
    await Future.wait([_refreshUps(), current.start(), if (_type == DynamicFeedType.video) _askBangumi()]);
  }

  /// 全部 or 视频; the other keeps its posts. 视频 asks for 我的追番 · 追剧 the first time it shows.
  void select(DynamicFeedType type) {
    if (type == _type) return;
    _type = type;
    _notify();
    if (!_upsStarted) return;
    unawaited(current.start());
    if (type == DynamicFeedType.video && !_bangumiStarted) unawaited(_askBangumi());
  }

  /// A pull or a tap on 关注: the faces, the list on screen and, on 视频, the posters again. Each that is still out
  /// (the first show's, another refresh's) answers for itself instead of being asked twice. Completes with a failure's
  /// words when posts were already shown (for a toast), else null.
  Future<String?> refresh() async {
    _upsStarted = true;
    final results = await Future.wait<String?>([
      _refreshUps().then((_) => null),
      current.reload(),
      if (_type == DynamicFeedType.video) _askBangumi().then((_) => null),
    ]);
    return results.whereType<String>().firstOrNull;
  }

  /// More faces once the row is scrolled near its end.
  Future<void> loadMoreUps() async {
    if (!_upsMore || _upsLoading || _upsFailed) return;
    await _loadUps(replacing: false);
  }

  Future<void> _refreshUps() => _firstUps.run(() => _loadUps(replacing: true));

  Future<void> _loadUps({required bool replacing}) async {
    if (_upsLoading && !replacing) return;
    final mine = replacing ? ++_upsGeneration : _upsGeneration;
    _upsLoading = true;
    try {
      final list = await api.ups(offset: replacing ? null : _upsOffset);
      if (mine != _upsGeneration || _disposed) return;
      final kept = replacing ? <DynamicUp>[] : [..._ups];
      final seen = {for (final up in kept) up.mid};
      final fresh = [
        for (final up in list.ups)
          if (seen.add(up.mid)) up,
      ];
      _ups = [...kept, ...fresh];
      _upsOffset = list.offset;
      _upsMore = list.hasMore && list.offset.isNotEmpty && fresh.isNotEmpty;
      if (replacing) _upsFailed = false;
    } catch (error) {
      if (mine != _upsGeneration || _disposed) return;
      if (!replacing) _upsFailed = true;
      _logger.warn(LogCategory.api, 'dynamic ups failed', {'error': '${error.runtimeType}', 'more': !replacing});
    } finally {
      if (mine == _upsGeneration) _upsLoading = false;
      _notify();
    }
  }

  Future<void> _askBangumi() => _bangumiCall.run(_loadBangumi);

  Future<void> _loadBangumi() async {
    _bangumiStarted = true;
    final account = mid();
    if (account == null || account <= 0) {
      _bangumi = const [];
      _notify();
      return;
    }
    final generation = _generation;
    try {
      final page = await api.bangumi(account, page: 1);
      if (generation != _generation || _disposed) return;
      _bangumi = page.items;
    } catch (error) {
      if (generation != _generation || _disposed) return;
      _logger.warn(LogCategory.api, 'dynamic bangumi failed', {'error': '${error.runtimeType}'});
    }
    _notify();
  }

  /// The account left: everything goes, and the next show starts over.
  void signOut() {
    _generation++;
    _upsGeneration++;
    _ups = const [];
    _upsOffset = '';
    _upsMore = false;
    _upsLoading = false;
    _upsStarted = false;
    _upsFailed = false;
    _firstUps.forget();
    _bangumi = const [];
    _bangumiStarted = false;
    _bangumiCall.forget();
    _seen.clear();
    all.clear();
    video.clear();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    all.dispose();
    video.dispose();
    super.dispose();
  }
}

/// One call out at a time: asked again while it is out, the same call answers.
final class _Shared<T> {
  Future<T>? _out;

  Future<T> run(Future<T> Function() call) {
    if (_out case final out?) return out;
    late final Future<T> future;
    future = call().whenComplete(() {
      if (identical(_out, future)) _out = null;
    });
    return _out = future;
  }

  /// A sign-out: the call out lands nowhere, and the next is asked afresh.
  void forget() => _out = null;
}
