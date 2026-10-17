part of 'bili_client.dart';

/// Ads and game cards in the related list carry a `redirect_url` instead of a playable video.
VideoCard? _relatedItem(Object? json) {
  final redirect = JsonObject.from(json).string('redirect_url') ?? '';
  return redirect.isEmpty ? attempt(() => VideoCard.fromJson(json)) : null;
}

extension BiliClientVideo on BiliClient {
  /// One of [bvid] or [aid].
  Future<VideoDetail> videoDetail({String? bvid, int? aid}) {
    if ((bvid == null) == (aid == null)) throw ArgumentError('videoDetail needs exactly one of bvid and aid');
    final query = bvid != null ? {'bvid': bvid} : {'aid': '$aid'};
    return get('/x/web-interface/wbi/view', query: query, signed: true, decode: VideoDetail.fromJson);
  }

  Future<PlayerInfo> playerInfo({required String bvid, required int cid}) =>
      get('/x/player/wbi/v2', query: {'bvid': bvid, 'cid': '$cid'}, signed: true, decode: PlayerInfo.fromJson);

  /// The server's display string ("1.2万+"), not a number.
  Future<String> onlineCount({required int aid, required String bvid, required int cid}) => get(
    '/x/player/online/total',
    query: {'aid': '$aid', 'bvid': bvid, 'cid': '$cid'},
    signed: false,
    decode: (json) => JsonObject.from(json).string('total') ?? '',
  );

  Future<List<VideoCard>> related({required String bvid}) async {
    final cards = await _getIfPresent(
      '/x/web-interface/archive/related',
      query: {'bvid': bvid},
      signed: false,
      decode: (json) => [for (final card in lossy(_array(json), _relatedItem)) ?card],
    );
    return cards ?? [];
  }

  Future<void> heartbeat({required String bvid, required int cid, required int playedTime}) => postVoid(
    '/x/click-interface/web/heartbeat',
    form: {'bvid': bvid, 'cid': '$cid', 'type': '3', 'played_time': '$playedTime'},
    referer: 'https://www.bilibili.com/video/$bvid',
  );

  Future<void> addToWatchLater({required int aid}) => postVoid('/x/v2/history/toview/add', form: {'aid': '$aid'});
}
