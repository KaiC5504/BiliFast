import 'package:bili_core/api.dart';

/// 动态's calls: the 关注 tab, a post, 我的关注, the face sheet and a space's 动态 tab.
abstract interface class DynamicApi {
  Future<DynamicPage> feed(DynamicFeedType type, {String? offset});

  Future<DynamicUpList> ups({String? offset});

  Future<DynamicPage> spacePosts(int mid, {String? offset});

  Future<DynamicItem> detail(String id);

  Future<void> like(String id, {required bool on});

  /// 取消关注 from ⋮ (137).
  Future<void> unfollow(int mid);

  Future<FollowingPage> followings(int mid, {required FollowingOrder order, required int page});

  Future<FollowingPage> searchFollowings(int mid, String name, {required int page});

  Future<FollowedBangumiPage> bangumi(int mid, {required int page});
}

class ClientDynamicApi implements DynamicApi {
  ClientDynamicApi(this._client);

  final BiliClient _client;

  @override
  Future<DynamicPage> feed(DynamicFeedType type, {String? offset}) => _client.dynamicFeed(type: type, offset: offset);

  @override
  Future<DynamicUpList> ups({String? offset}) => _client.dynamicUps(offset: offset);

  @override
  Future<DynamicPage> spacePosts(int mid, {String? offset}) => _client.spaceDynamics(mid: mid, offset: offset);

  @override
  Future<DynamicItem> detail(String id) => _client.dynamicDetail(id);

  @override
  Future<void> like(String id, {required bool on}) => _client.likeDynamic(id, on: on);

  @override
  Future<void> unfollow(int mid) => _client.follow(mid: mid, on: false);

  @override
  Future<FollowingPage> followings(int mid, {required FollowingOrder order, required int page}) =>
      _client.followingList(mid: mid, order: order, page: page);

  @override
  Future<FollowingPage> searchFollowings(int mid, String name, {required int page}) =>
      _client.searchFollowings(mid: mid, name: name, page: page);

  @override
  Future<FollowedBangumiPage> bangumi(int mid, {required int page}) => _client.followedBangumi(mid: mid, page: page);
}
