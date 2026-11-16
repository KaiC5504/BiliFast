import 'dart:async';

import 'package:bili_core/api.dart';

/// 热门's one call: page [page] of the website's popular list, from 1.
abstract interface class HotApi {
  Future<PopularPage> page(int page);
}

class ClientHotApi implements HotApi {
  ClientHotApi(this._client);

  final BiliClient _client;

  @override
  Future<PopularPage> page(int page) => _client.popular(page: page);
}

/// Made-up answers for tests and `--fake-account` on the PC: no call leaves the machine. [videos] are served
/// [pageSize] to a page; [calls] lists what was asked, in order; [failures] makes a call throw and [holds] keeps it
/// waiting, keyed by the call (`page=2`) or by every page (`page`).
class FakeHotApi implements HotApi {
  FakeHotApi({this.videos = const [], this.pageSize = 20});

  /// The `--fake-account` demo: two pages of 演示 videos, short and long titles, plays from thousands to millions,
  /// published from minutes to weeks before [now]. Covers are empty so nothing is fetched.
  factory FakeHotApi.demo({DateTime? now}) => FakeHotApi(videos: demoVideos(now ?? DateTime.now()));

  static const _plays = [1831000, 238000, 1519000, 1611000, 1161000, 1380000, 62000, 9876, 405000, 27300000];
  static const _lengths = [358, 4908, 70, 411, 475, 394, 174, 33, 1265, 3601];
  static const _ages = [
    Duration(hours: 22, minutes: 39),
    Duration(hours: 15, minutes: 12),
    Duration(hours: 19, minutes: 59),
    Duration(days: 2, hours: 3),
    Duration(hours: 23, minutes: 2),
    Duration(hours: 21, minutes: 15),
    Duration(hours: 2, minutes: 10),
    Duration(minutes: 35),
    Duration(days: 3, hours: 6),
    Duration(days: 12),
  ];

  static List<PopularVideo> demoVideos(DateTime now) => [
    for (var i = 0; i < 40; i++)
      PopularVideo(
        card: VideoCard(
          aid: 9000 + i,
          bvid: 'BV1hotdemo${i.toString().padLeft(2, '0')}',
          cid: 19000 + i,
          title: i % 3 == 1 ? '演示热门视频$i：这一行标题写得长一些，长到第二行也放不下时末尾会变成省略号为止' : '演示热门视频$i',
          cover: '',
          duration: _lengths[i % _lengths.length],
          ownerMid: 900 + i,
          ownerName: '演示UP主$i',
          views: _plays[i % _plays.length] + i,
          danmaku: 1200 + i,
          likes: 30000 + i,
        ),
        published: now.subtract(_ages[i % _ages.length]),
      ),
  ];

  final List<PopularVideo> videos;
  final int pageSize;

  final calls = <String>[];
  final failures = <String, Object>{};
  final holds = <String, Completer<void>>{};

  @override
  Future<PopularPage> page(int page) async {
    final call = 'page=$page';
    calls.add(call);
    if (holds[call] ?? holds['page'] case final hold?) await hold.future;
    if (failures[call] ?? failures['page'] case final failure?) throw failure;
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, videos.length);
    return PopularPage(
      videos: start >= videos.length ? const [] : videos.sublist(start, end),
      page: page,
      hasMore: end < videos.length,
    );
  }
}
