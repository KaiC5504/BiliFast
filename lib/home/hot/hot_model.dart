import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../feed_model.dart' show feedLogFields, requestFailureMessage;
import 'hot_api.dart';

/// 热门's pages (204): the videos shown, a page at a time. One call is out at a time; a page that adds no video ends
/// the list, and a failure waits for 重试, so nothing loops against the website.
class HotModel extends ChangeNotifier {
  HotModel({required this._api, Logger? logger}) : _logger = logger ?? Logger.shared;

  final HotApi _api;
  final Logger _logger;

  List<PopularVideo> get videos => _videos;
  List<PopularVideo> _videos = const [];

  /// The last page shown, 0 before the first.
  int _page = 0;
  bool _hasMore = true;

  /// The first page has been asked for.
  bool get started => _started;
  bool _started = false;

  Future<void>? _out;
  int _outPage = 0;

  /// The next page is out, under the rows.
  bool get loadingMore => _out != null && _outPage > 1;

  /// The first page is out with nothing shown.
  bool get loadingFirst => _out != null && _videos.isEmpty;

  /// Why the last call failed, until another starts; null while every call went through.
  String? get error => _error;
  String? _error;

  /// The list's end was reached.
  bool get exhausted => _started && !_hasMore && _out == null && _error == null;

  bool get canLoadMore => _videos.isNotEmpty && _hasMore && _error == null && _out == null && _refreshing == null;

  Future<String?>? _refreshing;

  /// A refresh is running.
  bool get refreshing => _refreshing != null;

  /// Bumped by a refresh, so an answer to a page asked before it is dropped.
  int _generation = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The first page, once.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_fetch(1));
  }

  /// Page 1 again, put in place of the list once it answers: the refresh running, or a new one. A page still out is
  /// let finish first and its answer dropped. Completes with why it failed when videos stay on screen, for a toast;
  /// with nothing shown the failure shows in the list's place instead.
  Future<String?> refresh() {
    _started = true;
    if (_refreshing case final running?) return running;
    // The first page or its 重试 is already what a refresh would ask.
    if (_out case final out? when _outPage == 1) return out.then((_) => null);
    return _refreshing = _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _refresh() async {
    _generation++;
    for (var out = _out; out != null; out = _out) {
      await out;
    }
    if (_disposed) return null;
    return _fetch(1);
  }

  Future<void> loadMore() async {
    if (!canLoadMore) return;
    await _fetch(_page + 1);
  }

  /// 重试: the first page if nothing shows, else the page that failed.
  Future<void> retry() async {
    if (_out != null || _refreshing != null) return;
    await _fetch(_videos.isEmpty ? 1 : _page + 1);
  }

  Future<String?> _fetch(int page) async {
    final generation = _generation;
    final done = Completer<void>();
    _out = done.future;
    _outPage = page;
    _error = null;
    _changed();
    try {
      final answer = await _api.page(page);
      if (generation != _generation || _disposed) return null;
      final seen = page == 1 ? <String>{} : {for (final video in _videos) video.card.bvid};
      final fresh = [
        for (final video in answer.videos)
          if (seen.add(video.card.bvid)) video,
      ];
      _videos = page == 1 ? fresh : [..._videos, ...fresh];
      _page = page;
      // A page that adds nothing ends the list, so an answer repeating itself can't keep it asking.
      _hasMore = answer.hasMore && fresh.isNotEmpty;
      return null;
    } catch (error) {
      _logger.warn(LogCategory.ui, 'hot page failed', {...feedLogFields(error), 'page': page});
      if (generation != _generation || _disposed) return null;
      final message = requestFailureMessage(error);
      if (page == 1 && _videos.isNotEmpty) return message;
      _error = message;
      return null;
    } finally {
      _out = null;
      done.complete();
      _changed();
    }
  }
}
