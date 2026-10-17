import 'dart:convert';
import 'dart:math';

import 'text.dart';

final class HTTPRequestHead {
  const HTTPRequestHead({required this.method, required this.target, required this.path, required this.headers});

  final String method;
  final String target;
  final String path;

  /// Lowercased names.
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) =>
      other is HTTPRequestHead &&
      other.method == method &&
      other.target == target &&
      other.path == path &&
      other.headers.length == headers.length &&
      headers.entries.every((entry) => other.headers[entry.key] == entry.value);

  @override
  int get hashCode => Object.hash(
        method,
        target,
        path,
        Object.hashAllUnordered(headers.entries.map((entry) => Object.hash(entry.key, entry.value))),
      );

  @override
  String toString() => 'HTTPRequestHead($method $target)';
}

sealed class HTTPParseResult {
  const HTTPParseResult();
}

final class HTTPParseIncomplete extends HTTPParseResult {
  const HTTPParseIncomplete();

  @override
  bool operator ==(Object other) => other is HTTPParseIncomplete;

  @override
  int get hashCode => (HTTPParseIncomplete).hashCode;

  @override
  String toString() => 'HTTPParseResult.incomplete';
}

final class HTTPParseInvalid extends HTTPParseResult {
  const HTTPParseInvalid();

  @override
  bool operator ==(Object other) => other is HTTPParseInvalid;

  @override
  int get hashCode => (HTTPParseInvalid).hashCode;

  @override
  String toString() => 'HTTPParseResult.invalid';
}

final class HTTPParseComplete extends HTTPParseResult {
  const HTTPParseComplete(this.head, {required this.headerLength});

  final HTTPRequestHead head;
  final int headerLength;

  @override
  bool operator ==(Object other) =>
      other is HTTPParseComplete && other.head == head && other.headerLength == headerLength;

  @override
  int get hashCode => Object.hash(head, headerLength);

  @override
  String toString() => 'HTTPParseResult.complete($head, headerLength: $headerLength)';
}

abstract final class HTTPRequestParser {
  static const maxHeaderBytes = 16 * 1024;

  static HTTPParseResult parse(List<int> bytes) {
    final end = _headerEnd(bytes);
    if (end == null) return bytes.length >= maxHeaderBytes ? const HTTPParseInvalid() : const HTTPParseIncomplete();
    final lines = utf8.decode(bytes.sublist(0, end), allowMalformed: true).split('\r\n');
    // Dart splits an empty string into no lines at all, Swift into one empty line.
    final requestLine = (lines.isEmpty ? '' : lines.first).split(' ').where((part) => part.isNotEmpty).toList();
    if (requestLine.length != 3 || !requestLine[2].startsWith('HTTP/1.')) return const HTTPParseInvalid();
    final target = requestLine[1];
    final query = target.indexOf('?');
    final path = query < 0 ? target : target.substring(0, query);
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      if (line.isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon < 0) return const HTTPParseInvalid();
      headers[trimSpaces(line.substring(0, colon)).toLowerCase()] = trimSpaces(line.substring(colon + 1));
    }
    return HTTPParseComplete(
      HTTPRequestHead(method: requestLine[0].toUpperCase(), target: target, path: path, headers: headers),
      headerLength: end + 4,
    );
  }

  static int? _headerEnd(List<int> bytes) {
    final limit = min(bytes.length, maxHeaderBytes);
    for (var index = 0; index + 4 <= limit; index++) {
      if (bytes[index] == 13 && bytes[index + 1] == 10 && bytes[index + 2] == 13 && bytes[index + 3] == 10) {
        return index;
      }
    }
    return null;
  }
}
