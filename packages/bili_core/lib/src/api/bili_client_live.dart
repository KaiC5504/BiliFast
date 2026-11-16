part of 'bili_client.dart';

const _liveWebLocation = '444.8';
const _liveAreaPageSize = 20;
const _liveFollowingPageSize = 9;
const _liveRankPageSize = 50;
const _liveGuardPageSize = 20;

/// PiliPlus's live calls' fields beside the Android identity's common ones.
const _liveAndroidFields = {
  'actionKey': 'appkey',
  'device': 'android',
  'device_name': 'android',
  'device_type': '0',
  'disable_rcmd': '0',
  'scale': '2',
};

/// The iPhone identity's model and scale; no capture of its live calls backs them.
const _liveIphoneFields = {'device_name': IphoneLabels.model, 'scale': '3'};

const _liveAppFields = {'fnval': '912', 'https_url_req': '1', 'network': 'wifi'};

/// PiliPlus's headers for the Android app's live calls; the fingerprints and trace id are its placeholders, the same
/// for everyone.
const _liveAndroidHeaders = {
  'app-key': 'android',
  'env': 'prod',
  'session_id': '11111111',
  'fp_local': '1111111111111111111111111111111111111111111111111111111111111111',
  'fp_remote': '1111111111111111111111111111111111111111111111111111111111111111',
  'x-bili-trace-id': '11111111111111111111111111111111:1111111111111111:0:0',
  'x-bili-aurora-eid': '',
  'x-bili-aurora-zone': '',
};

String _liveRoomReferer(int roomId) => 'https://live.bilibili.com/$roomId';

/// 直播's calls, on `api.live.bilibili.com`: the website's, apart from the tab's feed and area lists, which are the
/// official app's.
extension BiliClientLive on BiliClient {
  /// The 直播 tab's feed (`xlive/app-interface/v2/index/feed`) under the held identity, page [page] from 1.
  Future<LiveFeedPage> liveFeed({required int page}) =>
      _liveOfficialGet('/xlive/app-interface/v2/index/feed', {'page': '$page'}, (json) {
        _logger.info(LogCategory.api, 'live feed card types', {'cards': LiveDecode.cardTypes(json).join(' ')});
        return LiveDecode.feed(json, page: page);
      }, relation: true);

  /// An area tab's rooms, page [page] from 1 (`second/getList`, the official app's). 推荐's rooms are the feed's.
  Future<LiveCardPage> liveArea(LiveArea area, {required int page}) async {
    if (area.isRecommend) {
      final feed = await liveFeed(page: page);
      return LiveCardPage(page: page, cards: feed.cards, hasMore: feed.hasMore);
    }
    return _liveOfficialGet('/xlive/app-interface/v2/second/getList', {
      'area_id': '${area.id}',
      'parent_area_id': '${area.parentId}',
      'page': '$page',
      'page_size': '$_liveAreaPageSize',
      'module_select': '0',
      'qn': '0',
      'tag_version': '1',
    }, (json) => LiveDecode.areaPage(json, page: page, pageSize: _liveAreaPageSize));
  }

  /// 206: the followed rooms that are live, page [page] from 1.
  Future<LiveCardPage> liveFollowing({required int page}) => get(
    '/xlive/web-ucenter/user/following',
    query: {'page': '$page', 'page_size': '$_liveFollowingPageSize', 'ignoreRecord': '1', 'hit_ab': 'true'},
    signed: false,
    host: BiliClient.liveAPI,
    referer: 'https://live.bilibili.com/',
    decode: (json) => LiveDecode.following(json, page: page),
  );

  /// The room's status and its HLS stream at [qn] (the room's default when null).
  Future<LivePlayInfo> livePlayInfo(int roomId, {int? qn}) => get(
    '/xlive/web-room/v2/index/getRoomPlayInfo',
    query: {
      'room_id': '$roomId',
      'protocol': '0,1',
      'format': '0,1,2',
      'codec': '0,1',
      'qn': '${qn ?? 10000}',
      'platform': 'web',
      'ptype': '8',
      'dolby': '5',
      'panorama': '1',
      'web_location': _liveWebLocation,
    },
    signed: true,
    host: BiliClient.liveAPI,
    referer: _liveRoomReferer(roomId),
    decode: (json) {
      final info = LiveDecode.playInfo(json, qn: qn);
      if (info.unsupportedStream) {
        _logger.warn(LogCategory.api, 'live stream unsupported', {'offered': info.offeredStreams.toSet().join(' ')});
      }
      return info;
    },
  );

