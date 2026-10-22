import 'package:bili_core/api.dart';

/// 我的's calls, the website's: the account (nav, which also carries 硬币, B币, the level and the vip label) and its
/// three counts.
abstract interface class MeApi {
  Future<NavInfo> nav();

  Future<NavStat> stat();
}

class ClientMeApi implements MeApi {
  ClientMeApi(this._client);

  final BiliClient _client;

  @override
  Future<NavInfo> nav() => _client.nav();

  @override
  Future<NavStat> stat() => _client.navStat();
}
