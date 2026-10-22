import 'dart:async';

import 'package:bili_core/api.dart' show BiliNoAppTokenError;
import 'package:bili_core/devlog.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../search/results/video_row.dart' show searchLogReason;
import '../../shared/theme.dart';

/// One page of a list, as [OwnPager] asks for it.
typedef OwnPage<T> = ({List<T> items, bool hasMore});

/// One of the own space's paged lists, page 1 first and the next when asked. The page keeps one per tab while it is
/// open, so a tab switched away and back shows what had come with no call, and an answer landing meanwhile is kept.
///
/// One call is out at a time; a page that adds nothing ends the list, and a failure waits for 点击重试, so nothing
/// loops against the account. A missing app token asks [authorize] and starts the list again when it answers yes.
/// [restart] while a call is out lets it finish, drops its answer, then asks again.
abstract class OwnPager<T> extends ChangeNotifier {
  OwnPager({this.authorize});

  /// Completes with whether the app token is held now; without it the list waits for 点击重试.
  final Future<bool> Function()? authorize;

  List<T> _items = const [];
  bool _hasMore = true;
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  bool _started = false;
  bool _disposed = false;
  bool _authAsked = false;
  int _page = 1;
  int _generation = 0;
  bool _restartPending = false;

  List<T> get items => _items;
  bool get hasMore => _hasMore;
  bool get loading => _loading;

  /// The first page has answered.
  bool get loaded => _loaded;
  bool get failed => _failed;

  /// The log's name for the list.
  String get name;

  Future<OwnPage<T>> fetchPage(int page);

  /// Items already listed are dropped from a later page.
  Object idOf(T item);

  /// Page 1, the first time the list is shown.
  void start() {
    if (!_started) restart();
  }

  /// Starts again from page 1.
  void restart() {
    _started = true;
    _generation++;
    _items = const [];
    _page = 1;
    _hasMore = true;
    _loaded = false;
    _failed = false;
    if (_loading) {
      _restartPending = true;
    } else {
      _load();
    }
    notifyListeners();
  }

  void retry() {
    if (_loading) return;
    _authAsked = false;
    _load();
    notifyListeners();
  }

  /// The next page, unless one is out, the list has ended or a failure waits for 点击重试.
  void loadMore() {
    if (_loading || !_loaded || !_hasMore || _failed) return;
    _load();
    notifyListeners();
  }

  void _load() {
    _loading = true;
    _failed = false;
    unawaited(_fetch(_generation, _page));
  }

  Future<void> _fetch(int generation, int page) async {
    final OwnPage<T> answer;
    try {
      answer = await fetchPage(page);
    } on BiliNoAppTokenError {
      Logger.shared.info(LogCategory.ui, '$name without app token', {'page': page});
      // Once until a page answers or 点击重试, so a token that doesn't take can't bring the confirm back in a loop.
      final ask = _authAsked ? null : authorize;
      _authAsked = true;
      // Still loading while the confirm is up, so the scroll asks for nothing more meanwhile.
      final granted = await ask?.call() ?? false;
      if (!_answered(generation)) return;
      if (granted) {
        restart();
      } else {
        _failed = true;
        notifyListeners();
      }
      return;
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, '$name failed', {'page': page, 'error': searchLogReason(error)});
      if (!_answered(generation)) return;
      _failed = true;
      notifyListeners();
      return;
    }
    if (!_answered(generation)) return;
    _authAsked = false;
    final seen = {for (final item in _items) idOf(item)};
    final fresh = [
      for (final item in answer.items)
        if (seen.add(idOf(item))) item,
    ];
    _items = [..._items, ...fresh];
    _page = page + 1;
    _hasMore = answer.hasMore && fresh.isNotEmpty;
    _loaded = true;
    notifyListeners();
  }

  /// Ends the call that was out, and says whether its answer belongs to the list shown.
  bool _answered(int generation) {
    if (_disposed) return false;
    _loading = false;
    if (generation == _generation) return true;
    if (_restartPending) {
      _restartPending = false;
      _load();
      notifyListeners();
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A sliver showing an [OwnPager]: it starts the list, rebuilds as it answers and asks for the next page as the scroll
/// nears the end.
mixin OwnPagerView<W extends StatefulWidget, T> on State<W> {
  OwnPager<T> get pager;

  /// False holds the next page back, as while 收藏's list is folded.
  bool get pagingWanted => true;

  OwnPager<T>? _shown;
  ScrollPosition? _position;
  bool _checkQueued = false;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_scrolled);
      _position = position?..addListener(_scrolled);
    }
  }

  @override
  void dispose() {
    _shown?.removeListener(_changed);
    _position?.removeListener(_scrolled);
    super.dispose();
  }

  void _follow() {
    final pager = this.pager;
    if (identical(pager, _shown)) return;
    _shown?.removeListener(_changed);
    pager.start();
    _shown = pager..addListener(_changed);
    // A list kept from an earlier visit may end inside the screen already.
    checkPagingAfterFrame();
  }

  void _changed() {
    setState(() {});
    // A short page may leave the end in view, with no scroll to ask for the next.
    if (pager.loaded && pager.hasMore) checkPagingAfterFrame();
  }

  /// Checks once the frame is laid out whether the end is in view, as when a list is unfolded.
  void checkPagingAfterFrame() {
    if (_checkQueued) return;
    _checkQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (mounted) _loadMoreNearEnd();
    });
  }

  void _scrolled() {
    // A position can change mid-layout, where nothing may rebuild yet.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      checkPagingAfterFrame();
    } else {
      _loadMoreNearEnd();
    }
  }

  void _loadMoreNearEnd() {
    final pager = this.pager;
    if (pager.loading || !pager.loaded || !pager.hasMore || pager.failed || !pagingWanted) return;
    final position = _position;
    if (position == null || !position.hasContentDimensions || !position.hasPixels) return;
    if (position.extentAfter >= OwnSpaceTabsTheme.loadAhead) return;
    pager.loadMore();
  }
}