  /// The header's and the chat's room card's words: `getInfoByRoom`, then, logged in, the anchor's card for 关注
  /// (the room's answer doesn't say it). A failed card leaves 关注 off rather than failing the room.
  Future<LiveRoomInfo> liveRoomInfo(int roomId) async {
    final info = await get(
      '/xlive/web-room/v1/index/getInfoByRoom',
      query: {'room_id': '$roomId', 'web_location': _liveWebLocation},
      signed: true,
      host: BiliClient.liveAPI,
      referer: _liveRoomReferer(roomId),
      decode: LiveDecode.roomInfo,
    );
    if (info.uid <= 0 || cookies.value('SESSDATA') == null) return info;
    final bool following;
    try {
      following = (await uploaderCard(mid: info.uid)).following;
    } on BiliError catch (error) {
      _logger.warn(LogCategory.api, 'live anchor relation failed', {'error': error.runtimeType.toString()});
      return info;
    }
    return LiveRoomInfo(
      roomId: info.roomId,
      uid: info.uid,
      title: info.title,
      cover: info.cover,
      anchorName: info.anchorName,
      anchorFace: info.anchorFace,
      anchorFrame: info.anchorFrame,
      verify: info.verify,
      description: info.description,
      areaName: info.areaName,
      likeCount: info.likeCount,
      watchedText: info.watchedText,
      onlineCount: info.onlineCount,
      topFaces: info.topFaces,
      rankChips: info.rankChips,
      following: following,
    );
  }

  /// The danmaku socket's token and hosts.
  Future<LiveDanmuInfo> liveDanmuInfo(int roomId) => get(
    '/xlive/web-room/v1/index/getDanmuInfo',
    query: {'id': '$roomId', 'type': '0', 'web_location': _liveWebLocation},
    signed: true,
    host: BiliClient.liveAPI,
    referer: _liveRoomReferer(roomId),
    decode: LiveDecode.danmuInfo,
  );

  /// The chat's last lines before the socket's.
  Future<List<LiveChatMessage>> liveHistory(int roomId) => get(
    '/xlive/web-room/v1/dM/gethistory',
    query: {'roomid': '$roomId'},
    signed: false,
    host: BiliClient.liveAPI,
    referer: _liveRoomReferer(roomId),
    decode: LiveDecode.history,
  );

  /// The 醒目留言 still showing.
  Future<List<LiveSuperChat>> liveSuperChats(int roomId) => get(
    '/av/v1/SuperChat/getMessageList',
    query: {'room_id': '$roomId'},
    signed: false,
    host: BiliClient.liveAPI,
    referer: _liveRoomReferer(roomId),
    decode: (json) => LiveDecode.superChats(json, now: now()),
  );

  /// 房间观众's 在线榜, page [page] from 1; [anchorUid] is the room's `uid`.
  Future<LiveRankPage> liveRank(int roomId, {required int anchorUid, required int page}) => get(
    '/xlive/general-interface/v1/rank/queryContributionRank',
    query: {
      'ruid': '$anchorUid',
      'room_id': '$roomId',
      'page': '$page',
      'page_size': '$_liveRankPageSize',
      'type': 'online_rank',
      'switch': 'contribution_rank',
      'platform': 'web',
      'web_location': _liveWebLocation,
    },
    signed: true,
    host: BiliClient.liveAPI,
    referer: _liveRoomReferer(roomId),
    decode: (json) => LiveDecode.rank(json, page: page, pageSize: _liveRankPageSize),
  );

  /// 大航海's [tab], page [page] from 1 (`guardTab/topListNew`, `typ` 3 周, 4 月, 5 the whole 陪伴).
  Future<LiveGuardPage> liveGuards(
    int roomId, {
    required int anchorUid,
    required LiveGuardTab tab,
    required int page,
  }) => get(
    '/xlive/app-room/v2/guardTab/topListNew',
    query: {
      'roomid': '$roomId',
      'ruid': '$anchorUid',
      'page': '$page',
      'page_size': '$_liveGuardPageSize',
      'typ': switch (tab) {
        LiveGuardTab.weekly => '3',
        LiveGuardTab.monthly => '4',
        LiveGuardTab.companion => '5',
      },
    },
    signed: false,
    host: BiliClient.liveAPI,
    referer: _liveRoomReferer(roomId),
    decode: (json) => LiveDecode.guards(json, page: page, pageSize: _liveGuardPageSize),
  );

  /// The emote packages the viewer may send in the room.
  Future<List<LiveEmotePackage>> liveEmotes(int roomId) => get(
    '/xlive/web-ucenter/v2/emoticon/GetEmoticons',
    query: {'platform': 'pc', 'room_id': '$roomId'},
    signed: false,
    host: BiliClient.liveAPI,
    referer: _liveRoomReferer(roomId),
    decode: LiveDecode.emotes,
  );

  /// Sends [text] as a danmaku.
  Future<void> liveSend(int roomId, String text) {
    if (text.trim().isEmpty) throw ArgumentError('nothing to send');
    return _liveSend(roomId, {
      'msg': text,
      'room_type': '0',
      'jumpfrom': '0',
      'reply_mid': '0',
      'reply_attr': '0',
      'replay_dmid': '',
      'statistics': '{"appId":100,"platform":5}',
      'reply_type': '0',
      'reply_uname': '',
    });
  }

