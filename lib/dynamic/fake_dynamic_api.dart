import 'dart:async';

import 'package:bili_core/api.dart';

import 'dynamic_api.dart';

/// Made-up answers for tests and `--fake-account` on the PC: no 动态 call leaves the machine. Posts come [pageSize] to a
/// page from [posts] (any feed) or [videoPosts] (视频), with offsets `p1`, `p2`…; a person's posts are those by that
/// mid, or their [spacePages]. [calls] lists what was asked, in order; [failures] makes a call throw, [holds] keeps it
/// waiting.
class FakeDynamicApi implements DynamicApi {
  FakeDynamicApi({
    this.posts = const [],
    List<DynamicItem>? videoPosts,
    this.upList = const [],
    this.following = const [],
    this.bangumiList = const [],
    this.spacePages = const {},
    this.pageSize = 10,
  }) : videoPosts = videoPosts ?? [for (final post in posts) if (post.major is DynamicVideo) post];

  /// The `--fake-account` demo: one post of every kind the screenshots show, pictures and faces empty so nothing is
  /// fetched. Its videos are the public one the other demos open, so an inline play never asks the guard for a made-up
  /// BV (whose 412 halts every call after it).
  factory FakeDynamicApi.demo() => FakeDynamicApi(
    posts: demoPosts,
    upList: _demoUps,
    following: [
      for (final up in _demoUps) FollowingUser(mid: up.mid, name: up.name, face: '', vipPink: up.mid.isOdd),
      for (var i = 0; i < 25; i++) FollowingUser(mid: 900 + i, name: '演示关注$i', face: ''),
    ],
    bangumiList: [
      for (var i = 0; i < 6; i++) FollowedBangumi(seasonId: 70 + i, title: '演示番剧 第${i + 1}季', cover: '', progress: '全${12 + i}话'),
    ],
  );

  final List<DynamicItem> posts;
  final List<DynamicItem> videoPosts;
  final List<DynamicUp> upList;
  final List<FollowingUser> following;
  final List<FollowedBangumi> bangumiList;

  /// A person's 动态 answered exactly as given, the first for no offset and `pN`'s the one at N, and past them an
  /// empty last page: for answers [posts] can't make, as a page with nothing new that says there is more.
  final Map<int, List<DynamicPage>> spacePages;
  final int pageSize;

  final calls = <String>[];
  final failures = <String, Object>{};
  final holds = <String, Completer<void>>{};

  /// Ids liked or unliked, in order, with the state asked.
  final likes = <({String id, bool on})>[];
  final unfollowed = <int>[];

  Future<T> _answer<T>(String name, String call, T Function() answer) async {
    calls.add(call);
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return answer();
  }

  static int _pageIndex(String? offset) => offset == null || offset.isEmpty ? 0 : int.parse(offset.substring(1));

  DynamicPage _page(List<DynamicItem> all, String? offset) {
    final start = _pageIndex(offset) * pageSize;
    final end = (start + pageSize).clamp(0, all.length);
    final page = start >= all.length ? const <DynamicItem>[] : all.sublist(start, end);
    final hasMore = end < all.length;
    return DynamicPage(items: page, offset: hasMore ? 'p${end ~/ pageSize}' : '', hasMore: hasMore);
  }

  @override
  Future<DynamicPage> feed(DynamicFeedType type, {String? offset}) => _answer(
    'feed',
    'feed ${type.rawValue} offset=${offset ?? ''}',
    () => _page(type == DynamicFeedType.video ? videoPosts : posts, offset),
  );

  @override
  Future<DynamicUpList> ups({String? offset}) =>
      _answer('ups', 'ups offset=${offset ?? ''}', () => DynamicUpList(ups: offset == null ? upList : const []));

  @override
  Future<DynamicPage> spacePosts(int mid, {String? offset}) => _answer(
    'spacePosts',
    'spacePosts $mid offset=${offset ?? ''}',
    () => switch (spacePages[mid]) {
      final pages? => pages.elementAtOrNull(_pageIndex(offset)) ?? const DynamicPage(items: []),
      null => _page([for (final post in posts) if (post.author.mid == mid) post], offset),
    },
  );

