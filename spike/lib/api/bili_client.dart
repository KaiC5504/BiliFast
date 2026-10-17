import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'wbi.dart';

class BiliException implements Exception {
  BiliException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'BiliException($code, $message)';
}

/// The web API calls BiliNative's `BiliClient` makes, over dart:io.
class BiliClient {
  BiliClient({Map<String, String>? cookies}) : _cookies = {...?cookies};

  static const userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';
  static const referer = 'https://www.bilibili.com/';
  static const mediaHeaders = {'User-Agent': userAgent, 'Referer': referer};

  /// DASH | HDR | 4K | Dolby audio | Dolby Vision | 8K | AV1.
  static const dashFnval = 4048;
  static const _api = 'https://api.bilibili.com';

  final Map<String, String> _cookies;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  (int day, String mixin)? _wbi;

  bool get loggedIn => (_cookies['SESSDATA'] ?? '').isNotEmpty;

  /// A cookie file holds one Cookie header line, kept under the gitignored `local/`.
  static Map<String, String> parseCookieHeader(String header) {
    final out = <String, String>{};
    for (final pair in header.split(';')) {
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      out[pair.substring(0, i).trim()] = pair.substring(i + 1).trim();
    }
    return out;
  }

  Future<void> ensureRiskCookies() async {
    if (_cookies.containsKey('buvid3') && _cookies.containsKey('buvid4')) return;
    final data = await _get('/x/frontend/finger/spi', const {}, signed: false) as Map<String, dynamic>;
    _cookies.putIfAbsent('buvid3', () => '${data['b_3']}');
    _cookies.putIfAbsent('buvid4', () => '${data['b_4']}');
  }

  /// `index` is the 0-based page of the endless scroll.
  Future<List<FeedCard>> recommendFeed(int index) async {
    final p = '$index';
    final data = await _get('/x/web-interface/wbi/index/top/feed/rcmd',
        {'fresh_type': '4', 'ps': '12', 'fresh_idx': p, 'fresh_idx_1h': p, 'brush': p, 'feed_version': 'V8'},
        signed: true) as Map<String, dynamic>?;
    final items = (data?['item'] as List?) ?? const [];
    return [for (final i in items) ?FeedCard.tryParse(i as Map<String, dynamic>)];
  }

  Future<VideoInfo> view(String bvid) async {
    final d = await _get('/x/web-interface/wbi/view', {'bvid': bvid}, signed: true) as Map<String, dynamic>;
    return VideoInfo(
      bvid: bvid,
      cid: (d['cid'] as num).toInt(),
      title: '${d['title']}',
      owner: '${(d['owner'] as Map?)?['name'] ?? ''}',
      durationS: (d['duration'] as num?)?.toInt() ?? 0,
    );
  }

  Future<PlayInfo> playUrl(String bvid, int cid, int quality) async {
    final query = {
      'bvid': bvid,
      'cid': '$cid',
      'qn': '$quality',
      'fnval': '$dashFnval',
      'fnver': '0',
      'fourk': '1',
      // Logged out, the web player is offered a 1080P trial with this flag.
      if (!loggedIn) 'try_look': '1',
    };
    final d = await _get('/x/player/wbi/playurl', query, signed: true) as Map<String, dynamic>;
    return PlayInfo.parse(d);
  }

  Future<String> _mixinKey() async {
    final day = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
    final cached = _wbi;
    if (cached != null && cached.$1 == day) return cached.$2;
    // A logged-out reply (-101) still carries the keys.
    final body = await _send('/x/web-interface/nav', '', retried: false);
    final img = ((body['data'] as Map?)?['wbi_img'] as Map?) ?? const {};
    final mixin = Wbi.mixinKey(Wbi.keyFromUrl('${img['img_url']}'), Wbi.keyFromUrl('${img['sub_url']}'));
    if (mixin.length != 32) throw BiliException(-1, 'WBI keys missing in nav');
    _wbi = (day, mixin);
    return mixin;
  }

  Future<Object?> _get(String path, Map<String, String> query, {required bool signed}) async {
    final qs = signed
        ? Wbi.signedQuery(query, await _mixinKey(), DateTime.now().millisecondsSinceEpoch ~/ 1000)
        : Wbi.encodeQuery(query);
    final body = await _send(path, qs, retried: false);
    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 0) throw BiliException(code, '${body['message']}');
    return body['data'];
  }

  Future<Map<String, dynamic>> _send(String path, String query, {required bool retried}) async {
    final uri = Uri.parse('$_api$path${query.isEmpty ? '' : '?$query'}');
    final req = await _http.getUrl(uri);
    req.headers
      ..set('User-Agent', userAgent)
      ..set('Referer', referer)
      ..set('Accept', 'application/json');
    if (_cookies.isNotEmpty) {
      req.headers.set('Cookie', _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode == 412 && !retried && path != '/x/frontend/finger/spi') {
      // Risk control; fresh fingerprint cookies usually clear it once.
      _cookies
        ..remove('buvid3')
        ..remove('buvid4');
      await ensureRiskCookies();
      return _send(path, query, retried: true);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) throw BiliException(res.statusCode, 'HTTP ${res.statusCode} $path');
    return jsonDecode(text) as Map<String, dynamic>;
  }
}
