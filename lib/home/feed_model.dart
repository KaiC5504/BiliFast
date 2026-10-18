import 'dart:async' show TimeoutException;
import 'dart:io' show IOException;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../playback/playback_controller.dart' show PlaybackFailure;

/// The words for a failed request: the BiliError's or PlaybackFailure's message (a 番剧 link), a network message
/// when the connection failed or timed out, otherwise [fallback].
String requestFailureMessage(Object error, {String fallback = '加载失败，请稍后重试'}) {
  if (error is BiliError) return error.userMessage;
  if (error is PlaybackFailure) return error.userMessage;
  // package:http's ClientException, which the app does not import, from both transports.
  if (error is IOException || error is TimeoutException || '$error'.startsWith('ClientException')) {
    return '网络连接失败，请检查网络后重试';
  }
  return fallback;
}

/// The 推荐 feed (port of FeedModel.swift): page 1 on refresh, then the next index for every load more.
class FeedModel extends ChangeNotifier {
  FeedModel({required this._client, Logger? logger}) : _logger = logger ?? Logger.shared;

  static const emptyMessage = '暂时没有推荐的视频';
  static const endMessage = '没有更多了';

  /// Pages in a row that may add nothing before a load more gives up and the feed counts as [exhausted].
  static const _emptyPagesAllowed = 3;

  final BiliClient _client;
  final Logger _logger;
  List<FeedCard> _cards = const [];
  bool _loading = false;
  String? _error;
  bool _exhausted = false;
  int _nextIndex = 1;

  /// A refresh replaces the list, so a load more that was already running must not append to the new one.
  int _generation = 0;
  bool _disposed = false;

  List<FeedCard> get cards => _cards;
  bool get loading => _loading;

  /// Why the cards are missing (nothing on screen) or the next page is (under the cards); endless scroll waits for
  /// [retry] instead of asking again by itself.
  String? get error => _error;

  /// The last load more got only pages of cards already shown (or ads); scrolling stops asking until [retry].
  bool get exhausted => _exhausted;

  /// Whether endless scroll may ask for the next page now.
  bool get canLoadMore => _cards.isNotEmpty && !_loading && _error == null && !_exhausted;

  /// Page 1 again. With cards on screen a failure (or an empty page) keeps them, and its words come back for a toast;
  /// with none, it becomes [error]. Null otherwise.
  Future<String?> refresh() async {
    final mine = ++_generation;
    _loading = true;
    _notify();
    String? failure;
    try {
      // The first launch reaches here before the account check has fetched the fingerprint cookies.
      await _client.ensureRiskCookies();
      final page = await _client.recommendFeed(index: 1);
      if (mine != _generation) return null;
      final fresh = _appending(page, const []);
      _logPage(1, page.length, fresh.length);
      if (fresh.isEmpty) {
        failure = emptyMessage;
      } else {
        _cards = fresh;
        _nextIndex = 2;
        _error = null;
        _exhausted = false;
      }
    } catch (error) {
      if (mine != _generation) return null;
      _logger.warn(LogCategory.ui, 'feed refresh failed', {'error': '$error'});
      failure = requestFailureMessage(error);
    }
    _loading = false;
    final kept = _cards.isNotEmpty;
    if (failure != null && !kept) _error = failure;
    _notify();
    return kept ? failure : null;
  }

  Future<void> loadMore() async {
    if (_loading) return;
    if (_cards.isEmpty) {
      await refresh();
      return;
    }
    final mine = _generation;
    _loading = true;
    _error = null;
    _exhausted = false;
    _notify();
    try {
      // A page of cards already shown (or only ads) adds nothing, and then no card appears to ask for the next one;
      // ask on, a few times.
      var added = 0;
      for (var attempt = 0; attempt < _emptyPagesAllowed && added == 0; attempt++) {
        final index = _nextIndex;
        final page = await _client.recommendFeed(index: index);
        if (mine != _generation) return;
        final before = _cards.length;
        _cards = _appending(page, _cards);
        _nextIndex += 1;
        added = _cards.length - before;
        _logPage(index, page.length, added);
      }
      _exhausted = added == 0;
    } catch (error) {
      if (mine != _generation) return;
      _logger.warn(LogCategory.ui, 'feed load more failed', {'index': _nextIndex, 'error': '$error'});
      _error = requestFailureMessage(error);
    } finally {
      if (mine == _generation) {
        _loading = false;
        _notify();
      }
    }
  }

  /// 重试 under a message: page 1 when no cards are shown (the refresh is what failed), otherwise the next page.
  Future<void> retry() => _cards.isEmpty ? refresh() : loadMore();

  void _logPage(int index, int got, int added) =>
      _logger.info(LogCategory.ui, 'feed page', {'index': index, 'got': got, 'new': added});

  /// The feed repeats videos across pages, and the grid must not show one twice.
  static List<FeedCard> _appending(List<FeedCard> page, List<FeedCard> cards) {
    final seen = {for (final card in cards) card.bvid};
    return [
      ...cards,
      for (final card in page)
        if (seen.add(card.bvid)) card,
    ];
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
