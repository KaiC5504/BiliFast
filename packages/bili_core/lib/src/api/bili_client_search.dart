part of 'bili_client.dart';

const _searchDefaultPath = '/x/web-interface/wbi/search/default';
const _trendingPath = '/x/v2/search/trending/ranking';
const _discoveryPath = '/x/v2/search/recommend';
const _suggestPath = '/x/web-interface/suggest';
const _searchAllPath = '/x/web-interface/wbi/search/all/v2';
const _searchTypePath = '/x/web-interface/wbi/search/type';
const _hotWordCount = 10;

/// What the website's search page sends with every page of results.
const _searchPageQuery = {'page_size': '20', 'platform': 'pc', 'web_location': '1430654'};

/// 搜索发现 is the app's; with fewer of the Android app's parameters it answers -400.
const _discoveryQuery = {
  'build': '8430300',
  'channel': 'master',
  'version': '8.43.0',
  'c_locale': 'zh_CN',
  'mobi_app': 'android',
  'platform': 'android',
  's_locale': 'zh_CN',
  'from': '2',
};

/// -352, so the user sees the usual 请求过于频繁 message.
const _searchRiskControl = BiliError.api(code: -352, message: '搜索太频繁，请稍后再试');

String _searchReferer(String tab, String keyword) =>
    'https://search.bilibili.com/$tab?keyword=${Uri.encodeComponent(keyword)}';

int? _positive(Object? value) {
  final number = asInt(value);
  return number != null && number > 0 ? number : null;
}

/// A page with no rows at all ends the search, whatever the page count says; rows that fail to decode still count.
SearchPage<T> _searchPage<T>(
  JsonObject data,
  List<Object?> rows,
  int requested,
  T Function(Object? json) decode, {
  JsonObject? pageInfo,
}) {
  final page = _positive(data.map['page']) ?? requested;
  final pages = rows.isEmpty ? page : _positive(data.map['numPages']) ?? _positive(pageInfo?.map['pages']) ?? page;
  return SearchPage(items: lossy(rows, decode), page: page, pages: pages);
}

extension BiliClientSearch on BiliClient {
  /// The grey word in the search field (`/x/web-interface/wbi/search/default`); null when there is none.
  Future<String?> searchDefaultWord() => _getIfPresent<String?>(
    _searchDefaultPath,
    query: const {'web_location': '333.1365'},
    signed: true,
    decode: (json) {
      final object = JsonObject.from(json);
      return _filled(object.text('show_name')) ?? _filled(object.text('name'));
    },
  );

  /// bilibili热搜's ten words (`/x/v2/search/trending/ranking`).
  Future<List<HotWord>> hotWords() async {
    final words = await _getIfPresent(
      _trendingPath,
      query: const {'limit': '$_hotWordCount'},
      signed: false,
      decode: (json) => JsonObject.from(json).lossyList('list', HotWord.fromJson),
    );
    return (words ?? const []).take(_hotWordCount).toList();
  }

  /// 搜索发现's words (the app's `/x/v2/search/recommend`). Like every app-host call it goes without the web session
  /// cookies, which it doesn't need: it answers logged out.
  Future<List<DiscoveryWord>> discoveryWords() async {
    final envelope = await _getEnvelope(
      _discoveryPath,
      query: _discoveryQuery,
      signed: false,
      host: BiliClient.appAPI,
      sendCookies: false,
      decode: (json) => JsonObject.from(json).lossyList('list', DiscoveryWord.fromJson),
    );
    if (envelope.code != 0) throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
    return envelope.data ?? [];
  }

