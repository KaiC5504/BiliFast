part of 'bili_client.dart';

/// 我的收藏's calls, the website's (as PiliPlus keeps them): the account's folders, a folder's videos, removing.
/// 视频 (every favourite, across folders) has no web call; it is the official app's own list on the same host, sent
/// with the cookies like the rest. Removing from one folder is `updateFavourites`, making one `createFolder`.
extension BiliClientFav on BiliClient {
  /// Page [page] (from 1) of the account's own folders, the default first, with their covers.
  Future<FavFolderListPage> createdFolders({required int mid, int page = 1, int pageSize = 20}) async {
    final answer = await _getIfPresent(
      '/x/v3/fav/folder/created/list',
      query: {'pn': '$page', 'ps': '$pageSize', 'up_mid': '$mid'},
      signed: false,
      decode: FavFolderListPage.fromJson,
    );
    return answer ?? FavFolderListPage.empty;
  }

  /// Uploads a picture for a new folder's 封面; the answer is its address, for `createFolder`'s cover.
  Future<String> uploadFolderCover({required List<int> bytes, required String filename}) => _postFile(
    '/x/upload/web/image',
    form: {'bucket': 'medialist', 'dir': 'cover'},
    file: (field: 'file', filename: filename, contentType: BiliClientComments._imageType(filename), bytes: bytes),
    decode: decodeUploadedCover,
  );

  /// Page [page] (from 1) of a folder's videos, the latest favourite first; a card's covers ask for 3.
  Future<FavFolderPage> favFolderVideos({required int folderId, required int page, int pageSize = 20}) async {
    final answer = await _getIfPresent(
      '/x/v3/fav/resource/list',
      query: {
        'media_id': '$folderId',
        'pn': '$page',
        'ps': '$pageSize',
        'keyword': '',
        'order': 'mtime',
        'type': '0',
        'tid': '0',
        'platform': 'web',
      },
      signed: false,
      decode: FavFolderPage.fromJson,
    );
    return answer ?? FavFolderPage.empty;
  }

  /// 视频's tab id, from the tabs the official app's 我的收藏 is built from.
  Future<int?> favVideosTab() =>
      _getIfPresent<int?>('/x/v3/fav/tab', query: {'tab_id': '0'}, signed: false, decode: favVideosTabId);

  /// A page of 视频, the latest favourite first; [after] is the last page's `FavTabPage.next`.
  Future<FavTabPage> favAllVideos({required int tabId, FavTabCursor? after}) async {
    final answer = await _getIfPresent(
      '/x/v3/fav/tab/fav',
      query: {
        'start_oid': '${after?.oid ?? 0}',
        'start_otype': '${after?.otype ?? 0}',
        'tab_id': '$tabId',
        'start_score': '${after?.score ?? 0}',
        'page_type': '1',
      },
      signed: false,
      decode: FavTabPage.fromJson,
    );
    return answer ?? FavTabPage.empty;
  }

  /// Takes the video out of every folder that holds it (视频's 取消收藏).
  Future<void> unfavouriteEverywhere({required int aid}) =>
      postVoid('/x/v3/fav/resource/unfav-all', form: {'rid': '$aid', 'type': '2'});
}
