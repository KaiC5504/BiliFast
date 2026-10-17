import 'dart:convert';
import 'dart:typed_data';

abstract final class HTTPResponseWriter {
  static Uint8List head({required int status, required List<(String, String)> headers}) {
    final text = StringBuffer('HTTP/1.1 $status ${reason(status)}\r\n');
    for (final (name, value) in headers) {
      text.write('$name: $value\r\n');
    }
    text.write('\r\n');
    return utf8.encode(text.toString());
  }

  static String reason(int status) => switch (status) {
        200 => 'OK',
        206 => 'Partial Content',
        400 => 'Bad Request',
        404 => 'Not Found',
        405 => 'Method Not Allowed',
        416 => 'Range Not Satisfiable',
        500 => 'Internal Server Error',
        503 => 'Service Unavailable',
        _ => 'Status',
      };
}
