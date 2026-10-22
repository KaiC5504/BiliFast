import 'dart:async';

import 'package:bili_core/api.dart';

import 'space_api.dart';

/// Made-up answers for tests and `--fake-account` on the PC: no space call leaves the machine. Every mid gets
/// [profileFor]'s profile, and the account's own space [ownProfileFor]'s; [ownMid]'s plain profile is that one without
/// its extras, as the real call answers without the app token. The lists are paged [pageSize] at a time, the most
/// played order sorting by play count, and 追番 [bangumiPageSize] at a time. [calls] lists what was asked, in order;
/// [holds] keeps a call waiting and [failures] makes it throw.
class FakeSpaceApi implements SpaceApi {
  FakeSpaceApi({
    SpaceProfile Function(int mid)? profileFor,
    SpaceProfile Function(int mid)? ownProfileFor,
    this.ownMid,
    this.videoList = const [],
    this.pageSize = 20,
    this.bangumiList = const [],
    this.bangumiPageSize = 15,
  }) : _profileFor = profileFor ?? _plain,
       _ownProfileFor = ownProfileFor ?? _plainOwn;

  /// The demo the PC's `--fake-account` run opens: a verified 大会员 uploader with 合集 chips and 45 videos, its
  /// covers and face empty so nothing is fetched. The fake account's own space (mid 1) is [demoOwn] with 5 追番.
  factory FakeSpaceApi.demo({DateTime? now}) {
    final today = now ?? DateTime.now();
    return FakeSpaceApi(
      ownMid: _fakeAccountMid,
      ownProfileFor: demoOwn,
      bangumiList: _demoBangumi,
      profileFor: (mid) => SpaceProfile(
        mid: mid,
        name: '演示UP主',
        face: '',
        sign: '这是一个演示空间，所有内容都是编的。',
        level: 6,
        seniorMember: true,
        vip: true,
        official: SpaceOfficial.person,
        officialTitle: 'bilibili UP主认证：演示UP主',
        fans: 178000,
        following: 18,
        likes: 2841000,
        videoCount: 45,
        tagLines: const [SpaceTagLine(text: 'IP属地：广东')],
        entries: const [SpaceEntry(kind: SpaceEntryKind.charge, title: '充电', note: '5人充电')],
        chargeable: true,
        tabs: const [
          SpaceTab(kind: SpaceTabKind.home, title: '主页'),
          SpaceTab(kind: SpaceTabKind.dynamic, title: '动态'),
          SpaceTab(kind: SpaceTabKind.contribute, title: '投稿'),
        ],
        chips: const [
          SpaceChip(kind: SpaceChipKind.video, title: '视频'),
          SpaceChip(kind: SpaceChipKind.article, title: '图文'),
          SpaceChip(kind: SpaceChipKind.season, title: '演示合集', seasonId: 1),
        ],
      ),
      videoList: [
        for (var i = 0; i < 45; i++)
          SpaceVideo(
            aid: 1000 + i,
            bvid: 'BV1demo${i.toString().padLeft(5, '0')}',
            title: i.isEven ? '演示视频 第${i + 1}期' : '演示视频 第${i + 1}期：一个长一点的标题，好看看两行之后怎么截断',
            cover: '',
            duration: 60 + i * 37,
            play: (i * 7919) % 100000,
            danmaku: (i * 31) % 500,
            published: today.subtract(Duration(hours: i * 9)),
            publishedText: '${today.subtract(Duration(hours: i * 9)).month}月${today.subtract(Duration(hours: i * 9)).day}日',
            badges: i % 7 == 3 ? const ['合作'] : const [],
          ),
      ],
    );
  }

  static SpaceProfile _plain(int mid) => SpaceProfile(mid: mid, name: 'UP主$mid', face: '');

  static SpaceProfile _plainOwn(int mid) => SpaceProfile(mid: mid, name: 'UP主$mid', face: '', own: const OwnSpace());

  /// `AppEnvironment.useFakeAccount`'s.
  static const _fakeAccountMid = 1;

