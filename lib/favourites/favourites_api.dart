import 'package:bili_core/api.dart';

/// 我的收藏's calls, the website's. 视频 has no web list, so it is the official app's own on the same host
/// (`/x/v3/fav/tab/fav`), sent with the cookies like the rest.
abstract interface class FavouritesApi {
  /// The account's own folders, the default first.
  Future<List<FavFolder>> folders({required int mid});

  /// Page [page] (from 1) of a folder's videos; a card's covers ask for 3.
  Future<FavFolderPage> folderVideos({required int folderId, required int page, int pageSize = 20});

  /// Takes the video [aid] out of the folder [folderId].
  Future<void> removeFromFolder({required int folderId, required int aid});

  /// 视频's tab id, null when the answer has none.
  Future<int?> videosTab();

  /// A page of 视频; [after] is the last page's `FavTabPage.next`.
  Future<FavTabPage> allVideos({required int tabId, FavTabCursor? after});

  /// Takes the video [aid] out of every folder.
  Future<void> removeEverywhere({required int aid});
}

class ClientFavouritesApi implements FavouritesApi {
  ClientFavouritesApi(this._client);

  final BiliClient _client;

  @override
  Future<List<FavFolder>> folders({required int mid}) => _client.createdFolders(mid: mid);

  @override
  Future<FavFolderPage> folderVideos({required int folderId, required int page, int pageSize = 20}) =>
      _client.favFolderVideos(folderId: folderId, page: page, pageSize: pageSize);

  @override
  Future<void> removeFromFolder({required int folderId, required int aid}) =>
      _client.updateFavourites(aid: aid, add: const [], remove: [folderId]);

  @override
  Future<int?> videosTab() => _client.favVideosTab();

  @override
  Future<FavTabPage> allVideos({required int tabId, FavTabCursor? after}) =>
      _client.favAllVideos(tabId: tabId, after: after);

  @override
  Future<void> removeEverywhere({required int aid}) => _client.unfavouriteEverywhere(aid: aid);
}
