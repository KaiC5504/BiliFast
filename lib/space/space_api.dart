import 'package:bili_core/api.dart';

/// UP主空间's calls, the official app's. Following and 稍后再看 go through `PageApi`, as on the video page.
abstract interface class SpaceApi {
  Future<SpaceProfile> profile(int mid);

  /// The account's own space with its extras ([SpaceProfile.own]), asked with the app token.
  Future<SpaceProfile> ownProfile(int mid);

  /// Page [page] (from 1) of the account's own 追番.
  Future<SpaceBangumiPage> bangumi(int mid, {required int page});

  /// [next] is the last page's `SpaceVideoPage.next`, null for the first.
  Future<SpaceVideoPage> videos(int mid, {required SpaceOrder order, String? next});

  /// A 合集 or 系列 chip's videos.
  Future<SpaceVideoPage> chipVideos(int mid, SpaceChip chip, {String? next});
}

class ClientSpaceApi implements SpaceApi {
  ClientSpaceApi(this._client);

  final BiliClient _client;

  @override
  Future<SpaceProfile> profile(int mid) async => _client.space(mid: mid);

  @override
  Future<SpaceProfile> ownProfile(int mid) async => _client.ownSpace(mid: mid);

  @override
  Future<SpaceBangumiPage> bangumi(int mid, {required int page}) async => _client.spaceBangumi(mid: mid, page: page);

  @override
  Future<SpaceVideoPage> videos(int mid, {required SpaceOrder order, String? next}) async =>
      _client.spaceVideos(mid: mid, order: order, next: next);

  @override
  Future<SpaceVideoPage> chipVideos(int mid, SpaceChip chip, {String? next}) async =>
      _client.spaceChipVideos(mid: mid, chip: chip, next: next);
}
