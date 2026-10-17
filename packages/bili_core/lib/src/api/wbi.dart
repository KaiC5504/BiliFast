import 'dart:convert';

import 'md5.dart';

abstract final class WBI {
  static const _table = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, //
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
  ];

  static String mixinKey({required String imgKey, required String subKey}) {
    final raw = (imgKey + subKey).runes.toList();
    final picked = [for (final index in _table) if (index < raw.length) raw[index]];
    return String.fromCharCodes(picked.take(32));
  }

  /// The key is the file name of the image URL Bilibili hands out in `nav`, without extension.
  static String keyFromURL(String url) {
    final file = url.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '';
    return file.split('.').where((part) => part.isNotEmpty).firstOrNull ?? '';
  }

  /// encodeURIComponent semantics: everything except A-Z a-z 0-9 - . _ ~ is percent-encoded.
  static String encodeComponent(String text) {
    const hexDigits = '0123456789ABCDEF';
    final output = StringBuffer();
    for (final byte in utf8.encode(text)) {
      final unreserved = (byte >= 0x30 && byte <= 0x39) ||
          (byte >= 0x41 && byte <= 0x5A) ||
          (byte >= 0x61 && byte <= 0x7A) ||
          byte == 0x2D ||
          byte == 0x2E ||
          byte == 0x5F ||
          byte == 0x7E;
      if (unreserved) {
        output.writeCharCode(byte);
      } else {
        output
          ..write('%')
          ..write(hexDigits[byte >> 4])
          ..write(hexDigits[byte & 0x0f]);
      }
    }
    return output.toString();
  }

  static String encodeQuery(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    return keys.map((key) => '${encodeComponent(key)}=${encodeComponent(params[key]!)}').join('&');
  }

  static final _stripped = RegExp(r"[!'()*]");

  static String signedQuery(Map<String, String> params, {required String mixinKey, required int wts}) {
    final cleaned = params.map((key, value) => MapEntry(key, value.replaceAll(_stripped, '')));
    cleaned['wts'] = '$wts';
    final query = encodeQuery(cleaned);
    return '$query&w_rid=${MD5.hex(query + mixinKey)}';
  }
}
