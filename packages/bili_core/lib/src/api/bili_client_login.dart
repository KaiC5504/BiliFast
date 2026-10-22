part of 'bili_client.dart';

const _webLoginCookies = {'DedeUserID', 'DedeUserID__ckMd5', 'SESSDATA', 'bili_jct', 'sid'};

/// The website's QR login and its logout, for the Windows build (`login_models.dart`).
extension BiliClientLogin on BiliClient {
  /// `GET /x/passport-login/web/qrcode/generate` on [BiliClient.passport].
  Future<WebLoginQr> webLoginQr() => get(
    '/x/passport-login/web/qrcode/generate',
    signed: false,
    host: BiliClient.passport,
    decode: (json) {
      final object = JsonObject.from(json);
      return WebLoginQr(url: _filled(object, 'url'), key: _filled(object, 'qrcode_key'));
    },
  );

  /// `GET /x/passport-login/web/qrcode/poll?qrcode_key=` on [BiliClient.passport]. The answer's own code is 0 for
  /// every state; the state is `data.code`. The session comes in the success's `Set-Cookie` headers (on 2026-10-22
  /// its `url` held none), with the `url`'s query as a second source.
  Future<WebLoginPoll> webLoginPoll(String key) async {
    const path = '/x/passport-login/web/qrcode/poll';
    final sent = await _send(
      method: 'GET',
      path: path,
      query: {'qrcode_key': key},
      signed: false,
      host: BiliClient.passport,
      accept: 'application/json',
    );
    final state = _checked(
      _decodeEnvelope(sent, path, (json) {
        final object = JsonObject.from(json);
        return (
          code: object.required(object.integer('code'), 'code'),
          message: object.string('message') ?? '',
          url: object.string('url') ?? '',
        );
      }),
    );
    return switch (state.code) {
      86101 => const WebLoginWaiting(scanned: false),
      86090 => const WebLoginWaiting(scanned: true),
      86038 => const WebLoginExpired(),
      0 => WebLoginDone(_sessionCookies(sent.response.headers['set-cookie'] ?? '', state.url)),
      _ => throw BiliError.api(code: state.code, message: state.message),
    };
  }

  /// `POST /login/exit/v2` on [BiliClient.passport]: ends this session on Bilibili's side, so the cookies stop
  /// working even where a copy survives. Throws when Bilibili refuses.
  Future<void> webLogout() =>
      postVoid('/login/exit/v2', form: {'biliCSRF': ?csrf}, host: BiliClient.passport, referer: BiliClient.referer);

  static String _filled(JsonObject object, String key) {
    final value = object.required(object.string(key), key);
    if (value.isEmpty) throw DecodeError('$key: empty');
    return value;
  }

  /// The session from the success's `Set-Cookie` headers, then its crossDomain link's query for any it lacks. Read by
  /// hand rather than with [Uri.parse] or a cookie parser, whose errors quote what they read. A miss names what the
  /// answer held, never a value.
  static Map<String, String> _sessionCookies(String setCookie, String url) {
    final cookies = <String, String>{};
    final headerNames = <String>[];
    // package:http joins the headers with commas, and Expires dates hold commas too: a cookie starts only where a
    // name and `=` follow the comma.
    for (final cookie in setCookie.split(RegExp(r',(?=\s*[A-Za-z0-9_]+=)'))) {
      final pair = cookie.split(';').first.trim();
      final equals = pair.indexOf('=');
      if (equals <= 0) continue;
      final name = pair.substring(0, equals);
      headerNames.add(name);
      if (!_webLoginCookies.contains(name)) continue;
      final value = _cookieValue(pair.substring(equals + 1));
      if (value != null && value.isNotEmpty) cookies[name] = value;
    }
    final start = url.indexOf('?');
    var query = start < 0 ? '' : url.substring(start + 1);
    final fragment = query.indexOf('#');
    if (fragment >= 0) query = query.substring(0, fragment);
    final urlNames = <String>[];
    for (final pair in query.split('&')) {
      final equals = pair.indexOf('=');
      if (equals <= 0) continue;
      final name = pair.substring(0, equals);
      urlNames.add(name);
      if (!_webLoginCookies.contains(name) || cookies.containsKey(name)) continue;
      final value = _cookieValue(pair.substring(equals + 1));
      if (value != null && value.isNotEmpty) cookies[name] = value;
    }
    if (!cookies.containsKey('SESSDATA') || !cookies.containsKey('bili_jct')) {
      final inUrl = url.isEmpty ? 'empty' : 'names: ${urlNames.join(',')}';
      throw BiliError.decoding('web login: no session in the answer (headers: ${headerNames.join(',')}; url $inUrl)');
    }
    return cookies;
  }

  /// Percent-decoded, then escaped again as Bilibili's own Set-Cookie writes it (SESSDATA's `,` and `*` as `%2C` and
  /// `%2A`): that is the value a browser, and the iPhone's web view login, sends back, and the jar sends values as
  /// they are. Null when the encoding is broken; the decoder's errors would quote the value.
  static String? _cookieValue(String raw) {
    final String decoded;
    try {
      decoded = Uri.decodeComponent(raw);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
    final escaped = StringBuffer();
    for (final byte in utf8.encode(decoded)) {
      final plain =
          (byte >= 0x30 && byte <= 0x39) ||
          (byte >= 0x41 && byte <= 0x5A) ||
          (byte >= 0x61 && byte <= 0x7A) ||
          byte == 0x2D ||
          byte == 0x2E ||
          byte == 0x5F ||
          byte == 0x7E;
      escaped.write(plain ? String.fromCharCode(byte) : '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
    return escaped.toString();
  }
}
