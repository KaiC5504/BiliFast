import 'dart:async';

import 'package:bili_core/api.dart';

import 'space_api.dart';

/// Made-up answers for tests and `--fake-account` on the PC: no space call leaves the machine. Every mid gets
/// [profileFor]'s profile; the lists are paged [pageSize] at a time, the most played order sorting by play count.
/// [calls] lists what was asked, in order; [holds] keeps a call waiting and [failures] makes it throw.
class FakeSpaceApi implements SpaceApi {
  FakeSpaceApi({SpaceProfile Function(int mid)? profileFor, this.videoList = const [], this.pageSize = 20})
    : _profileFor = profileFor ?? _plain;

  /// The demo the PC's `--fake-account` run opens: a verified 大会员 uploader with 合集 chips and 45 videos, its
  /// covers and face empty so nothing is fetched.
  factory FakeSpaceApi.demo({DateTime? now}) {
    final today = now ?? DateTime.now();
    return FakeSpaceApi(
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

  final SpaceProfile Function(int mid) _profileFor;
  final List<SpaceVideo> videoList;
  final int pageSize;

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
  Future<SpaceProfile> profile(int mid) => _answer('profile', 'profile mid=$mid', () => _profileFor(mid));

  @override
  Future<SpaceProfile> ownProfile(int mid) =>
      _answer('ownProfile', 'ownProfile mid=$mid', () => throw UnimplementedError('own tabs builder'));

  @override
  Future<SpaceBangumiPage> bangumi(int mid, {required int page}) =>
      _answer('bangumi', 'bangumi mid=$mid page=$page', () => throw UnimplementedError('own tabs builder'));

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
