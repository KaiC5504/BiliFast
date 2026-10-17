import 'dart:convert';
import 'dart:typed_data';

import '../danmaku/danmaku_filter.dart';
import '../danmaku/danmaku_segment.dart';
import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import 'action_models.dart';
import 'app_signer.dart';
import 'bili_error.dart';
import 'bili_hosts.dart';
import 'comment_models.dart';
import 'cookie_jar.dart';
import 'feed_models.dart';
import 'form_encoding.dart';
import 'http.dart';
import 'json.dart';
import 'link_parser.dart';
import 'models.dart';
import 'video_models.dart';
import 'wbi.dart';

part 'bili_client_actions.dart';
part 'bili_client_app.dart';
part 'bili_client_comments.dart';
part 'bili_client_danmaku.dart';
part 'bili_client_feed.dart';
part 'bili_client_video.dart';

typedef _Sent = ({HTTPResponse response, double ms});

final class BiliClient {
  BiliClient({required this._transport, required this.cookies, DateTime Function()? now, Logger? logger})
    : now = now ?? DateTime.now,
      _logger = logger ?? Logger.shared;

  static const userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';
  static const referer = 'https://www.bilibili.com/';
  static Map<String, String> get mediaHeaders => {'User-Agent': userAgent, 'Referer': referer};

  /// DASH | HDR | 4K | Dolby audio | Dolby Vision | 8K | AV1.
  static const dashFnval = 4048;

  static const api = 'https://api.bilibili.com';
  static const passport = 'https://passport.bilibili.com';
  static const appAPI = 'https://app.bilibili.com';
  static const _origin = 'https://www.bilibili.com';
  static const _spiPath = '/x/frontend/finger/spi';

  final HTTPTransport _transport;
  final CookieJar cookies;
  final DateTime Function() now;
  final Logger _logger;
  ({String day, String mixin})? _wbiCache;

  /// The cookie every write call must echo back as the `csrf` form field.
  String? get csrf {
    final token = cookies.value('bili_jct');
    return token == null || token.isEmpty ? null : token;
  }

  int get _unixSeconds => now().millisecondsSinceEpoch ~/ 1000;

  /// A logged-out reply (-101) still carries the WBI keys, so it is returned, not thrown.
  Future<NavInfo> nav() async {
    final envelope = await _getEnvelope('/x/web-interface/nav', signed: false, decode: NavInfo.fromJson);
    final nav = envelope.data;
    if (nav == null) throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
    final imgKey = WBI.keyFromURL(nav.imgURL);
    final subKey = WBI.keyFromURL(nav.subURL);
    final mixin = WBI.mixinKey(imgKey: imgKey, subKey: subKey);
    final valid = imgKey.isNotEmpty && subKey.isNotEmpty && mixin.length == 32;
    _wbiCache = valid ? (day: _today(), mixin: mixin) : null;
    return nav;
  }

  /// The web API answers 412 to requests without the website's fingerprint cookies.
  Future<void> ensureRiskCookies() async {
    if (cookies.value('buvid3') != null && cookies.value('buvid4') != null) return;
    final envelope = await _getEnvelope(_spiPath, signed: false, decode: SPIInfo.fromJson);
    final spi = _checked(envelope);
    if (cookies.value('buvid3') == null) cookies.set('buvid3', spi.b3);
    if (cookies.value('buvid4') == null) cookies.set('buvid4', spi.b4);
  }

  /// One of [bvid] or [aid].
  Future<VideoView> view({String? bvid, int? aid}) {
    if ((bvid == null) == (aid == null)) throw ArgumentError('view needs exactly one of bvid and aid');
    final query = bvid != null ? {'bvid': bvid} : {'aid': '$aid'};
    return get('/x/web-interface/view', query: query, signed: false, decode: VideoView.fromJson);
  }

