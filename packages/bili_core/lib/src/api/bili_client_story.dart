part of 'bili_client.dart';

/// What the iPhone app 9.18.0 sends on every page of 竖屏's feed beside its common fields
/// (docs/reference/official-iphone-calls.md).
const _storyFeedQuery = {
  'client_attr': '1',
  'collection_second_feed_iaa': '1',
  'contain': '0',
  'extra_content': '{"story_video_bg_play_listen":"0"}',
  'fnval': '17364',
  'fnver': '0',
  'force_host': '0',
  'fourk': '1',
  'material_no': '0',
  'network': 'wifi',
  'player_extra_content': IphoneLabels.screen,
  'player_net': '1',
  'product_id': '',
  'product_type': '',
  'qn': '120',
  'qn_policy': '0',
  'room_id': '0',
  'server_name': '',
  'soft_fnval': '0',
  'sp_id': '',
  'statistics': '{"appId":1,"platform":1,"version":"${IphoneLabels.version}"}',
  'teenagers_age': '16',
  'video_mode': '1',
  'voice_balance': '1',
};

/// Only videos: live rooms (`vertical_live`), ads (`vertical_ad_av`, or anything with `ad_info`) and items without
/// a bvid or a cid are dropped.
StoryItem? _storyItem(Object? json) {
  if (json is! Map<String, Object?>) return null;
  if (json['goto'] != 'vertical_av' || json['ad_info'] != null) return null;
  return attempt(() => StoryItem.fromJson(json));
}

/// Each page's item gotos in order, names only.
List<String> _storyItemTypes(Object? json) {
  if (json is! Map<String, Object?>) return const [];
  final items = json['items'];
  if (items is! List) return const [];
  return [
    for (final item in items)
      if (item is Map<String, Object?>) '${item['goto'] ?? '?'}${item['ad_info'] != null ? '/ad' : ''}',
  ];
}

/// 竖屏's feed, asked as the official iPhone app asks it (docs/reference/official-iphone-calls.md).
extension BiliClientStory on BiliClient {
  /// The videos after [aid] / [cid], the video 竖屏 was entered on: [page] counts from 1 (`display_id`), and page 1
  /// names where 竖屏 was entered from ([entry]) and starts with the entered video itself. [trackId] is the entry
  /// card's, the same on every page. Only `vertical_av` items come back; live rooms and ads are dropped. Without the
  /// app token it throws [BiliError.noAppToken], and under an Android one a [StateError], with nothing sent.
  Future<List<StoryItem>> storyFeed({
    required int aid,
    required int cid,
    required int page,
    required PlaySource entry,
    String? trackId,
  }) async {
    const path = '/x/v2/feed/index/story';
    final token = _officialToken(true)!;
    if (token.identity != OfficialIdentity.iphone) {
      throw StateError("竖屏's feed is only known for the iPhone identity");
    }
    final first = page == 1;
    final envelope = await _getEnvelope(
      path,
      query: _officialSigned({
        ..._storyFeedQuery,
        'aid': '$aid',
        'cid': '$cid',
        'trackid': ?trackId,
        'display_id': '$page',
        'pull': first ? '1' : '0',
        if (first) ...{
          if (entry.from.isNotEmpty) 'from': entry.from,
          'from_spmid': entry.fromSpmid,
          'spmid': PlaySource.verticalPage,
          'auto_play': '0',
          'open_event': 'cold',
          'epid': '0',
          'ogv_style': '0',
        },
      }, token),
      signed: false,
      host: BiliClient.appAPI,
      sendCookies: false,
      extraHeaders: _officialHeaders(const {}, token),
      decode: (json) {
        _logger.info(LogCategory.api, 'story item types', {'items': _storyItemTypes(json).join(' ')});
        return [for (final item in JsonObject.from(json).lenientList('items', _storyItem)) ?item];
      },
    );
    final checked = _officialChecked(envelope, token);
    if (checked.code != 0) throw BiliError.api(code: checked.code, message: checked.message ?? '');
    return checked.data ?? const [];
  }
}
