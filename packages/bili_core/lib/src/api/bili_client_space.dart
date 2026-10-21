part of 'bili_client.dart';

/// A space from the official app's API, signed as the Android app signs it. It goes without the account's cookies,
/// as the app's own calls do; the relation to the uploader is the web card's (`uploaderCard`).
extension BiliClientSpace on BiliClient {
  Future<SpaceProfile> space({required int mid}) => throw UnimplementedError('slice 12: space');

  /// 投稿's videos by [order]; [next] is the last page's `SpaceVideoPage.next`.
  Future<SpaceVideoPage> spaceVideos({required int mid, required SpaceOrder order, String? next}) =>
      throw UnimplementedError('slice 12: spaceVideos');

  /// A 合集 or 系列 chip's videos.
  Future<SpaceVideoPage> spaceChipVideos({required int mid, required SpaceChip chip, String? next}) =>
      throw UnimplementedError('slice 12: spaceChipVideos');
}