  Future<({VideoView view, int? page})> resolve(VideoLink link) async {
    switch (link) {
      case BvidLink(:final id, :final page):
        return (view: await view(bvid: id), page: page);
      case AidLink(:final id, :final page):
        return (view: await view(aid: id), page: page);
      case ShortLink(:final url):
        // The link parser accepts http:// share links; only https is ever requested.
        final Uri secure;
        try {
          secure = url.replace(scheme: 'https');
        } on FormatException {
          throw BiliError.invalidLink;
        }
        final response = await _transport.send(HTTPRequest(url: secure, headers: {'User-Agent': userAgent}));
        _logger.info(LogCategory.api, 'resolve short link', {'host': secure.host, 'status': response.status});
        final next = LinkParser.parse(response.finalURL.toString());
        if (next == null || next.isShort) throw BiliError.invalidLink;
        return resolve(next);
    }
  }

  Future<PlayURLInfo> playURL({required String bvid, required int cid, required int quality}) async {
    final query = {'bvid': bvid, 'cid': '$cid', 'qn': '$quality', 'fnval': '$dashFnval', 'fnver': '0', 'fourk': '1'};
    final info = await get('/x/player/wbi/playurl', query: query, signed: true, decode: PlayURLInfo.fromJson);
    if (info.dash == null) throw BiliError.notDash;
    return info;
  }

  Future<String> _mixinKey() async {
    final cached = _wbiCache;
    if (cached != null && cached.day == _today()) return cached.mixin;
    await nav();
    final fresh = _wbiCache;
    if (fresh == null || fresh.day != _today()) {
      throw const BiliError.decoding('WBI keys missing or malformed in nav');
    }
    return fresh.mixin;
  }

  String _today() => '${_unixSeconds ~/ 86400}';

  T _checked<T>(BiliEnvelope<T> envelope) {
    final data = envelope.data;
    if (envelope.code != 0 || data == null) {
      throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
    }
    return data;
  }

  Future<T> get<T>(
    String path, {
    Map<String, String> query = const {},
    required bool signed,
    String host = api,
    required JsonDecode<T> decode,
  }) async => _checked(await _getEnvelope(path, query: query, signed: signed, host: host, decode: decode));

  /// For reads whose success may carry `data: null`, which is an empty result rather than an error.
  Future<T?> _getIfPresent<T>(
    String path, {
    Map<String, String> query = const {},
    required bool signed,
    required JsonDecode<T> decode,
  }) async {
    final envelope = await _getEnvelope(path, query: query, signed: signed, decode: decode);
    if (envelope.code != 0) throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
    return envelope.data;
  }

  /// For endpoints that do not answer with the JSON envelope, such as the protobuf danmaku segments.
  Future<Uint8List> getData(
    String path, {
    Map<String, String> query = const {},
    required bool signed,
    String host = api,
  }) async {
    final sent = await _send(method: 'GET', path: path, query: query, signed: signed, host: host, accept: '*/*');
    _logger.info(LogCategory.api, path, {'status': sent.response.status, 'ms': sent.ms.round()});
    return sent.response.body;
  }

  Future<T> post<T>(
    String path, {
    Map<String, String> form = const {},
    String? referer,
    String host = api,
    bool cookies = true,
    required JsonDecode<T> decode,
  }) async =>
      _checked(await _postEnvelope(path, form: form, referer: referer, host: host, cookies: cookies, decode: decode));

  /// For writes whose success carries no data (`data` may be null).
  Future<void> postVoid(
    String path, {
    Map<String, String> form = const {},
    String? referer,
    String host = api,
    bool cookies = true,
  }) async {
    final envelope = await _postEnvelope(
      path,
      form: form,
      referer: referer,
      host: host,
      cookies: cookies,
      decode: (_) => null,
    );
    if (envelope.code != 0) throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
  }

  Future<BiliEnvelope<T>> _getEnvelope<T>(
    String path, {
    Map<String, String> query = const {},
    required bool signed,
    String host = api,
    required JsonDecode<T> decode,
  }) async {
    final sent = await _send(
      method: 'GET',
      path: path,
      query: query,
      signed: signed,
      host: host,
      accept: 'application/json',
    );
    return _decodeEnvelope(sent, path, decode);
  }

