import 'dart:io';

/// Serves integration_test/fixtures/hls over loopback the way the app's local server does: GET and HEAD,
/// single byte ranges answered with 206, `Connection: close`. Every `/<session>/<file>` serves the fixture except
/// the `gone` session, and every request is recorded with its session, so a test can tell loads apart.
final class FixtureServer {
  FixtureServer._(this._server, this._files) {
    _server.listen(_handle);
  }

  static Future<FixtureServer> start() async {
    final directory = fixtureDirectory();
    final files = {
      for (final name in const ['master.m3u8', 'v.m3u8', 'a.m3u8', 'v.mp4', 'a.mp4'])
        name: File('${directory.path}/$name').readAsBytesSync(),
    };
    return FixtureServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), files);
  }

  final HttpServer _server;
  final Map<String, List<int>> _files;
  final requests =
      <({String session, String method, String name, String? range, String? userAgent, String? referer})>[];

  Uri uri(String name, {String session = 'hls'}) => Uri.parse('http://127.0.0.1:${_server.port}/$session/$name');

  Uri get master => uri('master.m3u8');

  /// A file that is not there, as when the local server lost its socket.
  Uri missing(String name) => uri(name, session: 'gone');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response..persistentConnection = false;
    final segments = request.uri.pathSegments;
    final session = segments.length == 2 ? segments.first : '';
    final name = segments.length == 2 ? segments.last : request.uri.path;
    final body = session == 'gone' ? null : _files[name];
    requests.add((
      session: session,
      method: request.method,
      name: name,
      range: request.headers.value('range'),
      userAgent: request.headers.value('user-agent'),
      referer: request.headers.value('referer'),
    ));
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
    } else if (body == null) {
      response.statusCode = HttpStatus.notFound;
    } else {
      response.headers
        ..contentType = name.endsWith('.m3u8') ? ContentType('application', 'vnd.apple.mpegurl') : ContentType('video', 'mp4')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes');
      var start = 0, end = body.length - 1;
      final range = request.headers.value('range');
      if (range != null) {
        final parsed = parseRange(range, body.length);
        if (parsed == null) {
          response
            ..statusCode = HttpStatus.requestedRangeNotSatisfiable
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */${body.length}');
          await response.close();
          return;
        }
        (start, end) = parsed;
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${body.length}');
      }
      response.contentLength = end - start + 1;
      if (request.method == 'GET') response.add(body.sublist(start, end + 1));
    }
    try {
      await response.close();
    } on SocketException {
      // mpv drops connections it no longer needs, after a seek for one.
    }
  }
}

/// `bytes=a-b`, `bytes=a-` and `bytes=-n`, clamped to the body; null when unsatisfiable or multi-range.
(int, int)? parseRange(String header, int total) {
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (match == null) return null;
  final first = match.group(1)!, last = match.group(2)!;
  if (first.isEmpty) {
    if (last.isEmpty) return null;
    final suffix = int.parse(last);
    if (suffix == 0) return null;
    return (total - suffix < 0 ? 0 : total - suffix, total - 1);
  }
  final start = int.parse(first);
  if (start >= total) return null;
  final end = last.isEmpty ? total - 1 : int.parse(last);
  if (end < start) return null;
  return (start, end >= total ? total - 1 : end);
}

/// The fixtures sit in the repo; the test app runs from the repo root, or from `build/windows/x64/runner/<mode>`.
Directory fixtureDirectory() {
  const relative = 'integration_test/fixtures/hls';
  final candidates = [Directory.current, File(Platform.resolvedExecutable).parent];
  for (final start in candidates) {
    Directory? directory = start;
    while (directory != null) {
      final found = Directory('${directory.path}/$relative');
      if (found.existsSync()) return found;
      final parent = directory.parent;
      directory = parent.path == directory.path ? null : parent;
    }
  }
  throw StateError('no $relative above ${Directory.current.path}');
}
