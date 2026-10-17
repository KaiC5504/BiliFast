import 'dart:convert';

import 'log_event.dart';

abstract final class Redactor {
  static const _secretKeyFragments = [
    'sessdata', 'bili_jct', 'jct', 'csrf', 'cookie', 'authorization', 'access_key', 'token', 'password', 'passwd', 'pwd',
    'dedeuserid__ckmd5',
  ];
  static const _idNames = {'mid', 'dedeuserid'};
  // Too short to match as a fragment ("design", "assign"), so it only counts as a whole name.
  static const _exactSecretKeys = {'sign'};

  // Prefixes are bounded so matching stays linear on long input.
  static const _secretName =
      r'(?:[\w-]{0,40}(?:sessdata|bili_jct|access_key|access_token|refresh_token|token|password|passwd|pwd|dedeuserid__ckmd5)'
      r'|[\w-]{0,40}csrf[\w-]{0,40}|sign)';
  static const _quote = r'''(?:\\?["'])''';
  static const _separator = r'''(?:\\?["'])?\s*[=:]\s*''';
  // Group 1 is the opening quote of a quoted value, so the quote survives the replacement.
  static const _value = r'''(?:(\\?["'])[^"'\\]*|[^;&\s"'\\]+)''';

  static final _urlPattern = RegExp(r'''https?:(?:\\?/){2}[^\s"'<>]+''');
  static const _urlTrailing = ').,;!?]}';
  static final _authorizationPattern =
      RegExp(r'''\b((?:proxy-)?authorization["']?\s*[:=]\s*["']?)[^\r\n"']+''', caseSensitive: false);
  static final _cookieHeaderPattern =
      RegExp(r'''\b((?:set-)?cookie["']?\s*:\s*["']?)([^\r\n"']+)''', caseSensitive: false);
  static final _bearerPattern = RegExp(r'\b(bearer\s+)[\w.~+/=-]{6,}', caseSensitive: false);
  // `name:SESSDATA value:abc` (NSHTTPCookie) and `"name":"SESSDATA","value":"abc"` (cookie JSON).
  static final _nameValuePattern = RegExp(
    '\\b(name$_separator$_quote?$_secretName$_quote?[\\s,;]+$_quote?value$_separator)$_value',
    caseSensitive: false,
  );
  static final _secretPairPattern = RegExp('\\b($_secretName$_separator)$_value', caseSensitive: false);
  static const _cookieFlags = {'httponly', 'secure', 'partitioned'};

