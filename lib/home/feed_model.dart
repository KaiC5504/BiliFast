import 'dart:async' show TimeoutException;
import 'dart:io' show IOException;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../playback/playback_controller.dart' show PlaybackFailure;
import '../video/player_prefs.dart';

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

/// Where the cards on screen came from.
enum FeedSource {
  /// The official app's feed (`/x/v2/feed/index`), personalised by the app token; its pages count from 0.
  official,

  /// The website's (`/x/web-interface/wbi/index/top/feed/rcmd`); its pages count from 1.
  web,
}

/// A card after 不感兴趣: the reason it went with, and the 反馈 picked in the reasons sheet, if any.
@immutable
class CardDislike {
  const CardDislike(this.reason, {this.feedback});

  final FeedReason reason;
  final FeedReason? feedback;
}

/// The 推荐 feed (port of FeedModel.swift): page 1 on refresh, then the next index for every load more. With the app
/// token and 开发者's 推荐 on 官方 it reads the official app's feed; without the token it never asks it, since the
/// feed is generic without one. When the official feed answers that the token is refused, the same load is done
/// from the website's, so 推荐 never goes blank.
class FeedModel extends ChangeNotifier {
  FeedModel({required this._client, Logger? logger, bool Function()? officialWanted})
    : _logger = logger ?? Logger.shared,
      _officialWanted = officialWanted ?? (() => PlayerPrefs.shared.officialFeed);

  static const emptyMessage = '暂时没有推荐的视频';
  static const endMessage = '没有更多了';

  /// Pages in a row that may add nothing before a load more gives up and the feed counts as [exhausted].
  static const _emptyPagesAllowed = 3;

  /// The official answers that mean the token is no longer taken (账号未登录, Access Key错误).
  static const _refusedCodes = {-101, -2};

  final BiliClient _client;
  final Logger _logger;
  final bool Function() _officialWanted;
  List<FeedCard> _cards = const [];
  bool _loading = false;
  String? _error;
  bool _exhausted = false;
  int _nextWebIndex = 2;
  int _nextOfficialIndex = 1;
  FeedSource? _source;

  /// Set when the official feed refused the token, so the rest of this scroll asks the website's; a refresh tries
  /// the official one again.
  bool _officialRefused = false;

  final _dislikes = <String, CardDislike>{};
  final _dislikeBusy = <String>{};

  /// A refresh replaces the list, so a load more that was already running must not append to the new one.
  int _generation = 0;
  bool _disposed = false;

  List<FeedCard> get cards => _cards;
  bool get loading => _loading;

  /// Where the last page shown came from; null before the first.
  FeedSource? get source => _source;

  /// Why the cards are missing (nothing on screen) or the next page is (under the cards); endless scroll waits for
  /// [retry] instead of asking again by itself.
  String? get error => _error;

  /// The last load more got only pages of cards already shown (or ads); scrolling stops asking until [retry].
  bool get exhausted => _exhausted;

  /// Whether endless scroll may ask for the next page now.
  bool get canLoadMore => _cards.isNotEmpty && !_loading && _error == null && !_exhausted;

  /// Whether the next load would read the official feed.
  bool get wantsOfficial => _officialWanted() && _client.appToken != null && !_officialRefused;

  /// The card's 不感兴趣, while it stands.
  CardDislike? dislikeOf(FeedCard card) => _dislikes[card.bvid];