  @override
  Future<DynamicItem> detail(String id) => _answer('detail', 'detail $id', () {
    for (final post in posts) {
      if (post.id == id) return post;
      if (post.original?.id == id) return post.original!;
    }
    throw const BiliError.api(code: 4101131, message: '内容不存在');
  });

  @override
  Future<void> like(String id, {required bool on}) => _answer('like', 'like $id $on', () => likes.add((id: id, on: on)));

  @override
  Future<void> unfollow(int mid) => _answer('unfollow', 'unfollow $mid', () => unfollowed.add(mid));

  @override
  Future<FollowingPage> followings(int mid, {required FollowingOrder order, required int page}) =>
      _answer('followings', 'followings ${order.name} page=$page', () {
        final sorted = order == FollowingOrder.recent ? following.reversed.toList() : following;
        return _users(sorted, page);
      });

  @override
  Future<FollowingPage> searchFollowings(int mid, String name, {required int page}) => _answer(
    'searchFollowings',
    'searchFollowings page=$page',
    () => _users([for (final user in following) if (user.name.contains(name)) user], page),
  );

  FollowingPage _users(List<FollowingUser> all, int page) {
    const size = 20;
    final start = (page - 1) * size;
    final end = (start + size).clamp(0, all.length);
    return FollowingPage(
      users: start >= all.length ? const [] : all.sublist(start, end),
      total: all.length,
      hasMore: end < all.length,
    );
  }

  @override
  Future<FollowedBangumiPage> bangumi(int mid, {required int page}) => _answer(
    'bangumi',
    'bangumi page=$page',
    () => FollowedBangumiPage(items: page == 1 ? bangumiList : const [], total: bangumiList.length),
  );

  static const _demoUps = [
    DynamicUp(mid: 101, name: '演示小雨', face: '', hasUpdate: true),
    DynamicUp(mid: 102, name: '演示阿木', face: '', hasUpdate: true),
    DynamicUp(mid: 103, name: '演示星河列车', face: '', hasUpdate: true),
    DynamicUp(mid: 104, name: '演示山海', face: ''),
  ];

  static const _upA = DynamicAuthor(
    mid: 103,
    name: '演示星河列车',
    face: '',
    pubTime: '4小时前',
    verify: DynamicVerify.organisation,
    vipPink: true,
  );

  static const _upB = DynamicAuthor(
    mid: 101,
    name: '演示小雨',
    face: '',
    pubTime: '3小时前',
    verify: DynamicVerify.personal,
    vipPink: true,
    decoration: DynamicDecoration(cardUrl: '', number: '000011'),
  );

  static const _video = DynamicVideo(
    aid: 1001,
    bvid: 'BV1GJ411x7h7',
    title: '演示动态视频的标题',
    cover: '',
    durationText: '00:56',
    duration: 56,
    plays: '37.1万',
    danmaku: '1233',
    badge: '动态视频',
  );

