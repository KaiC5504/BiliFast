part of 'bili_client.dart';

const _spacePath = '/x/v2/space';
const _spaceArchivePath = '/x/v2/space/archive/cursor';
const _spaceSeasonPath = '/x/v2/space/season/videos';
const _spaceSeriesPath = '/x/v2/space/series';
const _spacePageSize = '20';

/// What the Android app 8.43.0 sends with every space call.
const _androidQuery = {
  'build': '8430300',
  'version': '8.43.0',
  'c_locale': 'zh_CN',
  'channel': 'master',
  'mobi_app': 'android',
  'platform': 'android',
  's_locale': 'zh_CN',
  'statistics': '{"appId":1,"platform":3,"version":"8.43.0","abtest":""}',
};

const _androidHeaders = {
  'User-Agent':
      'Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com) os/android model/android mobi_app/android build/8430300 '
      'channel/master innerVer/8430300 osVer/15 network/2',
  'bili-http-engine': 'cronet',
};

/// A space from the official app's API, signed as the Android app signs it. It goes without the account's cookies,
/// as the app's own calls do; the relation to the uploader is the web card's (`uploaderCard`).
extension BiliClientSpace on BiliClient {
  Future<SpaceProfile> space({required int mid}) => _androidGet(_spacePath, {'vmid': '$mid'}, SpaceProfile.fromJson);

  /// 投稿's videos by [order]; [next] is the last page's `SpaceVideoPage.next`.
  Future<SpaceVideoPage> spaceVideos({required int mid, required SpaceOrder order, String? next}) => _androidGet(
    _spaceArchivePath,
    {'vmid': '$mid', 'ps': _spacePageSize, 'qn': '80', 'order': order.value, 'sort': 'desc', 'aid': ?next},
    SpaceVideoPage.fromArchive,
  );

  /// A 合集 or 系列 chip's videos.
  Future<SpaceVideoPage> spaceChipVideos({required int mid, required SpaceChip chip, String? next}) async {
    final (path, list) = switch (chip) {
      SpaceChip(kind: SpaceChipKind.season, :final seasonId?) => (_spaceSeasonPath, {'season_id': '$seasonId'}),
      SpaceChip(kind: SpaceChipKind.series, :final seriesId?) => (_spaceSeriesPath, {'series_id': '$seriesId'}),
      _ => throw ArgumentError.value(chip.kind, 'chip', 'only a 合集 or 系列 chip with its id lists here'),
    };
    return _androidGet(path, {
      'vmid': '$mid',
      ...list,
      'ps': _spacePageSize,
      'qn': '32',
      'sort': 'desc',
      'next': ?next,
    }, SpaceVideoPage.fromArchive);
  }

  Future<T> _androidGet<T>(String path, Map<String, String> query, JsonDecode<T> decode) async => _checked(
    await _getEnvelope(
      path,
      query: AppSigner.android.signed({..._androidQuery, ...query}, ts: _unixSeconds),
      signed: false,
      host: BiliClient.appAPI,
      sendCookies: false,
      extraHeaders: _androidHeaders,
      decode: decode,
    ),
  );
}
