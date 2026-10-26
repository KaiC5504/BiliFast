part of 'bili_client.dart';

const _dynamicFeatures =
    'itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,'
    'ugcDelete,onlyfansQaCard,commentsNewVersion,avatarAutoTheme,sunflowerStyle,cardsEnhance,eva3CardOpus,'
    'eva3CardVideo,eva3CardComment,eva3CardVote,eva3CardUser';
const _dynamicDetailFeatures =
    'itemOpusStyle,opusBigCover,onlyfansVote,endFooterHidden,decorationCard,onlyfansAssetsV2,ugcDelete,'
    'onlyfansQaCard,editable,opusPrivateVisible,avatarAutoTheme,sunflowerStyle,cardsEnhance,eva3CardOpus,'
    'eva3CardVideo,eva3CardComment,eva3CardVote,eva3CardUser';
const _followingPageSize = 20;
const _bangumiPageSize = 15;

/// The website's WebGL fingerprint fields as a space page sends them (base64 short of its last two characters), for
/// Safari on a Mac as [BiliClient.userAgent] says.
final _dmImgStr = _webGlField('WebGL 1.0');
final _dmCoverImgStr = _webGlField('Apple GPUApple Inc.');

String _webGlField(String text) {
  final encoded = base64.encode(utf8.encode(text));
  return encoded.substring(0, encoded.length - 2);
}

/// 动态: the website's polymer calls with the web login's cookies (the official app's own feed is gRPC).
extension BiliClientDynamic on BiliClient {
  /// 关注's 全部 or 视频; [offset] is the last page's [DynamicPage.offset], null for the first.
  Future<DynamicPage> dynamicFeed({required DynamicFeedType type, String? offset}) => get(
    '/x/polymer/web-dynamic/v1/feed/all',
    query: {
      'type': type.rawValue,
      if (offset != null && offset.isNotEmpty) 'offset': offset,
      'timezone_offset': '-480',
      'features': _dynamicFeatures,
    },
    signed: false,
    decode: DynamicDecode.page,
  );

  /// 最常访问: the portal for the first page, then uplist with [offset].
  Future<DynamicUpList> dynamicUps({String? offset}) => offset == null || offset.isEmpty
      ? get(
          '/x/polymer/web-dynamic/v1/portal',
          query: {'up_list_more': '1', 'web_location': '333.1365'},
          signed: false,
          decode: DynamicDecode.ups,
        )
      : get(
          '/x/polymer/web-dynamic/v1/uplist',
          query: {'offset': offset, 'platform': 'web', 'web_location': '333.1365'},
          signed: false,
          decode: DynamicDecode.ups,
        );

  /// One person's posts: the face sheet (139) and a space's 动态 tab (136).
  Future<DynamicPage> spaceDynamics({required int mid, String? offset}) => get(
    '/x/polymer/web-dynamic/v1/feed/space',
    query: {
      'host_mid': '$mid',
      'offset': offset ?? '',
      'timezone_offset': '-480',
      'features': _dynamicFeatures,
      'platform': 'web',
      'web_location': '333.1387',
      'dm_img_list': '[]',
      'dm_img_str': _dmImgStr,
      'dm_cover_img_str': _dmCoverImgStr,
      'dm_img_inter': '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}',
    },
    signed: true,
    referer: 'https://space.bilibili.com/$mid/dynamic',
    decode: DynamicDecode.page,
  );

  /// A post on its own, with its whole text and IP属地.
  Future<DynamicItem> dynamicDetail(String id) => get(
    '/x/polymer/web-dynamic/v1/detail',
    query: {'id': id, 'timezone_offset': '-480', 'features': _dynamicDetailFeatures},
    signed: false,
    decode: DynamicDecode.detail,
  );

  /// 👍 on a post (`up` 1) or taken back (2).
  Future<void> likeDynamic(String id, {required bool on}) async {
    final envelope = await _postJsonEnvelope(
      '/x/dynamic/feed/dyn/thumb',
      json: {'dyn_id_str': id, 'up': on ? 1 : 2, 'spmid': '333.1365.0.0'},
      referer: 'https://t.bilibili.com/',
      decode: (_) => null,
    );
    if (envelope.code != 0) throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
  }

  /// 我的关注, page [page] from 1.
  Future<FollowingPage> followingList({required int mid, required FollowingOrder order, required int page}) => get(
    '/x/relation/followings',
    query: {
      'vmid': '$mid',
      'pn': '$page',
      'ps': '$_followingPageSize',
      'order': 'desc',
      'order_type': order.rawValue,
    },
    signed: false,
    decode: (json) => DynamicDecode.followings(json, page: page, pageSize: _followingPageSize),
  );

  /// 搜索我的关注.
  Future<FollowingPage> searchFollowings({required int mid, required String name, required int page}) => get(
    '/x/relation/followings/search',
    query: {
      'vmid': '$mid',
      'name': name,
      'pn': '$page',
      'ps': '$_followingPageSize',
      'order': 'desc',
      'order_type': 'attention',
    },
    signed: true,
    decode: (json) => DynamicDecode.followings(json, page: page, pageSize: _followingPageSize),
  );

  /// 我的追番 · 追剧's posters (128), page [page] from 1.
  Future<FollowedBangumiPage> followedBangumi({required int mid, required int page}) => get(
    '/x/space/bangumi/follow/list',
    query: {'type': '1', 'vmid': '$mid', 'pn': '$page', 'ps': '$_bangumiPageSize'},
    signed: false,
    decode: (json) => DynamicDecode.bangumi(json, page: page, pageSize: _bangumiPageSize),
  );
}
