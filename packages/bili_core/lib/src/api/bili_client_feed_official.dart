part of 'bili_client.dart';

/// PiliPlus's `rcmdVideoListApp` query, less what changes per page.
const _officialFeedQuery = {
  'build': '8430300',
  'c_locale': 'zh_CN',
  'channel': 'master',
  'column': '2',
  'device': 'phone',
  'device_name': 'android',
  'device_type': '0',
  'disable_rcmd': '0',
  'flush': '8',
  'fnval': '976',
  'fnver': '0',
  'force_host': '2',
  'fourk': '1',
  'guidance': '1',
  'https_url_req': '1',
  'mobi_app': 'android_i',
  'network': 'wifi',
  'platform': 'android',
  'player_net': '1',
  'qn': '32',
  'recsys_mode': '0',
  's_locale': 'zh_CN',
  'splash_id': '',
  'statistics': '{"appId":1,"platform":3,"version":"8.43.0","abtest":""}',
  'voice_balance': '0',
};

/// The fixed fingerprints and trace id are PiliPlus's placeholders, the same for everyone.
const _officialFeedHeaders = {
  'fp_local': '1111111111111111111111111111111111111111111111111111111111111111',
  'fp_remote': '1111111111111111111111111111111111111111111111111111111111111111',
  'session_id': '11111111',
  'env': 'prod',
  'app-key': 'android_hd',
  'User-Agent':
      'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd mobi_app/android_hd '
      'build/2001100 channel/master innerVer/2001100 osVer/15 network/2',
  'x-bili-trace-id': '11111111111111111111111111111111:1111111111111111:0:0',
  'x-bili-aurora-eid': '',
  'x-bili-aurora-zone': '',
  'bili-http-engine': 'cronet',
};

/// Only playable video cards: ads (`ad_av`, `ad_web_s`, or any card with `ad_info`), live rooms, 番剧, banners and
/// the rest are dropped, as PiliPlus's `_filterAppRcmd` does.
FeedCard? _officialFeedItem(Object? json) {
  if (json is! Map<String, Object?>) return null;
  final object = JsonObject(json);
  final goto = object.text('card_goto') ?? object.text('goto');
  if (goto != 'av' || json['ad_info'] != null || asInt(json['can_play']) != 1) return null;
  return attempt(() => FeedCard.fromOfficial(json));
}

/// 推荐 from the official app's feed (`/x/v2/feed/index`), personalised by the app token. Only videos come back:
/// ads, live rooms, 番剧 and other cards are dropped.
extension BiliClientFeedOfficial on BiliClient {
  /// [index] counts the pages of one scroll from 0, and 0 is a pull to refresh. Without the app token it throws
  /// [BiliError.noAppToken] and sends nothing: the feed is generic without it.
  Future<List<FeedCard>> officialFeed({required int index}) async {
    const path = '/x/v2/feed/index';
    final envelope = await _getEnvelope(
      path,
      query: _officialSigned({
        ..._officialFeedQuery,
        'idx': '$index',
        'pull': index == 0 ? 'true' : 'false',
      }, account: true),
      signed: false,
      host: BiliClient.appAPI,
      sendCookies: false,
      extraHeaders: _officialHeaders(_officialFeedHeaders),
      decode: (json) => [for (final card in JsonObject.from(json).lenientList('items', _officialFeedItem)) ?card],
    );
    final checked = _officialChecked(envelope, account: true);
    if (checked.code != 0) throw BiliError.api(code: checked.code, message: checked.message ?? '');
    return checked.data ?? const [];
  }

  /// 不感兴趣 on a 推荐 card: one of [reasonId] (我不想看) or [feedbackId] (反馈).
  Future<void> feedDislike({required String goto, required int id, int? reasonId, int? feedbackId}) {
    if ((reasonId == null) == (feedbackId == null)) {
      throw ArgumentError('feedDislike needs exactly one of reasonId and feedbackId');
    }
    return _feedDislikeCall('/x/feed/dislike', goto: goto, id: id, reasonId: reasonId, feedbackId: feedbackId);
  }

  /// Takes a [feedDislike] back; the reason it was sent with may be named.
  Future<void> feedDislikeCancel({required String goto, required int id, int? reasonId, int? feedbackId}) =>
      _feedDislikeCall('/x/feed/dislike/cancel', goto: goto, id: id, reasonId: reasonId, feedbackId: feedbackId);

  /// A GET, as PiliPlus sends it; success carries no data.
  Future<void> _feedDislikeCall(
    String path, {
    required String goto,
    required int id,
    required int? reasonId,
    required int? feedbackId,
  }) async {
    final envelope = await _getEnvelope(
      path,
      query: _officialSigned({
        'goto': goto,
        'id': '$id',
        'reason_id': ?reasonId?.toString(),
        'feedback_id': ?feedbackId?.toString(),
        'build': '1',
        'mobi_app': 'android',
      }, account: true),
      signed: false,
      host: BiliClient.appAPI,
      sendCookies: false,
      extraHeaders: _officialHeaders(const {}),
      decode: (_) => null,
    );
    final checked = _officialChecked(envelope, account: true);
    if (checked.code != 0) throw BiliError.api(code: checked.code, message: checked.message ?? '');
  }
}
