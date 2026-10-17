import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Bilibili's WBI request signing, ported from BiliNative's `WBI.swift`.
class Wbi {
  static const _table = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, //
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
  ];

  static String mixinKey(String imgKey, String subKey) {
    final raw = imgKey + subKey;
    final out = StringBuffer();
    for (final i in _table) {
      if (i < raw.length) out.write(raw[i]);
      if (out.length == 32) break;
    }
    return out.toString();
  }

  /// The key is the file name of the image URL handed out in `nav`, without extension.
  static String keyFromUrl(String url) {
    final file = url.split('/').last;
    return file.split('.').first;
  }

  /// encodeURIComponent semantics: everything except A-Z a-z 0-9 - . _ ~ is percent-encoded.
  static String encodeComponent(String text) {
    const hex = '0123456789ABCDEF';
    final out = StringBuffer();
    for (final b in utf8.encode(text)) {
      final plain = (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
          b == 0x2D || b == 0x2E || b == 0x5F || b == 0x7E;
      if (plain) {
        out.writeCharCode(b);
      } else {
        out
          ..write('%')
          ..write(hex[b >> 4])
          ..write(hex[b & 0x0f]);
      }
    }
    return out.toString();
  }

  static String encodeQuery(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    return keys.map((k) => '${encodeComponent(k)}=${encodeComponent(params[k]!)}').join('&');
  }

  static String signedQuery(Map<String, String> params, String mixinKey, int wts) {
    final cleaned = params.map((k, v) => MapEntry(k, v.replaceAll(RegExp(r"[!'()*]"), '')));
    cleaned['wts'] = '$wts';
    final query = encodeQuery(cleaned);
    final rid = md5.convert(utf8.encode(query + mixinKey)).toString();
    return '$query&w_rid=$rid';
  }
}