  /// The fake account's own space: level 5 at 14805/28800, a 装扮 on the banner, every 主页 section filled and hidden
  /// from others, no videos (108's empty 投稿), and the tabs 主页 投稿 收藏 追番.
  static SpaceProfile demoOwn(int mid) {
    SpaceVideo video(int i, String title) => SpaceVideo(
      aid: 2000 + i,
      bvid: 'BV1own${i.toString().padLeft(5, '0')}',
      title: title,
      cover: '',
      duration: 12 + i * 9,
      play: 37000 + i * 248000,
      danmaku: i * 232,
    );
    return SpaceProfile(
      mid: mid,
      name: '测试账号',
      face: '',
      level: 5,
      vip: true,
      following: 13,
      tagLines: const [SpaceTagLine(text: 'IP属地：广东')],
      tabs: const [
        SpaceTab(kind: SpaceTabKind.home, title: '主页'),
        SpaceTab(kind: SpaceTabKind.contribute, title: '投稿'),
        SpaceTab(kind: SpaceTabKind.favourite, title: '收藏'),
        SpaceTab(kind: SpaceTabKind.bangumi, title: '追番'),
      ],
      defaultTab: SpaceTabKind.home,
      own: OwnSpace(
        exp: 14805,
        nextExp: 28800,
        vipBadge: true,
        bannerLabel: const SpaceBannerLabel(title: '演示装扮 金牛座', subtitle: 'NO.000001'),
        favourites: const SpaceSection(
          count: 2,
          hidden: true,
          items: [
            SpaceFolderCard(id: 101, title: '默认收藏夹', cover: '', count: 0, isPrivate: false),
            SpaceFolderCard(id: 102, title: '演示收藏夹', cover: '', count: 45, isPrivate: true),
          ],
        ),
        bangumi: SpaceSection(count: _demoBangumi.length, hidden: true, items: _demoBangumi.take(3).toList()),
        coins: SpaceSection(
          count: 2,
          hidden: true,
          items: [video(0, '演示投币视频'), video(1, '演示投币视频：一个长一点的标题，好看看两行之后怎么截断')],
        ),
        likes: SpaceSection(count: 2, hidden: true, items: [video(2, '演示点赞视频'), video(3, '演示点赞视频 第二个')]),
        garbs: const SpaceSection(
          count: 2,
          hidden: true,
          items: [
            SpaceGarbCard(title: '演示装扮 金牛座', image: '', fansNumber: 'NO.000001'),
            SpaceGarbCard(title: '演示装扮 不问天', image: ''),
          ],
        ),
        garbTotal: 7779,
      ),
    );
  }

  static const _demoBangumi = [
    SpaceBangumiCard(seasonId: 901, title: '演示番剧 第一季', cover: '', progress: '全23话'),
    SpaceBangumiCard(seasonId: 902, title: '演示番剧 第二季', cover: '', progress: '全13话'),
    SpaceBangumiCard(seasonId: 903, title: '演示番剧 剧场版', cover: '', progress: '全4话'),
    SpaceBangumiCard(seasonId: 904, title: '演示番剧', cover: '', progress: '全13话'),
    SpaceBangumiCard(seasonId: 905, title: 'A Made-up Show with a Long Name', cover: '', progress: '全1话'),
  ];

  final SpaceProfile Function(int mid) _profileFor;
  final SpaceProfile Function(int mid) _ownProfileFor;
  final int? ownMid;
  final List<SpaceVideo> videoList;
  final int pageSize;
  final List<SpaceBangumiCard> bangumiList;
  final int bangumiPageSize;

  final calls = <String>[];
  final holds = <String, Completer<void>>{};
  final failures = <String, Object>{};

  Future<T> _answer<T>(String name, String call, T Function() value) async {
    calls.add(call);
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return value();
  }

  @override
  Future<SpaceProfile> profile(int mid) =>
      _answer('profile', 'profile mid=$mid', () => mid == ownMid ? _withoutOwn(_ownProfileFor(mid)) : _profileFor(mid));

  static SpaceProfile _withoutOwn(SpaceProfile profile) => SpaceProfile(
    mid: profile.mid,
    name: profile.name,
    face: profile.face,
    sign: profile.sign,
    level: profile.level,
    seniorMember: profile.seniorMember,
    vip: profile.vip,
    vipLabel: profile.vipLabel,
    official: profile.official,
    officialTitle: profile.officialTitle,
    fans: profile.fans,
    following: profile.following,
    likes: profile.likes,
    videoCount: profile.videoCount,
    banner: profile.banner,
    tagLines: profile.tagLines,
    entries: profile.entries,
    chargeable: profile.chargeable,
    tabs: profile.tabs,
    defaultTab: profile.defaultTab,
    chips: profile.chips,
    orders: profile.orders,
  );

  @override
  Future<SpaceProfile> ownProfile(int mid) => _answer('ownProfile', 'ownProfile mid=$mid', () => _ownProfileFor(mid));

  @override
  Future<SpaceBangumiPage> bangumi(int mid, {required int page}) =>
      _answer('bangumi', 'bangumi mid=$mid page=$page', () {
        final start = ((page - 1) * bangumiPageSize).clamp(0, bangumiList.length);
        final end = (start + bangumiPageSize).clamp(0, bangumiList.length);
        return SpaceBangumiPage(
          items: bangumiList.sublist(start, end),
          hasMore: end < bangumiList.length,
          total: bangumiList.length,
        );
      });

  @override
  Future<SpaceVideoPage> videos(int mid, {required SpaceOrder order, String? next}) =>
      _answer('videos', 'videos mid=$mid order=${order.value} next=$next', () {
        final sorted = [...videoList];
        if (order == SpaceOrder.mostPlayed) sorted.sort((a, b) => b.play.compareTo(a.play));
        return _page(sorted, next);
      });

  @override
  Future<SpaceVideoPage> chipVideos(int mid, SpaceChip chip, {String? next}) =>
      _answer('chipVideos', 'chipVideos mid=$mid chip=${chip.title} next=$next', () => _page(videoList.take(12).toList(), next));

  SpaceVideoPage _page(List<SpaceVideo> list, String? next) {
    final start = next == null ? 0 : int.parse(next);
    final end = (start + pageSize).clamp(0, list.length);
    final more = end < list.length;
    return SpaceVideoPage(items: list.sublist(start, end), hasMore: more, next: more ? '$end' : null, total: list.length);
  }
}
