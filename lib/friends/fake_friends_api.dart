import 'dart:async';

import 'package:bili_core/api.dart';

import 'friends_api.dart';

/// Made-up answers for tests and `--fake-account` on the PC: no call leaves the machine. [following] is the account's
/// followings in 最近关注's order (最近访问 answers them reversed), [fanList] its fans; 关注 changes which of them the
/// lists say are followed; faces in [collectibleFaces] are 数字藏品. [calls] lists what was asked, in order (never a search's text); [failures] makes a call
/// throw, [holds] keeps it waiting.
class FakeFriendsApi implements FriendsApi {
  FakeFriendsApi({
    this.following = const [],
    this.fanList = const [],
    List<RelationTag>? groups,
    Map<int, Set<int>>? memberships,
    this.collectibleFaces = const {},
    this.pageSize = 20,
  }) : groups = groups ?? defaultGroups,
       memberships = memberships ?? {},
       _followed = {for (final user in following) user.mid};

  /// The `--fake-account` demo: a page and a half of followings, some 大会员 and some verified, two with 数字藏品 faces,
  /// two following back; one fan not followed back. Faces are empty so nothing is fetched.
  factory FakeFriendsApi.demo() => FakeFriendsApi(
    following: [
      for (var i = 0; i < 28; i++)
        FollowingUser(
          mid: 800 + i,
          name: '演示好友$i',
          face: '',
          sign: i.isEven ? '演示签名：这一行写得长一些，长到放不下时末尾会变成省略号为止' : '',
          verify: DynamicVerify.values[i % DynamicVerify.values.length],
          vipPink: i % 3 == 0,
        ),
    ],
    fanList: const [
      FollowingUser(mid: 801, name: '演示好友1', face: ''),
      FollowingUser(mid: 803, name: '演示好友3', face: ''),
      FollowingUser(mid: 899, name: '演示粉丝', face: '', sign: '还没被回关'),
    ],
    memberships: {
      800: {RelationTag.special},
    },
    collectibleFaces: const {805, 806},
  );

  static const defaultGroups = [
    RelationTag(id: RelationTag.special, name: '特别关注', count: 1, tip: '第一时间收到该分组下用户更新稿件的通知'),
    RelationTag(id: RelationTag.defaultGroup, name: '默认分组'),
  ];

  final List<FollowingUser> following;
  final List<FollowingUser> fanList;
  final List<RelationTag> groups;
  final Map<int, Set<int>> memberships;
  final Set<int> collectibleFaces;
  final int pageSize;
  final Set<int> _followed;

  final calls = <String>[];
  final failures = <String, Object>{};
  final holds = <String, Completer<void>>{};

  /// 关注 and 取消关注 sent, in order.
  final follows = <({int mid, bool on})>[];

  /// 分组 saved, in order.
  final saved = <({int mid, Set<int> tags})>[];

  bool isFollowed(int mid) => _followed.contains(mid);

  Future<T> _answer<T>(String name, String call, T Function() answer) async {
    calls.add(call);
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return answer();
  }

  RelationPage _page(List<RelationUser> all, int page) {
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, all.length);
    return RelationPage(
      users: start >= all.length ? const [] : all.sublist(start, end),
      total: all.length,
      hasMore: end < all.length,
    );
  }

  bool _isFan(int mid) => fanList.any((fan) => fan.mid == mid);

  RelationUser _followedUser(FollowingUser user) => RelationUser(
    user: user,
    attribute: _isFan(user.mid) ? RelationUser.mutualValue : RelationUser.followed,
    special: memberships[user.mid]?.contains(RelationTag.special) ?? false,
    collectibleFace: collectibleFaces.contains(user.mid),
  );

  List<RelationUser> get _followedUsers => [
    for (final user in following)
      if (_followed.contains(user.mid)) _followedUser(user),
  ];

  @override
  Future<RelationPage> followings(int mid, {required FollowingOrder order, required int page}) =>
      _answer('followings', 'followings ${order.name} page=$page', () {
        final users = _followedUsers;
        return _page(order == FollowingOrder.mostVisited ? users.reversed.toList() : users, page);
      });

  @override
  Future<RelationPage> searchFollowings(int mid, String name, {required int page}) => _answer(
    'searchFollowings',
    'searchFollowings page=$page',
    () => _page([for (final user in _followedUsers) if (user.user.name.contains(name)) user], page),
  );

  @override
  Future<RelationPage> fans(int mid, {required int page}) => _answer(
    'fans',
    'fans page=$page',
    () => _page([
      for (final fan in fanList)
        RelationUser(
          user: fan,
          attribute: _followed.contains(fan.mid) ? RelationUser.mutualValue : RelationUser.none,
          collectibleFace: collectibleFaces.contains(fan.mid),
        ),
    ], page),
  );

  @override
  Future<void> follow(int mid, {required bool on}) => _answer('follow', 'follow $mid $on', () {
    follows.add((mid: mid, on: on));
    if (on) {
      _followed.add(mid);
    } else {
      _followed.remove(mid);
      memberships.remove(mid);
    }
  });

  @override
  Future<List<RelationTag>> tags() => _answer('tags', 'tags', () => groups);

  @override
  Future<Set<int>> tagsOf(int mid) => _answer('tagsOf', 'tagsOf $mid', () => {...?memberships[mid]});

  @override
  Future<void> setTags(int mid, Set<int> tags) => _answer('setTags', 'setTags $mid ${(tags.toList()..sort()).join(',')}', () {
    saved.add((mid: mid, tags: {...tags}));
    memberships[mid] = {...tags};
  });
}
