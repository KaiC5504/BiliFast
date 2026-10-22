import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../search/results/video_row.dart' show searchLogReason;
import '../../shared/theme.dart';

/// One page of a list, as [OwnPaging] asks for it.
typedef OwnPage<T> = ({List<T> items, bool hasMore});

/// Pages a list shown as slivers in the space's scroll view, page 1 first, the next as the scroll nears the end.
///
/// One call is out at a time; a page that adds nothing ends the list, and a failure waits for 点击重试, so nothing
/// loops against the account. [restartPaging] while a call is out lets it finish, drops its answer, then asks again.
mixin OwnPaging<W extends StatefulWidget, T> on State<W> {
  List<T> items = const [];
  bool hasMore = true;
  bool loading = false;

  /// The first page has answered.
  bool loaded = false;
  bool failed = false;

  int _page = 1;
  int _generation = 0;
  bool _restartPending = false;
  ScrollPosition? _position;
  bool _checkQueued = false;

  Future<OwnPage<T>> fetchPage(int page);

  /// Items already listed are dropped from a later page.
  Object idOf(T item);

  /// The log's name for the list.
  String get pagingName;

  /// False holds the next page back, as while 收藏's list is folded.
  bool get pagingWanted => true;

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
    _position?.removeListener(_scrolled);
    super.dispose();
  }

  /// Starts again from page 1; callers rebuild.
  void restartPaging() {
    _generation++;
    items = const [];
    _page = 1;
    hasMore = true;
    loaded = false;
    failed = false;
    if (loading) {
      _restartPending = true;
    } else {
      _load();
    }
  }

  void retryPaging() => setState(_load);

  /// Checks once the frame is laid out whether the end is in view, as when a list is unfolded.
  void checkPagingAfterFrame() {
    if (_checkQueued) return;
    _checkQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (mounted) _loadMoreNearEnd();
    });
  }

  void _load() {
    if (loading) return;
    loading = true;
    failed = false;
    unawaited(_fetch(_generation, _page));
  }

  Future<void> _fetch(int generation, int page) async {
    final OwnPage<T> answer;
    try {
      answer = await fetchPage(page);
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, '$pagingName failed', {'page': page, 'error': searchLogReason(error)});
      if (_answered(generation)) setState(() => failed = true);
      return;
    }
    if (!_answered(generation)) return;
    final seen = {for (final item in items) idOf(item)};
    final fresh = [
      for (final item in answer.items)
        if (seen.add(idOf(item))) item,
    ];
    setState(() {
      items = [...items, ...fresh];
      _page = page + 1;
      hasMore = answer.hasMore && fresh.isNotEmpty;
      loaded = true;
    });
    // A short page may leave the end in view, with no scroll to ask for the next.
    if (hasMore) checkPagingAfterFrame();
  }

  /// Ends the call that was out, and says whether its answer belongs to the list shown.
  bool _answered(int generation) {
    if (!mounted) return false;
    loading = false;
    if (generation == _generation) return true;
    if (_restartPending) {
      _restartPending = false;
      setState(_load);
    }
    return false;
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
    if (loading || !loaded || !hasMore || failed || !pagingWanted) return;
    final position = _position;
    if (position == null || !position.hasContentDimensions || !position.hasPixels) return;
    if (position.extentAfter >= OwnSpaceTabsTheme.loadAhead) return;
    setState(_load);
  }
}
