part of 'bili_client.dart';

/// Ads and live rooms share the list; only `goto == "av"` rows are videos.
FeedCard? _feedItem(Object? json) {
  final object = JsonObject.from(json);
  if (object.string('goto') != 'av') return null;
  return attempt(() => FeedCard.fromJson(json));
}

HistoryPage _historyPayload(Object? json) {
  final object = JsonObject.from(json);
  final rows = object.list('list') ?? const [];
  final cursor = object.nested('cursor');
  final max = cursor?.count('max') ?? 0;
  final viewAt = cursor?.count('view_at') ?? 0;
  // The last page answers with a zero cursor, and the server reads zeros as "from the top", so passing it back would loop.
  // Rows that failed to decode still count: the cursor must move past them.
  return HistoryPage(
    items: lossy(rows, HistoryItem.fromJson),
    next: rows.isEmpty || (max == 0 && viewAt == 0) ? null : HistoryCursor(max: max, viewAt: viewAt),
  );
}

extension BiliClientFeed on BiliClient {
  /// `index` is the 0-based page of the endless scroll; pull to refresh starts again at 0.
  Future<List<FeedCard>> recommendFeed({required int index}) async {
    final position = '$index';
    final query = {
      'fresh_type': '4',
      'ps': '12',
      'fresh_idx': position,
      'fresh_idx_1h': position,
      'brush': position,
      'feed_version': 'V8',
    };
    final cards = await _getIfPresent(
      '/x/web-interface/wbi/index/top/feed/rcmd',
      query: query,
      signed: true,
      decode: (json) => [for (final card in JsonObject.from(json).lossyList('item', _feedItem)) ?card],
    );
    return cards ?? [];
  }

  /// Needs the login cookie. `type` filters to videos and `business` names the kind of cursor row, which is then always archive.
  Future<HistoryPage> history({HistoryCursor? after}) async {
    final query = {
      'max': '${after?.max ?? 0}',
      'view_at': '${after?.viewAt ?? 0}',
      'business': 'archive',
      'type': 'archive',
      'ps': '20',
    };
    final payload = await _getIfPresent(
      '/x/web-interface/history/cursor',
      query: query,
      signed: false,
      decode: _historyPayload,
    );
    return payload ?? const HistoryPage(items: [], next: null);
  }
}