  Future<BiliEnvelope<T>> _postEnvelope<T>(
    String path, {
    required Map<String, String> form,
    String? referer,
    required String host,
    bool cookies = true,
    required JsonDecode<T> decode,
  }) async {
    final sent = await _send(
      method: 'POST',
      path: path,
      signed: false,
      host: host,
      form: form,
      referer: referer,
      accept: 'application/json',
      sendCookies: cookies,
    );
    return _decodeEnvelope(sent, path, decode);
  }

  BiliEnvelope<T> _decodeEnvelope<T>(_Sent sent, String path, JsonDecode<T> decode) {
    try {
      final envelope = BiliEnvelope.parse(utf8.decode(sent.response.body), decode);
      _logger.info(LogCategory.api, path, {
        'status': sent.response.status,
        'code': envelope.code,
        'ms': sent.ms.round(),
      });
      return envelope;
    } on Exception catch (error) {
      if (error is! DecodeError && error is! FormatException) rethrow;
      _logger.error(LogCategory.api, '$path decode failed', {'error': '$error'});
      throw BiliError.decoding('$error');
    }
  }

  /// Logs the path only: the query and form can carry the csrf token or a comment the user typed.
  /// `sendCookies: false` is for the app API: no session cookies, no csrf field (its calls carry a signature and
  /// an access token instead), and no 412 retry, since fresh fingerprint cookies would not be sent anyway.
  Future<_Sent> _send({
    required String method,
    required String path,
    Map<String, String> query = const {},
    required bool signed,
    required String host,
    Map<String, String>? form,
    String? referer,
    required String accept,
    bool sendCookies = true,
    bool retried = false,
  }) async {
    Uint8List? body;
    final headers = {'User-Agent': userAgent, 'Referer': referer ?? BiliClient.referer, 'Accept': accept};
    if (form != null) {
      final fields = Map.of(form);
      if (sendCookies) {
        final token = csrf;
        if (token == null) throw const BiliError.api(code: -101, message: '账号未登录');
        fields['csrf'] = token;
        headers['Origin'] = _origin;
      }
      body = FormEncoding.encode(fields);
      headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
    }
    final String queryString;
    if (signed) {
      final key = await _mixinKey();
      queryString = WBI.signedQuery(query, mixinKey: key, wts: _unixSeconds);
    } else {
      queryString = WBI.encodeQuery(query);
    }
    final Uri url;
    try {
      url = Uri.parse(host + path + (queryString.isEmpty ? '' : '?$queryString'));
    } on FormatException {
      throw BiliError.invalidLink;
    }
    // The session cookies and the csrf token must never leave Bilibili's own hosts.
    if (BiliHosts.isBilibili(url.host)) {
      final cookie = cookies.headerValue;
      if (sendCookies && cookie != null) headers['Cookie'] = cookie;
    } else if (form != null) {
      throw BiliError.invalidLink;
    }
    final watch = Stopwatch()..start();
    final HTTPResponse response;
    try {
      response = await _transport.send(HTTPRequest(url: url, headers: headers, method: method, body: body));
    } catch (error) {
      _logger.error(LogCategory.api, path, {'error': '$error'});
      rethrow;
    }
    final ms = watch.elapsedMicroseconds / 1000;
    if (response.status < 200 || response.status >= 300) {
      _logger.warn(LogCategory.api, path, {'status': response.status, 'ms': ms.round()});
      // 412 is risk control; fresh fingerprint cookies usually clear it once.
      if (response.status == 412 && !retried && sendCookies && path != _spiPath) {
        cookies.remove('buvid3');
        cookies.remove('buvid4');
        await ensureRiskCookies();
        return _send(
          method: method,
          path: path,
          query: query,
          signed: signed,
          host: host,
          form: form,
          referer: referer,
          accept: accept,
          sendCookies: sendCookies,
          retried: true,
        );
      }
      throw BiliError.http(response.status);
    }
    return (response: response, ms: ms);
  }
}
