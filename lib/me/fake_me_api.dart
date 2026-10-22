import 'dart:async';

import 'package:bili_core/api.dart';

import 'me_api.dart';

/// 我的 for tests and `--fake-account`: a made-up account, no traffic. [calls] lists what was asked, in order; [holds]
/// keeps a call waiting and [failures] makes it throw, both by method name (`nav`, `stat`).
class FakeMeApi implements MeApi {
  FakeMeApi({required this.navInfo, required this.counts});

  /// The made-up 测试账号 (mid 1) the PC's `--fake-account` shows: a 年度大会员 at level 5, with the face 评论's demo
  /// gives it and one of the demo's avatar frames.
  factory FakeMeApi.demo() => FakeMeApi(
    navInfo: const NavInfo(
      isLogin: true,
      mid: 1,
      uname: '测试账号',
      face: 'https://i0.hdslb.com/bfs/face/member/noface.jpg',
      vipStatus: 1,
      vipType: 2,
      level: 5,
      coins: 879,
      bcoin: 2.3,
      vipLabel: '年度大会员',
      vipBadge: true,
      pendant: 'https://i2.hdslb.com/bfs/garb/item/f8bb9af4f245cce0fcba5df248069f1eedd8cbb7.png',
    ),
    counts: const NavStat(following: 13, follower: 0, dynamicCount: 0),
  );

  /// Read when a call answers, so a held call answers with what the test set meanwhile.
  NavInfo navInfo;
  NavStat counts;

  final calls = <String>[];
  final holds = <String, Completer<void>>{};
  final failures = <String, Object>{};

  Future<T> _answer<T>(String name, T Function() value) async {
    calls.add(name);
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return value();
  }

  @override
  Future<NavInfo> nav() => _answer('nav', () => navInfo);

  @override
  Future<NavStat> stat() => _answer('stat', () => counts);
}
