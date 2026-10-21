part of 'bili_client.dart';

String _videoReferer(String bvid) => 'https://www.bilibili.com/video/$bvid';

extension BiliClientActions on BiliClient {
  Future<VideoRelation> relation({required int aid, required String bvid}) => get(
    '/x/web-interface/archive/relation',
    query: {'aid': '$aid', 'bvid': bvid},
    signed: false,
    decode: VideoRelation.fromJson,
  );

  Future<UploaderCard> uploaderCard({required int mid}) => get(
    '/x/web-interface/card',
    query: {'mid': '$mid', 'photo': 'false'},
    signed: false,
    decode: UploaderCard.fromJson,
  );

  Future<void> like({required int aid, required String bvid, required bool on}) => postVoid(
    '/x/web-interface/archive/like',
    form: {'aid': '$aid', 'like': on ? '1' : '2'},
    referer: _videoReferer(bvid),
  );

  /// 一键三连: like, coin and favourite in one call. The server spends up to two coins and says how many.
  Future<TripleResult> triple({required int aid, required String bvid}) => post(
    '/x/web-interface/archive/like/triple',
    form: {
      'aid': '$aid',
      'eab_x': '2',
      'ramval': '0',
      'source': 'web_normal',
      'ga': '1',
      'spmid': '333.788.0.0',
      'statistics': '{"appId":100,"platform":5}',
    },
    referer: _videoReferer(bvid),
    decode: TripleResult.fromJson,
  );

  Future<void> coin({required int aid, required String bvid, required int multiply, required bool alsoLike}) =>
      postVoid(
        '/x/web-interface/coin/add',
        form: {'aid': '$aid', 'multiply': '$multiply', 'select_like': alsoLike ? '1' : '0'},
        referer: _videoReferer(bvid),
      );

  Future<double> coinBalance() => get(
    '/site/getCoin',
    signed: false,
    host: 'https://account.bilibili.com',
    decode: (json) => JsonObject.from(json).number('money') ?? 0,
  );

  /// The account's own folders; `contains` tells which of them already hold the video `aid`.
  Future<List<FavFolder>> favouriteFolders({required int mid, required int aid}) async {
    final folders = await _getIfPresent(
      '/x/v3/fav/folder/created/list-all',
      query: {'up_mid': '$mid', 'rid': '$aid', 'type': '2'},
      signed: false,
      decode: (json) => JsonObject.from(json).lossyList('list', FavFolder.fromJson),
    );
    return folders ?? [];
  }

  /// `rid`/`type` is the single-video form and `resources` the batch form; sending both keeps either reading working.
  Future<void> updateFavourites({required int aid, required List<int> add, required List<int> remove}) => postVoid(
    '/x/v3/fav/resource/batch-deal',
    form: {
      'rid': '$aid',
      'type': '2',
      'resources': '$aid:2',
      'add_media_ids': add.join(','),
      'del_media_ids': remove.join(','),
    },
  );

  /// [cover] is an address from `uploadFolderCover`; without one the folder shows its newest video's.
  Future<FavFolder> createFolder({
    required String title,
    required bool isPrivate,
    String intro = '',
    String cover = '',
  }) => post(
    '/x/v3/fav/folder/add',
    form: {
      'title': title,
      if (intro.isNotEmpty) 'intro': intro,
      'privacy': isPrivate ? '1' : '0',
      if (cover.isNotEmpty) 'cover': cover,
    },
    decode: FavFolder.fromJson,
  );

  Future<void> countShare({required int aid}) => postVoid('/x/web-interface/share/add', form: {'aid': '$aid'});

  Future<void> follow({required int mid, required bool on}) => postVoid(
    '/x/relation/modify',
    form: {'fid': '$mid', 'act': on ? '1' : '2', 're_src': '14'},
    referer: 'https://space.bilibili.com/$mid',
  );

  /// 订阅 (the 合集 sheet's 收藏) adds or removes a whole 合集.
  Future<void> favSeason({required int seasonId, required bool on}) => postVoid(
    on ? '/x/v3/fav/season/fav' : '/x/v3/fav/season/unfav',
    form: {'platform': 'web', 'season_id': '$seasonId'},
  );

  Future<List<VideoTag>> tags({required String bvid, required int cid}) async {
    final tags = await _getIfPresent(
      '/x/web-interface/view/detail/tag',
      query: {'bvid': bvid, 'cid': '$cid'},
      signed: false,
      decode: (json) => lossy(_array(json), VideoTag.fromJson),
    );
    return tags ?? [];
  }
}

List<Object?> _array(Object? json) =>
    json is List ? List<Object?>.of(json) : throw DecodeError('expected array, got ${json.runtimeType}');
