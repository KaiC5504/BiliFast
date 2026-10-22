import 'package:bili_core/api.dart';

import 'me_api.dart';

/// 我的 for tests and `--fake-account`: a made-up account, no traffic.
class FakeMeApi implements MeApi {
  FakeMeApi({required this.navInfo, required this.counts});

  /// The made-up 测试账号 (mid 1) the PC's `--fake-account` shows. Filled in by the data agent.
  factory FakeMeApi.demo() => FakeMeApi(
    navInfo: const NavInfo(isLogin: true, mid: 1, uname: '测试账号'),
    counts: const NavStat(following: 0, follower: 0, dynamicCount: 0),
  );

  NavInfo navInfo;
  NavStat counts;

  @override
  Future<NavInfo> nav() async => navInfo;

  @override
  Future<NavStat> stat() async => counts;
}
