part of 'bili_client.dart';

const _relationPageSize = 20;

/// 我的好友's calls beyond 我的关注's: the lists with how the account stands with each person, the account's fans and
/// its 分组 (特别关注).
extension BiliClientRelation on BiliClient {
  /// The account's followings, page [page] from 1; [FollowingOrder.recent] is 最近关注, [FollowingOrder.mostVisited]
  /// 最近访问.
  Future<RelationPage> relationFollowings({required int mid, required FollowingOrder order, required int page}) => get(
    '/x/relation/followings',
    query: {
      'vmid': '$mid',
      'pn': '$page',
      'ps': '$_relationPageSize',
      'order': 'desc',
      'order_type': order.rawValue,
    },
    signed: false,
    decode: (json) => RelationDecode.page(json, page: page, pageSize: _relationPageSize),
  );

  /// 搜索我的关注 with each person's relation.
  Future<RelationPage> searchRelationFollowings({required int mid, required String name, required int page}) => get(
    '/x/relation/followings/search',
    query: {
      'vmid': '$mid',
      'name': name,
      'pn': '$page',
      'ps': '$_relationPageSize',
      'order': 'desc',
      'order_type': 'attention',
    },
    signed: true,
    decode: (json) => RelationDecode.page(json, page: page, pageSize: _relationPageSize),
  );

  /// The people following [mid], page [page] from 1.
  Future<RelationPage> fans({required int mid, required int page}) => get(
    '/x/relation/fans',
    query: {'vmid': '$mid', 'pn': '$page', 'ps': '$_relationPageSize', 'order': 'desc'},
    signed: false,
    decode: (json) => RelationDecode.page(json, page: page, pageSize: _relationPageSize),
  );

  /// The account's 分组, 特别关注 and 默认分组 among them.
  Future<List<RelationTag>> relationTags() => get('/x/relation/tags', signed: false, decode: RelationDecode.tags);

  /// The 分组 [mid] is in.
  Future<Set<int>> relationTagsOf({required int mid}) async =>
      await _getIfPresent(
        '/x/relation/tag/user',
        query: {'fid': '$mid'},
        signed: false,
        decode: RelationDecode.tagsOf,
      ) ??
      <int>{};

  /// Puts [mid] in exactly [tags], replacing the 分组 they were in; none puts them back in 默认分组.
  Future<void> setRelationTags({required int mid, required Set<int> tags}) => postVoid(
    '/x/relation/tags/addUsers',
    form: {'fids': '$mid', 'tagids': tags.isEmpty ? '${RelationTag.defaultGroup}' : (tags.toList()..sort()).join(',')},
    referer: 'https://space.bilibili.com/',
  );
}
