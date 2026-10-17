import 'dart:convert';
import 'dart:typed_data';

import 'wbi.dart';

/// application/x-www-form-urlencoded with percent-escapes for everything outside RFC 3986's unreserved set,
/// so a space is %20 (not +) and a literal + or & in a comment cannot be misread by the server.
abstract final class FormEncoding {
  static Uint8List encode(Map<String, String> fields) => utf8.encode(WBI.encodeQuery(fields));
}