  /// Sends [emote] as a whole-message danmaku. The website sends `emoticonOptions` as its script stringifies an
  /// object, in place of the text's reply fields.
  Future<void> liveSendEmote(int roomId, LiveEmote emote) {
    if (emote.unique.isEmpty) throw ArgumentError('the emote has no emoticon_unique');
    return _liveSend(roomId, {'msg': emote.unique, 'dm_type': '1', 'emoticonOptions': '[object Object]'});
  }

  Future<void> _liveSend(int roomId, Map<String, String> fields) async {
    final token = _liveCsrf();
    final envelope = await _postEnvelope(
      '/msg/send',
      query: const {'web_location': _liveWebLocation},
      signed: true,
      form: {
        'bubble': '0',
        'color': '16777215',
        'mode': '1',
        'fontsize': '25',
        'rnd': '$_unixSeconds',
        'roomid': '$roomId',
        ...fields,
        'csrf_token': token,
      },
      host: BiliClient.liveAPI,
      referer: _liveRoomReferer(roomId),
      decode: (_) => null,
    );
    if (envelope.code != 0) throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
    // A dropped danmaku still answers 0, with a word in `message` (`f`, `k`: believed filtered / the room's blocked
    // words); a sent one leaves it empty or says 0.
    final word = (envelope.message ?? '').trim();
    if (word.isEmpty || const {'0', 'ok', 'success'}.contains(word.toLowerCase())) return;
    final logged = word.length <= 24 ? word : '(${word.length} chars)';
    _logger.warn(LogCategory.api, 'live send dropped', {'message': logged});
    throw BiliError.api(code: 0, message: word == 'f' || word == 'k' ? '您发送的弹幕被屏蔽了' : word);
  }

  /// [clicks] double taps' 点赞, sent as one. The website signs the form itself, csrf among it.
  Future<void> liveLike(int roomId, {required int anchorUid, required int uid, required int clicks}) async {
    final form = await _wbiSignedFields({
      'click_time': '$clicks',
      'room_id': '$roomId',
      'uid': '$uid',
      'anchor_id': '$anchorUid',
      'web_location': _liveWebLocation,
      'csrf': _liveCsrf(),
    });
    await postVoid(
      '/xlive/app-ucenter/v1/like_info_v3/like/likeReportV3',
      form: form,
      host: BiliClient.liveAPI,
      referer: _liveRoomReferer(roomId),
    );
  }

  /// `roomEntryAction`: the room goes into 历史记录. The website names csrf in the URL as well as the form.
  Future<void> liveEnter(int roomId) async {
    final envelope = await _postEnvelope(
      '/xlive/web-room/v1/index/roomEntryAction',
      query: {'csrf': _liveCsrf()},
      form: {'room_id': '$roomId', 'platform': 'pc'},
      host: BiliClient.liveAPI,
      referer: _liveRoomReferer(roomId),
      decode: (_) => null,
    );
    if (envelope.code != 0) throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
  }

  String _liveCsrf() => csrf ?? (throw const BiliError.api(code: -101, message: '账号未登录'));

  /// [fields] with `wts` and `w_rid` added, as the website signs a form.
  Future<Map<String, String>> _wbiSignedFields(Map<String, String> fields) async {
    final query = WBI.signedQuery(fields, mixinKey: await _mixinKey(), wts: _unixSeconds);
    return {
      for (final pair in query.split('&'))
        Uri.decodeComponent(pair.substring(0, pair.indexOf('='))): Uri.decodeComponent(
          pair.substring(pair.indexOf('=') + 1),
        ),
    };
  }

  /// An official live call under the held identity, its token as `access_key` when one is held (the lists answer
  /// without one), sent without cookies. [relation] asks the feed's 我的关注 strip, which needs the token.
  Future<T> _liveOfficialGet<T>(
    String path,
    Map<String, String> fields,
    JsonDecode<T> decode, {
    bool relation = false,
  }) async {
    final token = appToken;
    final iphone = (token?.identity ?? officialIdentity) == OfficialIdentity.iphone;
    final envelope = await _getEnvelope(
      path,
      query: _officialSigned({
        ...iphone ? _liveIphoneFields : _liveAndroidFields,
        ..._liveAppFields,
        if (relation && token != null) 'relation_page': '1',
        ...fields,
      }, token),
      signed: false,
      host: BiliClient.liveAPI,
      sendCookies: false,
      extraHeaders: _officialHeaders(iphone ? const {} : _liveAndroidHeaders, token),
      decode: decode,
    );
    return _checked(_officialChecked(envelope, token));
  }
}
