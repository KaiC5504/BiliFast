import 'package:bili_core/api.dart';

/// 我的好友's calls: the account's followings and fans with how it stands with each, 搜索我的关注, 关注 and its 分组.
abstract interface class FriendsApi {
  Future<RelationPage> followings(int mid, {required FollowingOrder order, required int page});

  Future<RelationPage> searchFollowings(int mid, String name, {required int page});

  Future<RelationPage> fans(int mid, {required int page});

  /// 关注 or 取消关注, through the same `/x/relation/modify` as a space's.
  Future<void> follow(int mid, {required bool on});

  Future<List<RelationTag>> tags();

  Future<Set<int>> tagsOf(int mid);

  Future<void> setTags(int mid, Set<int> tags);
}

class ClientFriendsApi implements FriendsApi {
  ClientFriendsApi(this._client);

  final BiliClient _client;

  @override
  Future<RelationPage> followings(int mid, {required FollowingOrder order, required int page}) =>
      _client.relationFollowings(mid: mid, order: order, page: page);

  @override
  Future<RelationPage> searchFollowings(int mid, String name, {required int page}) =>
      _client.searchRelationFollowings(mid: mid, name: name, page: page);

  @override
  Future<RelationPage> fans(int mid, {required int page}) => _client.fans(mid: mid, page: page);

  @override
  Future<void> follow(int mid, {required bool on}) => _client.follow(mid: mid, on: on);

  @override
  Future<List<RelationTag>> tags() => _client.relationTags();

  @override
  Future<Set<int>> tagsOf(int mid) => _client.relationTagsOf(mid: mid);

  @override
  Future<void> setTags(int mid, Set<int> tags) => _client.setRelationTags(mid: mid, tags: tags);
}
