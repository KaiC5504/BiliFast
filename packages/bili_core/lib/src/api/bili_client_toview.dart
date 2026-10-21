part of 'bili_client.dart';

const _toViewListPath = '/x/v2/history/toview/web';
const _toViewDeletePath = '/x/v2/history/toview/v2/dels';
const _toViewClearPath = '/x/v2/history/toview/clear';
const _toViewCopyPath = '/x/v2/history/toview/copy';
const _toViewMovePath = '/x/v2/history/toview/move';

/// 稍后再看's calls, the website's (as PiliPlus keeps them): the list, removing, clearing, and copying or moving to a
/// 收藏 folder. All need the login cookie.
extension BiliClientToView on BiliClient {
  static const pageSize = 20;

  /// [page] counts from 1. The list ends when a page comes back empty or the pages so far cover the server's count;
  /// rows dropped while decoding still count, so a page of bangumi doesn't stop it early.
  Future<WatchLaterListPage> watchLater({
    required WatchLaterFilter filter,
    required bool oldestFirst,
    required int page,
  }) async {
    final query = {
      'pn': '$page',
      'ps': '$pageSize',
      'viewed': '${filter.viewed}',
      'key': '',
      'asc': '$oldestFirst',
      'need_split': 'true',
      'web_location': '333.881',
    };
    final payload = await _getIfPresent(
      _toViewListPath,
      query: query,
      signed: true,
      decode: (json) {
        final object = JsonObject.from(json);
        final rows = object.list('list') ?? const [];
        final total = object.count('count');
        return WatchLaterListPage(
          items: lossy(rows, WatchLaterItem.fromJson),
          total: total,
          hasMore: rows.isNotEmpty && page * pageSize < total,
        );
      },
    );
    return payload ?? WatchLaterListPage.empty;
  }

  Future<void> removeFromWatchLater({required List<int> aids}) async {
    _checkAids(aids);
    return postVoid(_toViewDeletePath, form: {'resources': aids.join(',')});
  }

  Future<void> clearWatchLater(WatchLaterClean kind) =>
      postVoid(_toViewClearPath, form: {'clean_type': '${kind.cleanType}'});

  /// [mid] is the account's own.
  Future<void> copyWatchLater({required List<int> aids, required int folderId, required int mid}) async {
    _checkAids(aids);
    return postVoid(
      _toViewCopyPath,
      form: {'tar_media_id': '$folderId', 'mid': '$mid', 'resources': aids.join(','), 'platform': 'web'},
    );
  }

  /// Moving also takes the videos out of 稍后再看.
  Future<void> moveWatchLater({required List<int> aids, required int folderId}) async {
    _checkAids(aids);
    return postVoid(
      _toViewMovePath,
      form: {'tar_media_id': '$folderId', 'resources': aids.join(','), 'platform': 'web'},
    );
  }

  /// An empty list or a row decoded without its aid fails here instead of posting an empty or zero resource.
  static void _checkAids(List<int> aids) {
    if (aids.isEmpty || aids.any((aid) => aid <= 0)) throw const BiliError.decoding('稍后再看 call without aids');
  }
}
