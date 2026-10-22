part of 'bili_client.dart';

/// 我的's calls beyond [BiliClient.nav].
extension BiliClientMe on BiliClient {
  /// `GET /x/web-interface/nav/stat` with the web login's cookies.
  Future<NavStat> navStat() => throw UnimplementedError();
}