  /// Unlike the other calls, the answer keeps its rows beside `code` (`result.tag`), not under `data`; PiliPlus
  /// reads `data.result`, so both are accepted.
  Future<List<SearchSuggestion>> searchSuggestions(String term) async {
    if (term.trim().isEmpty) return [];
    final query = {'term': term, 'highlight': '0', 'spmid': '333.1365', 'web_location': '333.1365'};
    final sent = await _send(
      method: 'GET',
      path: _suggestPath,
      query: query,
      signed: true,
      host: BiliClient.api,
      accept: 'application/json',
    );
    final int code;
    final String message;
    final JsonObject? result;
    try {
      final body = JsonObject.from(jsonDecode(utf8.decode(sent.response.body)), 'envelope');
      code = body.required(body.integer('code'), 'code');
      message = body.text('message') ?? '';
      result = body.nested('result') ?? body.nested('data')?.nested('result');
    } on Exception catch (error) {
      if (error is! DecodeError && error is! FormatException) rethrow;
      final failure = BiliClient._decodeFailure(error);
      _logger.error(LogCategory.api, '$_suggestPath decode failed', {'error': failure});
      throw BiliError.decoding(failure);
    }
    _logger.info(LogCategory.api, _suggestPath, {'status': sent.response.status, 'code': code, 'ms': sent.ms.round()});
    if (code != 0) throw BiliError.api(code: code, message: message);
    return result?.lenientList('tag', (json) => SearchSuggestion.fromJson(json, term)) ?? [];
  }

  /// 综合 without filters (`/x/web-interface/wbi/search/all/v2`): its video rows only.
  Future<SearchPage<SearchVideo>> searchAll({required String keyword, int page = 1}) => get(
    _searchAllPath,
    query: {'search_type': 'all', 'keyword': keyword, 'page': '$page', ..._searchPageQuery},
    signed: true,
    referer: _searchReferer('all', keyword),
    decode: _unlessCaptcha(_searchAllPath, (data) {
      final groups = data.lenientList('result', (json) => JsonObject.from(json));
      final videos = groups.where((group) => group.text('result_type') == 'video').firstOrNull;
      final rows = videos?.lenientList('data', (json) => json) ?? const [];
      return _searchPage(data, rows, page, SearchVideo.fromJson, pageInfo: data.nested('pageinfo')?.nested('video'));
    }),
  );

  /// 综合 with 筛选 (`/x/web-interface/wbi/search/type`, `search_type=video`).
  Future<SearchPage<SearchVideo>> searchVideos({
    required String keyword,
    int page = 1,
    SearchOrder order = SearchOrder.totalrank,
    SearchDuration duration = SearchDuration.any,
    DateTime? publishedFrom,
    DateTime? publishedTo,
  }) {
    final query = {
      'search_type': 'video',
      'keyword': keyword,
      'page': '$page',
      if (order != SearchOrder.totalrank) 'order': order.name,
      'duration': '${duration.index}',
      if (publishedFrom != null) 'pubtime_begin_s': '${publishedFrom.millisecondsSinceEpoch ~/ 1000}',
      if (publishedTo != null) 'pubtime_end_s': '${publishedTo.millisecondsSinceEpoch ~/ 1000}',
      ..._searchPageQuery,
    };
    return get(
      _searchTypePath,
      query: query,
      signed: true,
      referer: _searchReferer('video', keyword),
      decode: _unlessCaptcha(
        _searchTypePath,
        (data) => _searchPage(data, data.lenientList('result', (json) => json), page, SearchVideo.fromJson),
      ),
    );
  }

  /// 用户 (`/x/web-interface/wbi/search/type`, `search_type=bili_user`).
  Future<SearchPage<SearchUser>> searchUsers({required String keyword, int page = 1}) => get(
    _searchTypePath,
    query: {'search_type': 'bili_user', 'keyword': keyword, 'page': '$page', ..._searchPageQuery},
    signed: true,
    referer: _searchReferer('upuser', keyword),
    decode: _unlessCaptcha(
      _searchTypePath,
      (data) => _searchPage(data, data.lenientList('result', (json) => json), page, SearchUser.fromJson),
    ),
  );

  /// Risk control answers a search with `data.v_voucher`, the ticket for a captcha, in place of results.
  JsonDecode<T> _unlessCaptcha<T>(String path, T Function(JsonObject data) decode) => (json) {
    final data = JsonObject.from(json);
    final voucher = data.map['v_voucher'];
    if (voucher != null && voucher != '') {
      _logger.warn(LogCategory.api, '$path asks for a captcha');
      throw _searchRiskControl;
    }
    return decode(data);
  };
}

String? _filled(String? text) => text == null || text.isEmpty ? null : text;
