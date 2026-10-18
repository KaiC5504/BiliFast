import 'dart:io' show IOException;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

/// The words for a failed request: Bilibili's own reason when it gave one, otherwise the network or a retry.
String requestFailureMessage(Object error, {String fallback = '加载失败，请稍后重试'}) {
  if (error is BiliError) return error.userMessage;
  // package:http's ClientException, which the app does not import, from both transports.
  if (error is IOException || '$error'.startsWith('ClientException')) return '网络连接失败，请检查网络后重试';
  return fallback;
}

/// The 推荐 feed (port of FeedModel.swift): page 1 on refresh, then the next index for every load more.
class FeedModel extends ChangeNotifier {
  FeedModel({required this._client, Logger? logger}) : _logger = logger ?? Logger.shared;

  final BiliClient _client;
  final Logger _logger;
  List<FeedCard> _cards = const [];
  bool _loading = false;
  String? _error;
  int _nextIndex = 1;

  /// A refresh replaces the list, so a load more that was already running must not append to the new one.
  int _generation = 0;
  bool _disposed = false;

  List<FeedCard> get cards => _cards;
  bool get loading => _loading;

  /// The last load failed; endless scroll waits for a tap on retry instead of asking again by itself.
  String? get error => _error;

  Future<void> refresh() async {
    final mine = ++_generation;
    _loading = true;
    _notify();
    try {
      // The first launch reaches here before the account check has fetched the fingerprint cookies.
      await _client.ensureRiskCookies();
      final page = await _client.recommendFeed(index: 1);
      if (mine != _generation) return;
      _cards = _appending(page, const []);
      _nextIndex = 2;
      _error = null;
    } catch (error) {
      if (mine != _generation) return;
      _logger.warn(LogCategory.ui, 'feed refresh failed', {'error': '$error'});
      _error = requestFailureMessage(error);
    } finally {
      if (mine == _generation) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (_loading) return;
    if (_cards.isEmpty) return refresh();
    final mine = _generation;
    _loading = true;
    _notify();
    try {
      // A page of cards already shown (or only ads) adds nothing, and then no card appears to ask for the next one;
      // ask on, a few times.
      for (var attempt = 0; attempt < 3; attempt++) {
        final page = await _client.recommendFeed(index: _nextIndex);
        if (mine != _generation) return;
        final before = _cards.length;
        _cards = _appending(page, _cards);
        _nextIndex += 1;
        if (_cards.length > before) break;
      }
      _error = null;
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