  /// Page 1 again. With cards on screen a failure (or an empty page) keeps them, and its words come back for a toast;
  /// with none, it becomes [error]. Null otherwise.
  Future<String?> refresh() async {
    final mine = ++_generation;
    _loading = true;
    _officialRefused = false;
    _notify();
    String? failure;
    try {
      final page = await _fetch(refresh: true);
      if (mine != _generation) return null;
      final fresh = _appending(page.cards, const []);
      _logPage(page, fresh.length);
      if (fresh.isEmpty) {
        failure = emptyMessage;
      } else {
        _cards = fresh;
        _advance(page);
        _source = page.source;
        _dislikes.clear();
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
        final page = await _fetch(refresh: false);
        if (mine != _generation) return;
        final before = _cards.length;
        _cards = _appending(page.cards, _cards);
        _advance(page);
        _source = page.source;
        added = _cards.length - before;
        _logPage(page, added);
      }
      _exhausted = added == 0;
    } catch (error) {
      if (mine != _generation) return;
      _logger.warn(LogCategory.ui, 'feed load more failed', {'error': '$error'});
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

  /// One page from the source this load should read, with the index it asked for. The indexes only move once the
  /// caller knows the page still counts.
  Future<({List<FeedCard> cards, FeedSource source, int index})> _fetch({required bool refresh}) async {
    if (wantsOfficial) {
      final index = refresh ? 0 : _nextOfficialIndex;
      try {
        return (cards: await _client.officialFeed(index: index), source: FeedSource.official, index: index);
      } catch (error) {
        if (!_refused(error)) rethrow;
        _logger.warn(LogCategory.ui, 'official feed refused, web feed instead', {'error': '$error'});
        _officialRefused = true;
      }
    }
    // The first launch reaches here before the account check has fetched the fingerprint cookies.
    if (refresh) await _client.ensureRiskCookies();
    final index = refresh ? 1 : _nextWebIndex;
    return (cards: await _client.recommendFeed(index: index), source: FeedSource.web, index: index);
  }

  static bool _refused(Object error) =>
      error is BiliNoAppTokenError || error is BiliAPIError && _refusedCodes.contains(error.code);

  void _advance(({List<FeedCard> cards, FeedSource source, int index}) page) {
    switch (page.source) {
      case FeedSource.official:
        _nextOfficialIndex = page.index + 1;
      case FeedSource.web:
        _nextWebIndex = page.index + 1;
    }
  }

  /// 不感兴趣 with [reason] (one of the card's [FeedDislike.reasons]): the card turns over at once and turns back if
  /// the call fails, whose words come back for a toast. Taps on a card whose call is still out are dropped.
  Future<String?> dislike(FeedCard card, FeedReason reason) async {
    final data = card.dislike;
    final key = card.bvid;
    if (data == null || _dislikes.containsKey(key) || !_dislikeBusy.add(key)) return null;
    _dislikes[key] = CardDislike(reason);
    _notify();
    try {
      await _send(data, reason);
      return null;
    } catch (error) {
      _logger.warn(LogCategory.ui, 'feed dislike failed', {'error': '$error'});
      _dislikes.remove(key);
      return requestFailureMessage(error);
    } finally {
      _dislikeBusy.remove(key);
      _notify();
    }
  }

  /// 撤销: the card comes back at once, and goes over again if the server keeps the 不感兴趣.
  Future<String?> undo(FeedCard card) async {
    final data = card.dislike;
    final key = card.bvid;
    final standing = _dislikes[key];
    if (data == null || standing == null || !_dislikeBusy.add(key)) return null;
    _dislikes.remove(key);
    _notify();
    final reason = standing.reason;
    try {
      await _client.feedDislikeCancel(
        goto: data.goto,
        id: data.id,
        reasonId: reason.kind == FeedReasonKind.dislike ? reason.id : null,
        feedbackId: reason.kind == FeedReasonKind.feedback ? reason.id : null,
      );
      return null;
    } catch (error) {
      _logger.warn(LogCategory.ui, 'feed dislike undo failed', {'error': '$error'});
      _dislikes[key] = standing;
      return requestFailureMessage(error);
    } finally {
      _dislikeBusy.remove(key);
      _notify();
    }
  }

  /// The reasons sheet's pick on a card already turned over; it is forgotten again if the call fails.
  Future<String?> sendReason(FeedCard card, FeedReason feedback) async {
    final data = card.dislike;
    final key = card.bvid;
    final standing = _dislikes[key];
    if (data == null || standing == null || !_dislikeBusy.add(key)) return null;
    _dislikes[key] = CardDislike(standing.reason, feedback: feedback);
    _notify();
    try {
      await _send(data, feedback);
      return null;
    } catch (error) {
      _logger.warn(LogCategory.ui, 'feed dislike reason failed', {'error': '$error'});
      if (_dislikes[key]?.feedback == feedback) _dislikes[key] = standing;
      return requestFailureMessage(error);
    } finally {
      _dislikeBusy.remove(key);
      _notify();
    }
  }

  Future<void> _send(FeedDislike data, FeedReason reason) => _client.feedDislike(
    goto: data.goto,
    id: data.id,
    reasonId: reason.kind == FeedReasonKind.dislike ? reason.id : null,
    feedbackId: reason.kind == FeedReasonKind.feedback ? reason.id : null,
  );

  void _logPage(({List<FeedCard> cards, FeedSource source, int index}) page, int added) => _logger.info(
    LogCategory.ui,
    'feed page',
    {'source': page.source.name, 'index': page.index, 'got': page.cards.length, 'new': added},
  );

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
