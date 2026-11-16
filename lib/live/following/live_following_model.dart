import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../home/feed_model.dart' show feedLogFields, requestFailureMessage;
import '../live_api.dart';

/// 206's followed rooms live now, a page at a time: one call out at a time, a page that adds no room ends the list,
/// and a failure waits for 重试.
class LiveFollowingModel extends ChangeNotifier {
  LiveFollowingModel({required this._api, Logger? logger}) : _logger = logger ?? Logger.shared;

  final LiveApi _api;
  final Logger _logger;

  List<LiveCard> get cards => _cards;
  List<LiveCard> _cards = const [];

  /// 人正在直播's count: the answer's, else the rooms shown.
  int get total => _total > 0 ? _total : _cards.length;
  int _total = 0;

  int _page = 0;
  bool _hasMore = true;
  bool _answered = false;
  Future<void>? _out;
  int _outPage = 0;
  int _generation = 0;
  bool _disposed = false;

  bool get loadingFirst => _out != null && _cards.isEmpty;
  bool get loadingMore => _out != null && _outPage > 1;

  String? get error => _error;
  String? _error;

  bool get answered => _answered;
  bool get exhausted => _answered && !_hasMore && _out == null && _error == null;
  bool get canLoadMore => _cards.isNotEmpty && _hasMore && _error == null && _out == null && _refreshing == null;

  Future<String?>? _refreshing;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void start() => unawaited(_fetch(1));

  /// Page 1 again in place of the list; with rooms on screen a failure comes back for a toast.
  Future<String?> refresh() {
    if (_refreshing case final running?) return running;
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

  Future<void> retry() async {
    if (_out != null || _refreshing != null) return;
    await _fetch(_cards.isEmpty ? 1 : _page + 1);
  }

  Future<String?> _fetch(int page) async {
    final generation = _generation;
    final done = Completer<void>();
    _out = done.future;
    _outPage = page;
    _error = null;
    _changed();
    try {
      final answer = await _api.following(page: page);
      if (generation != _generation || _disposed) return null;
      final seen = page == 1 ? <int>{} : {for (final card in _cards) card.roomId};
      final fresh = [
        for (final card in answer.cards)
          if (seen.add(card.roomId)) card,
      ];
      _cards = page == 1 ? fresh : [..._cards, ...fresh];
      if (page == 1 || answer.total > 0) _total = answer.total;
      _page = page;
      _answered = true;
      _hasMore = answer.hasMore && fresh.isNotEmpty;
      return null;
    } catch (error) {
      _logger.warn(LogCategory.ui, 'live following page failed', {...feedLogFields(error), 'page': page});
      if (generation != _generation || _disposed) return null;
      final message = requestFailureMessage(error);
      if (page == 1 && _cards.isNotEmpty) return message;
      _error = message;
      return null;
    } finally {
      _out = null;
      done.complete();
      _changed();
    }
  }
}