  /// Values may be String, int, double, bool or [LogValue], as in [LogValue.of].
  static Map<String, LogValue> fields(Map<String, Object> fields) {
    final result = <String, LogValue>{};
    for (final MapEntry(:key, value: raw) in fields.entries) {
      final value = LogValue.of(raw);
      final lowered = key.toLowerCase();
      if (_exactSecretKeys.contains(lowered) || _secretKeyFragments.any(lowered.contains)) {
        result[key] = const LogString('[redacted]');
      } else if (_idNames.contains(lowered)) {
        result[key] = LogString(_hashedID(value));
      } else if (value case LogString(value: final text)) {
        result[key] = LogString(Redactor.text(text));
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  /// Shortens signed URLs and blanks cookie-style secrets in free text.
  static String text(String input) {
    var output = input.replaceAllMapped(_urlPattern, (match) {
      var core = match[0]!;
      var cut = core.length;
      while (cut > 0 && _urlTrailing.contains(core[cut - 1])) {
        cut--;
      }
      final tail = core.substring(cut);
      core = core.substring(0, cut);
      return url(core) + tail;
    });
    output = output.replaceAllMapped(_authorizationPattern, (m) => '${m[1]}[redacted]');
    output = output.replaceAllMapped(_bearerPattern, (m) => '${m[1]}[redacted]');
    output = output.replaceAllMapped(_cookieHeaderPattern, (m) => '${m[1]}${_redactCookieValues(m[2]!)}');
    output = output.replaceAllMapped(_nameValuePattern, (m) => '${m[1]}${m[2] ?? ''}[redacted]');
    return output.replaceAllMapped(_secretPairPattern, (m) => '${m[1]}${m[2] ?? ''}[redacted]');
  }

  static final _urlParts = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*)://([^/?#]*)([^?#]*)(?:\?([^#]*))?(?:#.*)?$');
  static final _rfc3986 = RegExp(r"^(?:[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=]|%[0-9A-Fa-f]{2})*$");

  /// Keeps scheme, host, port, path and the `deadline` parameter: enough to see which node and
  /// when the signature expires, without the signature or the account id.
  static String url(String text) {
    final unescaped = text.replaceAll(r'\/', '/').replaceAll(r'\u0026', '&');
    final parts = _rfc3986.hasMatch(unescaped) ? _urlParts.firstMatch(unescaped) : null;
    final authority = parts == null ? null : _authority(parts[2]!);
    if (parts == null || authority == null) {
      // Not a URL Foundation's URLComponents would parse; never pass the query through.
      final end = unescaped.indexOf(RegExp('[?#]'));
      return end < 0 ? unescaped : unescaped.substring(0, end);
    }
    final (host, port) = authority;
    final buffer = StringBuffer('${parts[1]}://$host');
    if (port != null) buffer.write(':$port');
    buffer.write(_decode(parts[3]!));
    final query = parts[4];
    if (query != null) {
      for (final item in query.split('&')) {
        final equals = item.indexOf('=');
        final name = _decode(equals < 0 ? item : item.substring(0, equals));
        if (name != 'deadline') continue;
        // Like URLComponents' `first(where:)`: only the first `deadline` item counts, even without a value.
        if (equals >= 0) buffer.write('?deadline=${_decode(item.substring(equals + 1))}');
        break;
      }
    }
    return buffer.toString();
  }

  /// Host and explicit port of `[userinfo@]host[:port]`, or null when there is no usable host.
  static (String, int?)? _authority(String authority) {
    final hostPort = authority.substring(authority.lastIndexOf('@') + 1);
    String host;
    String? portText;
    if (hostPort.startsWith('[')) {
      final close = hostPort.indexOf(']');
      if (close < 0) return null;
      host = hostPort.substring(0, close + 1);
      final rest = hostPort.substring(close + 1);
      if (rest.isNotEmpty && !rest.startsWith(':')) return null;
      portText = rest.isEmpty ? null : rest.substring(1);
    } else {
      final colon = hostPort.lastIndexOf(':');
      host = colon < 0 ? hostPort : hostPort.substring(0, colon);
      portText = colon < 0 ? null : hostPort.substring(colon + 1);
    }
    if (host.isEmpty) return null;
    if (portText == null || portText.isEmpty) return (_decode(host), null);
    final port = RegExp(r'^\d+$').hasMatch(portText) ? int.tryParse(portText) : null;
    return port == null ? null : (_decode(host), port);
  }

  static String _decode(String text) {
    try {
      return Uri.decodeComponent(text);
    } on ArgumentError {
      return text;
    }
  }

  static String mid(int mid) => _hashed(mid.toString());

  /// FNV-1a 64; Dart ints wrap at 64 bits, so the arithmetic matches Swift's `&*` on UInt64.
  static String _hashed(String text) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(text)) {
      hash ^= byte;
      hash *= 0x00000100000001b3;
    }
    final high = hash >>> 32;
    final low = hash & 0xffffffff;
    final hex = high == 0 ? low.toRadixString(16) : high.toRadixString(16) + low.toRadixString(16).padLeft(8, '0');
    return 'mid:${hex.length > 8 ? hex.substring(0, 8) : hex}';
  }

  static String _hashedID(LogValue value) => switch (value) {
    LogInt(value: final number) => mid(number),
    LogString(value: final text) when text.startsWith('mid:') => text,
    LogString(value: final text) => switch (RegExp(r'^[+-]?\d+$').hasMatch(text) ? int.tryParse(text) : null) {
      final int number => mid(number),
      null => _hashed(text),
    },
    LogDouble(value: final number) => _hashed(number.toString()),
    LogBool(value: final flag) => _hashed(flag.toString()),
  };

  /// Cookie and Set-Cookie headers: names stay visible (presence matters when debugging 412s), values go.
  static String _redactCookieValues(String header) => header.split(';').map((segment) {
    var lead = 0;
    while (lead < segment.length && (segment[lead] == ' ' || segment[lead] == '\t')) {
      lead++;
    }
    final leading = segment.substring(0, lead);
    final body = segment.substring(lead);
    final equals = body.indexOf('=');
    if (equals >= 0) return '$leading${body.substring(0, equals)}=[redacted]';
    final trimmed = body.trim();
    return _cookieFlags.contains(trimmed.toLowerCase()) || trimmed.isEmpty ? segment : '$leading[redacted]';
  }).join(';');
}
