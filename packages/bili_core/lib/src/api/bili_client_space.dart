part of 'bili_client.dart';

const _spacePath = '/x/v2/space';
const _spaceArchivePath = '/x/v2/space/archive/cursor';
const _spaceSeasonPath = '/x/v2/space/season/videos';
const _spaceSeriesPath = '/x/v2/space/series';
const _spacePageSize = '20';

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

  Future<T> _androidGet<T>(String path, Map<String, String> query, JsonDecode<T> decode) =>
      _officialGet(path, query, decode, account: false);
}