  /// One of each kind 127-140 show, in the feed's order.
  static final demoPosts = <DynamicItem>[
    const DynamicItem(
      id: '9001',
      kind: DynamicKind.draw,
      typeName: 'DYNAMIC_TYPE_DRAW',
      author: _upB,
      nodes: [
        DynamicTextNode('演示动态的第一行，写得稍微长一点\n第二行随便说说今天发生的一件小事\n第三行还在继续往下写！！\n第四行也没有停下来！！，每天都写一点！写满的！！ 再多写一行让它折起来'),
      ],
      foldedLines: true,
      major: DynamicPictures(
        pictures: [
          DynamicPicture(url: '', width: 1080, height: 1350),
          DynamicPicture(url: '', width: 1080, height: 1350),
          DynamicPicture(url: '', width: 1080, height: 1350),
          DynamicPicture(url: '', width: 1080, height: 1350),
        ],
      ),
      goods: DynamicGoods(
        headText: 'UP主的推荐',
        items: [DynamicGoodsItem(name: '演示商品', cover: '', brief: '最高26888元', jumpText: '去看看')],
      ),
      stat: DynamicStat(forward: 9, comment: 100, like: 388),
      comments: CommentArea(oid: 9001, type: 11),
    ),
    const DynamicItem(
      id: '9002',
      kind: DynamicKind.video,
      typeName: 'DYNAMIC_TYPE_AV',
      author: DynamicAuthor(
        mid: 103,
        name: '演示星河列车',
        face: '',
        pubTime: '4小时前',
        pubAction: '发布了动态视频',
        verify: DynamicVerify.organisation,
        vipPink: true,
      ),
      nodes: [
        DynamicTopicNode('#演示话题#'),
        DynamicTextNode(' '),
        DynamicTopicNode('#另一个话题#'),
        DynamicTextNode('\n\n「这是一句演示用的引语，只为看看它怎么换行！」'),
      ],
      major: _video,
      stat: DynamicStat(forward: 24000, comment: 858, like: 11000),
      comments: CommentArea(oid: 1001, type: 1),
    ),
    const DynamicItem(
      id: '9003',
      kind: DynamicKind.forward,
      typeName: 'DYNAMIC_TYPE_FORWARD',
      author: DynamicAuthor(mid: 102, name: '演示阿木', face: '', pubTime: '2025年5月20日'),
      nodes: [DynamicTextNode('周末出门，出发')],
      original: DynamicItem(
        id: '9013',
        kind: DynamicKind.video,
        typeName: 'DYNAMIC_TYPE_AV',
        author: DynamicAuthor(mid: 105, name: '演示原作者', face: '', following: false),
        major: DynamicVideo(
          aid: 1002,
          bvid: 'BV1GJ411x7h7',
          title: '被转发的视频标题很长很长一直写到被截断为止',
          cover: '',
          durationText: '21:50',
          duration: 1310,
          plays: '5.6万',
          danmaku: '348',
        ),
        comments: CommentArea(oid: 1002, type: 1),
      ),
      stat: DynamicStat(like: 2),
      comments: CommentArea(oid: 9003, type: 17),
    ),
    DynamicItem(
      id: '9004',
      kind: DynamicKind.draw,
      typeName: 'DYNAMIC_TYPE_DRAW',
      author: _upA,
      nodes: const [
        DynamicBadgeNode('互动抽奖', kind: 'lottery'),
        DynamicTextNode(' '),
        DynamicTopicNode('#演示话题#'),
        DynamicTextNode('\n\n「演示活动」年度颁奖典礼 | 趣味数据回顾\n'),
        DynamicVideoLinkNode('「演示」第六话 | 出发', bvid: 'BV1GJ411x7h7'),
        DynamicTextNode('\n'),
        DynamicMentionNode('@演示小雨', mid: 101),
      ],
      major: DynamicPictures(
        pictures: [for (var i = 0; i < 9; i++) const DynamicPicture(url: '', width: 1000, height: 1000)],
      ),
      stat: const DynamicStat(forward: 120, comment: 4515, like: 17000, favourite: 414),
      comments: const CommentArea(oid: 9004, type: 11),
    ),
    const DynamicItem(
      id: '9005',
      kind: DynamicKind.word,
      typeName: 'DYNAMIC_TYPE_WORD',
      author: DynamicAuthor(mid: 104, name: '演示山海', face: '', pubTime: '5小时前', location: '上海'),
      nodes: [
        DynamicTextNode('一条只有字的动态'),
        DynamicEmojiNode('[打call]', url: ''),
      ],
      stat: DynamicStat(),
      comments: CommentArea(oid: 9005, type: 17),
    ),
    const DynamicItem(
      id: '9006',
      kind: DynamicKind.live,
      typeName: 'DYNAMIC_TYPE_LIVE_RCMD',
      author: DynamicAuthor(mid: 102, name: '演示阿木', face: '', pubTime: '6小时前', pubAction: '直播了'),
      major: DynamicOtherMajor(typeName: 'MAJOR_TYPE_LIVE_RCMD', title: '演示直播间'),
      stat: DynamicStat(comment: 3, like: 12),
    ),
  ];
}
