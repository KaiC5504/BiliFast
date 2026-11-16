part of 'bili_client.dart';

const _popularPageSize = 20;

/// 首页's 热门 (204).
extension BiliClientPopular on BiliClient {
  /// `/x/web-interface/popular`, page [page] from 1.
  Future<PopularPage> popular({required int page}) => get(
    '/x/web-interface/popular',
    query: {'pn': '$page', 'ps': '$_popularPageSize'},
    signed: false,
    decode: (json) => PopularDecode.page(json, page: page),
  );
}
