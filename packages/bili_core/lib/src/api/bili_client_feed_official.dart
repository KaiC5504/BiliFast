part of 'bili_client.dart';

/// 推荐 from the official app's feed (`/x/v2/feed/index`), personalised by the app token. Only videos come back:
/// ads, live rooms, 番剧 and other cards are dropped.
extension BiliClientFeedOfficial on BiliClient {
  /// [index] counts the pages of one scroll from 0, and 0 is a pull to refresh.
  Future<List<FeedCard>> officialFeed({required int index}) => throw UnimplementedError('officialFeed');
}
