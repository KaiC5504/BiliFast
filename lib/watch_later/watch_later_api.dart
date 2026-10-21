import 'package:bili_core/api.dart';

/// 稍后再看's calls, the website's.
abstract interface class WatchLaterApi {
  /// [page] counts from 1.
  Future<WatchLaterListPage> list({required WatchLaterFilter filter, required bool oldestFirst, required int page});

  Future<void> remove({required List<int> aids});

  Future<void> clear(WatchLaterClean kind);

  /// The account's own 收藏 folders, for 复制到 and 移动到; [aid] is one of the videos going there.
  Future<List<FavFolder>> folders({required int mid, required int aid});

  Future<void> copyToFolder({required List<int> aids, required int folderId, required int mid});

  /// Also takes the videos out of 稍后再看.
  Future<void> moveToFolder({required List<int> aids, required int folderId});
}

class ClientWatchLaterApi implements WatchLaterApi {
  ClientWatchLaterApi(this._client);

  final BiliClient _client;

  @override
  Future<WatchLaterListPage> list({required WatchLaterFilter filter, required bool oldestFirst, required int page}) =>
      _client.watchLater(filter: filter, oldestFirst: oldestFirst, page: page);

  @override
  Future<void> remove({required List<int> aids}) => _client.removeFromWatchLater(aids: aids);

  @override
  Future<void> clear(WatchLaterClean kind) => _client.clearWatchLater(kind);

  @override
  Future<List<FavFolder>> folders({required int mid, required int aid}) => _client.favouriteFolders(mid: mid, aid: aid);

  @override
  Future<void> copyToFolder({required List<int> aids, required int folderId, required int mid}) =>
      _client.copyWatchLater(aids: aids, folderId: folderId, mid: mid);

  @override
  Future<void> moveToFolder({required List<int> aids, required int folderId}) =>
      _client.moveWatchLater(aids: aids, folderId: folderId);
}
