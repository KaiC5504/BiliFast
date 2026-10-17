import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

abstract final class MD5 {
  static String hex(String text) => crypto.md5.convert(utf8.encode(text)).toString();
}
