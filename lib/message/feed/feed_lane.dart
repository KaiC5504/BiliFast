import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../home/feed_model.dart' show requestFailureMessage;

/// A page of a list and where the next starts; [next] is null at the end.
final class FeedChunk<T> {
  const FeedChunk(this.items, {this.next});

  final List<T> items;
  final Object? next;
}

typedef FeedFetch<T> = Future<FeedChunk<T>> Function(Object? after);

/// The page's calls, one after another: two lists on one page never have calls out at the same time.
class FeedCalls {
  Future<void> _last = Future<void>.value();

  Future<R> run<R>(Future<R> Function() call) {
    final result = _last.then((_) => call());
    _last = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

/// What a failed call logs: its status or code, never its message.
String feedLogReason(Object error) => switch (error) {
  BiliHTTPError(:final status) => 'http $status',
  BiliAPIError(:final code) => 'api $code',
  _ => '${error.runtimeType}',
};

/// One of the page's lists: its rows so far, the call out, why the last one failed. Pages come through [FeedCalls];
/// a refresh drops what a page asked before it brings.
class FeedLane<T> extends ChangeNotifier {
  FeedLane({required this.name, required this.fetch, required this.idOf, required this.calls, Logger? logger})
    : _logger = logger ?? Logger.shared;

  /// The list's name in the log.
  final String name;
  final FeedFetch<T> fetch;
  final int Function(T item) idOf;
  final FeedCalls calls;
  final Logger _logger;

  List<T> _items = const [];
  Object? _next;
  bool _loaded = false;
  bool _end = false;
  bool _loading = false;
  bool _refreshing = false;
  String? _error;
  bool _needsLogin = false;
  int _generation = 0;
  bool _disposed = false;

  List<T> get items => _items;

  /// The first page has answered.
  bool get loaded => _loaded;
  bool get loading => _loading;

  /// The next page is out (not a pull).
  bool get loadingMore => _loading && !_refreshing;
  bool get hasMore => !_end;

  /// Why the first page or the last next page failed, in the user's words.
  String? get error => _error;

  /// The list answered -101: the page asks for the login rather than offering 重试.
  bool get needsLogin => _needsLogin;

  bool get canLoadMore => _loaded && !_end && !_loading && _error == null && !_needsLogin;

  /// The first page, once.
  Future<void> start() async {
    if (_loaded || _loading || _needsLogin) return;
    await _first();
  }

  /// 重试: the first page again, or the next one.
  Future<void> retry() async {
    if (_loading) return;
    _error = null;
    if (_loaded) {
      await loadMore();
    } else {
      await _first();
    }
  }

  /// A pull: the first page again, put in place of the rows once it answers. Returns why it failed when rows stay
  /// on screen, for a toast; a list with none shows the failure itself.
  Future<String?> refresh() async {
    if (_needsLogin) return null;
    final generation = ++_generation;
    _loading = true;
    _refreshing = true;
    _notify();
    try {
      final chunk = await calls.run(() => fetch(null));
      if (_disposed || generation != _generation) return null;
      _items = _unique(chunk.items);
      _next = chunk.next;
      _end = chunk.next == null || chunk.items.isEmpty;
      _loaded = true;
      _error = null;
      return null;
    } catch (error) {
      if (_disposed || generation != _generation) return null;
      final message = _failed(error);
      if (_loaded) return message;
      _error = message;
      return null;
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        _refreshing = false;
        _notify();
      }
    }
  }

  Future<void> _first() async {
    await refresh();
  }

  Future<void> loadMore() async {
    if (!canLoadMore) return;
    final generation = _generation;
    final after = _next;
    _loading = true;
    _notify();
    try {
      final chunk = await calls.run(() => fetch(after));
      if (_disposed || generation != _generation) return;
      final seen = {for (final item in _items) idOf(item)};
      final added = [
        for (final item in chunk.items)
          if (seen.add(idOf(item))) item,
      ];
      _items = [..._items, ...added];
      _next = chunk.next;
      // A page that adds nothing ends the list, so a server answering the same page can't keep it asking.
      _end = chunk.next == null || added.isEmpty;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _error = _failed(error);
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Forgets everything, for another account; nothing out is kept.
  void reset() {
    _generation += 1;
    _items = const [];
    _next = null;
    _loaded = false;
    _end = false;
    _loading = false;
    _refreshing = false;
    _error = null;
    _needsLogin = false;
    _notify();
  }

  void remove(int id) {
    final kept = [
      for (final item in _items)
        if (idOf(item) != id) item,
    ];
    if (kept.length == _items.length) return;
    _items = kept;
    _notify();
  }

  void update(int id, T Function(T item) change) {
    final index = _items.indexWhere((item) => idOf(item) == id);
    if (index < 0) return;
    _items = [..._items]..[index] = change(_items[index]);
    _notify();
  }

  List<T> _unique(List<T> items) {
    final seen = <int>{};
    return [
      for (final item in items)
        if (seen.add(idOf(item))) item,
    ];
  }

  String _failed(Object error) {
    _logger.warn(LogCategory.api, 'message feed failed', {'list': name, 'error': feedLogReason(error)});
    if (error is BiliError && error.needsLogin) _needsLogin = true;
    return requestFailureMessage(error);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
