import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/local_http.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

final content = Uint8List.fromList([for (var i = 0; i < 1000; i++) (i * 7) & 0xFF]);

(PlaybackRouter, String) makeRouter(List<ByteRange> reads) {
  final media = MediaResource(
    totalSize: 1000,
    prefix: content.sublist(0, 100),
    read: (range) {
      reads.add(range);
      return Stream.value(content.sublist(range.start, range.end + 1));
    },
  );
  final router = PlaybackRouter();
  final token = router.register(PlaybackAssets(playlists: {'master.m3u8': '#EXTM3U\n'}, media: {'v.mp4': media}));
  return (router, token);
}

HTTPRequestHead head(String path, {String? range, String method = 'GET'}) =>
    HTTPRequestHead(method: method, target: path, path: path, headers: range == null ? {} : {'range': range});

Future<(int, List<(String, String)>, List<int>)> body(RouteResult result) async => switch (result) {
      RouteText(:final status, :final body) => (status, <(String, String)>[], body),
      RouteFailure(:final status, :final headers) => (status, headers, <int>[]),
      RouteMedia(:final status, :final headers, :final body) => (
          status,
          headers,
          await body.fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk)),
        ),
    };

String? header(List<(String, String)> headers, String name) {
  for (final (key, value) in headers) {
    if (key == name) return value;
  }
  return null;
}

Future<(List<int>, Object?)> drain(RouteResult result) async {
  if (result is! RouteMedia) return (<int>[], null);
  final received = <int>[];
  try {
    await for (final chunk in result.body) {
      received.addAll(chunk);
    }
    return (received, null);
  } catch (error) {
    return (received, error);
  }
}

void main() {
  test('parser states', () {
    expect(HTTPRequestParser.parse(utf8.encode('GET /a HTTP/1.1\r\nHost: x\r\n')), const HTTPParseIncomplete());
    expect(HTTPRequestParser.parse(utf8.encode('NONSENSE\r\n\r\n')), const HTTPParseInvalid());
    final raw = utf8.encode(
      'GET /tok/v.mp4?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=0-99\r\nX-Playback-Session-Id: 1\r\n\r\n',
    );
    final result = HTTPRequestParser.parse(raw);
    if (result is! HTTPParseComplete) fail('expected complete');
    expect(result.headerLength, raw.length);
    expect(result.head.method, 'GET');
    expect(result.head.path, '/tok/v.mp4');
    expect(result.head.target, '/tok/v.mp4?x=1');
    expect(result.head.headers['range'], 'bytes=0-99');
    expect(result.head.headers['x-playback-session-id'], '1');
    expect(HTTPRequestParser.parse(List.filled(20000, 65)), const HTTPParseInvalid());
  });

  test('header cap applies even when the terminator arrives', () {
    final padding = 'a' * HTTPRequestParser.maxHeaderBytes;
    expect(HTTPRequestParser.parse(utf8.encode('GET /a HTTP/1.1\r\nX-Pad: $padding\r\n\r\n')), const HTTPParseInvalid());

    const prefix = 'GET /a HTTP/1.1\r\nX-Pad: ';
    final padFits = HTTPRequestParser.maxHeaderBytes - utf8.encode(prefix).length - 4;
    final fits = utf8.encode('$prefix${'a' * padFits}\r\n\r\n');
    expect(fits.length, HTTPRequestParser.maxHeaderBytes);
    final result = HTTPRequestParser.parse(fits);
    if (result is! HTTPParseComplete) fail('a head of exactly the cap should parse');
    expect(result.headerLength, fits.length);

    final oneOver = utf8.encode('$prefix${'a' * (padFits + 1)}\r\n\r\n');
    expect(HTTPRequestParser.parse(oneOver), const HTTPParseInvalid());
  });

  // Review focus 4: whatever range AVPlayer sends gets the right bytes.
  test('range variants', () {
    expect(RangeRequest.parse(null, totalSize: 1000), const RangeRequest.full());
    expect(RangeRequest.parse('bytes=0-99', totalSize: 1000), RangeRequest.range(ByteRange(0, 99)));
    expect(RangeRequest.parse('bytes=900-', totalSize: 1000), RangeRequest.range(ByteRange(900, 999)));
    expect(RangeRequest.parse('bytes=-100', totalSize: 1000), RangeRequest.range(ByteRange(900, 999)));
    expect(RangeRequest.parse('bytes=0-5000', totalSize: 1000), RangeRequest.range(ByteRange(0, 999)));
    expect(RangeRequest.parse('bytes=1000-', totalSize: 1000), const RangeRequest.unsatisfiable());
    expect(RangeRequest.parse('bytes=0-1,5-6', totalSize: 1000), const RangeRequest.unsatisfiable());
    expect(RangeRequest.parse('bytes=50-10', totalSize: 1000), const RangeRequest.unsatisfiable());
  });

  test('range edge cases', () {
    final whole = RangeRequest.range(ByteRange(0, 999));
    expect(RangeRequest.parse('bytes=0-', totalSize: 1000), whole);
    expect(RangeRequest.parse('bytes=-5000', totalSize: 1000), whole);
    expect(RangeRequest.parse('bytes=-1000', totalSize: 1000), whole);
    expect(RangeRequest.parse('bytes=-1', totalSize: 1000), RangeRequest.range(ByteRange(999, 999)));
    expect(RangeRequest.parse('bytes=999-999', totalSize: 1000), RangeRequest.range(ByteRange(999, 999)));
    expect(RangeRequest.parse('bytes=999-5000', totalSize: 1000), RangeRequest.range(ByteRange(999, 999)));
    expect(RangeRequest.parse('bytes=-0', totalSize: 1000), const RangeRequest.unsatisfiable());
    expect(RangeRequest.parse('bytes=-', totalSize: 1000), const RangeRequest.unsatisfiable());
    expect(RangeRequest.parse('bytes=abc-', totalSize: 1000), const RangeRequest.unsatisfiable());
    expect(RangeRequest.parse('bytes=0-99', totalSize: 0), const RangeRequest.unsatisfiable());
    expect(RangeRequest.parse('  Bytes=10-19 ', totalSize: 1000), RangeRequest.range(ByteRange(10, 19)));
    expect(RangeRequest.parse('', totalSize: 1000), const RangeRequest.full());
  });

  test('response head', () {
    final text = utf8.decode(HTTPResponseWriter.head(status: 206, headers: [('Content-Length', '10')]));
    expect(text, 'HTTP/1.1 206 Partial Content\r\nContent-Length: 10\r\n\r\n');
  });

  test('playlist and unknown paths', () async {
    final (router, token) = makeRouter([]);
    final playlist = await body(router.route(head('/$token/master.m3u8')));
    expect(playlist.$1, 200);
    expect(utf8.decode(playlist.$3), '#EXTM3U\n');
    final wrongToken = await body(router.route(head('/wrongtoken/master.m3u8')));
    expect(wrongToken.$1, 404);
    final missing = await body(router.route(head('/$token/nope.mp4')));
    expect(missing.$1, 404);
    final post = await body(router.route(head('/$token/master.m3u8', method: 'POST')));
    expect(post.$1, 405);
    router.unregister(token);
    final afterUnregister = await body(router.route(head('/$token/master.m3u8')));
    expect(afterUnregister.$1, 404);
  });

  test('ranges inside, across and after the prefix', () async {
    final reads = <ByteRange>[];
    final (router, token) = makeRouter(reads);

    final inside = await body(router.route(head('/$token/v.mp4', range: 'bytes=0-49')));
    expect(inside.$1, 206);
    expect(inside.$3, content.sublist(0, 50));
    expect(inside.$2, contains(('Content-Range', 'bytes 0-49/1000')));
    expect(inside.$2, contains(('Content-Length', '50')));
    expect(reads, isEmpty);

    final across = await body(router.route(head('/$token/v.mp4', range: 'bytes=50-199')));
    expect(across.$3, content.sublist(50, 200));
    expect(reads, [ByteRange(100, 199)]);

    final open = await body(router.route(head('/$token/v.mp4', range: 'bytes=500-')));
    expect(open.$3, content.sublist(500, 1000));
    final full = await body(router.route(head('/$token/v.mp4')));
    expect(full.$1, 200);
    final refused = await body(router.route(head('/$token/v.mp4', range: 'bytes=2000-')));
    expect(refused.$1, 416);
    expect(refused.$2, contains(('Content-Range', 'bytes */1000')));
  });

  test('prefix boundary and clamped ranges', () async {
    final reads = <ByteRange>[];
    final (router, token) = makeRouter(reads);
    final path = '/$token/v.mp4';

    // Ends on the last prefix byte: no read.
    final lastPrefixByte = await body(router.route(head(path, range: 'bytes=99-99')));
    expect(lastPrefixByte.$3, [content[99]]);
    expect(header(lastPrefixByte.$2, 'Content-Range'), 'bytes 99-99/1000');
    expect(reads, isEmpty);

    // Starts on the first byte after the prefix: read only.
    final firstReadByte = await body(router.route(head(path, range: 'bytes=100-100')));
    expect(firstReadByte.$3, [content[100]]);
    expect(reads, [ByteRange(100, 100)]);

    // One byte on each side of the boundary.
    final straddle = await body(router.route(head(path, range: 'bytes=99-100')));
    expect(straddle.$1, 206);
    expect(straddle.$3, content.sublist(99, 101));
    expect(header(straddle.$2, 'Content-Length'), '2');
    expect(reads.last, ByteRange(100, 100));

    // Wide straddle, not aligned to anything.
    final wide = await body(router.route(head(path, range: 'bytes=37-613')));
    expect(wide.$3, content.sublist(37, 614));
    expect(header(wide.$2, 'Content-Range'), 'bytes 37-613/1000');
    expect(header(wide.$2, 'Content-Length'), '577');
    expect(reads.last, ByteRange(100, 613));

    // bytes=0- is a 206 covering the whole resource.
    final openFromZero = await body(router.route(head(path, range: 'bytes=0-')));
    expect(openFromZero.$1, 206);
    expect(openFromZero.$3, content);
    expect(header(openFromZero.$2, 'Content-Range'), 'bytes 0-999/1000');
    expect(header(openFromZero.$2, 'Content-Length'), '1000');

    // End past totalSize is clamped, and the headers describe what is sent.
    final clamped = await body(router.route(head(path, range: 'bytes=950-5000')));
    expect(clamped.$1, 206);
    expect(clamped.$3, content.sublist(950, 1000));
    expect(header(clamped.$2, 'Content-Range'), 'bytes 950-999/1000');
    expect(header(clamped.$2, 'Content-Length'), '50');

    // Suffix forms, including one larger than the resource.
    final suffix = await body(router.route(head(path, range: 'bytes=-30')));
    expect(suffix.$3, content.sublist(970, 1000));
    expect(header(suffix.$2, 'Content-Range'), 'bytes 970-999/1000');
    final hugeSuffix = await body(router.route(head(path, range: 'bytes=-5000')));
    expect(hugeSuffix.$1, 206);
    expect(hugeSuffix.$3, content);
    expect(header(hugeSuffix.$2, 'Content-Range'), 'bytes 0-999/1000');
    final smallSuffix = await body(router.route(head(path, range: 'bytes=-10')));
    expect(smallSuffix.$3, content.sublist(990, 1000));

    // Full body: 200 with no Content-Range, prefix then read.
    final full = await body(router.route(head(path)));
    expect(full.$1, 200);
    expect(full.$3, content);
    expect(header(full.$2, 'Content-Range'), isNull);
    expect(header(full.$2, 'Content-Length'), '1000');

    for (final refusal in ['bytes=1000-', 'bytes=1000-1005', 'bytes=-0', 'bytes=500-100', 'bytes=0-1,5-6']) {
      final refused = await body(router.route(head(path, range: refusal)));
      expect(refused.$1, 416, reason: refusal);
      expect(header(refused.$2, 'Content-Range'), 'bytes */1000', reason: refusal);
    }
  });

  test('a read failure after the prefix surfaces to the caller', () async {
    final boom = StateError('boom');
    final media = MediaResource(
      totalSize: 1000,
      prefix: Uint8List.fromList(List.filled(100, 1)),
      read: (_) => Stream.error(boom),
    );
    final router = PlaybackRouter();
    final token = router.register(PlaybackAssets(playlists: {}, media: {'v.mp4': media}));
    final result = router.route(head('/$token/v.mp4', range: 'bytes=50-199'));
    if (result is! RouteMedia) fail('expected media');
    final received = <int>[];
    try {
      await for (final chunk in result.body) {
        received.addAll(chunk);
      }
      fail('expected the read error');
    } on StateError catch (error) {
      expect(error, same(boom));
    }
    expect(received, List.filled(50, 1));
  });

  test('HEAD serves headers without reading', () async {
    final reads = <ByteRange>[];
    final (router, token) = makeRouter(reads);
    final path = '/$token/v.mp4';

    final full = await body(router.route(head(path, method: 'HEAD')));
    expect(full.$1, 200);
    expect(full.$3, isEmpty);
    expect(header(full.$2, 'Content-Length'), '1000');
    expect(header(full.$2, 'Content-Range'), isNull);

    final ranged = await body(router.route(head(path, range: 'bytes=50-599', method: 'HEAD')));
    expect(ranged.$1, 206);
    expect(ranged.$3, isEmpty);
    expect(header(ranged.$2, 'Content-Length'), '550');
    expect(header(ranged.$2, 'Content-Range'), 'bytes 50-599/1000');

    final refused = await body(router.route(head(path, range: 'bytes=5000-', method: 'HEAD')));
    expect(refused.$1, 416);
    expect(reads, isEmpty);
  });

  test('body length must match the advertised length', () async {
    (PlaybackRouter, String) makeRouter(List<List<int>> chunks) {
      final media = MediaResource(
        totalSize: 1000,
        prefix: Uint8List.fromList(List.filled(100, 1)),
        read: (_) => Stream.fromIterable(chunks),
      );
      final router = PlaybackRouter();
      return (router, router.register(PlaybackAssets(playlists: {}, media: {'v.mp4': media})));
    }

    final (shortRouter, shortToken) = makeRouter([List.filled(60, 2)]);
    final short = await drain(shortRouter.route(head('/$shortToken/v.mp4', range: 'bytes=200-299')));
    expect(short.$1.length, 60);
    expect(short.$2, const PlaybackBodyError.shorter(expected: 100, received: 60));

    final (longRouter, longToken) = makeRouter([List.filled(80, 2), List.filled(80, 3)]);
    final long = await drain(longRouter.route(head('/$longToken/v.mp4', range: 'bytes=200-299')));
    expect(long.$1.length, 100);
    expect(long.$2, const PlaybackBodyError.longer(expected: 100));

    // Straddling the prefix: 50 prefix bytes, then the read part (100..<150) is the one checked.
    final straddle = await drain(shortRouter.route(head('/$shortToken/v.mp4', range: 'bytes=50-149')));
    expect(straddle.$1.length, 100);
    expect(straddle.$2, const PlaybackBodyError.longer(expected: 50));

    final (exactRouter, exactToken) = makeRouter([List.filled(40, 2), List.filled(60, 2)]);
    final exact = await drain(exactRouter.route(head('/$exactToken/v.mp4', range: 'bytes=200-299')));
    expect(exact.$1.length, 100);
    expect(exact.$2, isNull);
  });

  test('tokens', () {
    final tokens = {for (var i = 0; i < 64; i++) PlaybackRouter.makeToken()};
    expect(tokens.length, 64);
    for (final token in tokens) {
      expect(token.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(token), isTrue, reason: token);
    }
  });

  test('no token or extra segments are 404', () async {
    final (router, token) = makeRouter([]);
    for (final path in [
      '/',
      '/master.m3u8',
      '/$token',
      '/$token/',
      '/$token/master.m3u8/extra',
      '//master.m3u8',
      '//$token/master.m3u8',
      '/$token//master.m3u8',
      '/$token/master.m3u8/',
      '$token/master.m3u8',
    ]) {
      final result = await body(router.route(head(path)));
      expect(result.$1, 404, reason: path);
    }
    final headRequest = await body(router.route(head('/$token/master.m3u8', method: 'HEAD')));
    expect(headRequest.$1, 200);
  });

  group('beyond the Swift tests', () {
    test('an empty head and odd request lines', () {
      expect(HTTPRequestParser.parse(utf8.encode('\r\n\r\n')), const HTTPParseInvalid());
      expect(HTTPRequestParser.parse(utf8.encode('GET /a\r\n\r\n')), const HTTPParseInvalid());
      expect(HTTPRequestParser.parse(utf8.encode('GET /a HTTP/2\r\n\r\n')), const HTTPParseInvalid());
      expect(HTTPRequestParser.parse(utf8.encode('GET /a HTTP/1.1\r\nNoColon\r\n\r\n')), const HTTPParseInvalid());
      expect(HTTPRequestParser.parse(<int>[]), const HTTPParseIncomplete());
      const rawHead = 'head  /a?b?c  HTTP/1.0\r\n  X-A :\t1 \r\n\r\n';
      final result = HTTPRequestParser.parse(utf8.encode('${rawHead}body'));
      if (result is! HTTPParseComplete) fail('expected complete');
      expect(result.head, const HTTPRequestHead(method: 'HEAD', target: '/a?b?c', path: '/a', headers: {'x-a': '1'}));
      expect(result.headerLength, rawHead.length);
    });

    test("range numbers parse like Swift's Int64", () {
      expect(RangeRequest.parse('bytes=0x10-', totalSize: 1000), const RangeRequest.unsatisfiable());
      expect(RangeRequest.parse('bytes=+5-9', totalSize: 1000), RangeRequest.range(ByteRange(5, 9)));
      expect(RangeRequest.parse('bytes= 5 - 9 ', totalSize: 1000), RangeRequest.range(ByteRange(5, 9)));
      expect(RangeRequest.parse('bytes=5\n-9', totalSize: 1000), const RangeRequest.unsatisfiable());
      expect(RangeRequest.parse('bytes=5', totalSize: 1000), const RangeRequest.unsatisfiable());
      expect(RangeRequest.parse('items=0-5', totalSize: 1000), const RangeRequest.unsatisfiable());
      expect(RangeRequest.parse('bytes=99999999999999999999-', totalSize: 1000), const RangeRequest.unsatisfiable());
    });

    test('a body nobody listens to never starts a read', () async {
      final reads = <ByteRange>[];
      final (router, token) = makeRouter(reads);
      final result = router.route(head('/$token/v.mp4', range: 'bytes=50-199'));
      expect(result, isA<RouteMedia>());
      expect(reads, isEmpty);
      await body(result);
      expect(reads, [ByteRange(100, 199)]);
    });

    for (final (name, range, firstBytes) in [('read-only', 'bytes=200-299', 10), ('spliced', 'bytes=50-299', 60)]) {
      test('cancelling a $name body cancels the read underneath', () async {
        final cancelled = Completer<void>();
        final media = MediaResource(
          totalSize: 1000,
          prefix: Uint8List(100),
          read: (_) {
            final controller = StreamController<List<int>>(onCancel: cancelled.complete);
            controller.add(Uint8List(10));
            return controller.stream;
          },
        );
        final router = PlaybackRouter();
        final token = router.register(PlaybackAssets(playlists: {}, media: {'v.mp4': media}));
        final result = router.route(head('/$token/v.mp4', range: range));
        if (result is! RouteMedia) fail('expected media');
        var received = 0;
        final readDelivered = Completer<void>();
        final subscription = result.body.listen((chunk) {
          received += chunk.length;
          if (received >= firstBytes && !readDelivered.isCompleted) readDelivered.complete();
        });
        await readDelivered.future.timeout(const Duration(seconds: 2));
        await subscription.cancel();
        await cancelled.future.timeout(const Duration(seconds: 1));
      });
    }

    test('a long body stops the read underneath', () async {
      final cancelled = Completer<void>();
      final media = MediaResource(
        totalSize: 1000,
        prefix: Uint8List(0),
        read: (_) {
          final controller = StreamController<List<int>>(onCancel: cancelled.complete);
          controller
            ..add(Uint8List(80))
            ..add(Uint8List(80));
          return controller.stream;
        },
      );
      final router = PlaybackRouter();
      final token = router.register(PlaybackAssets(playlists: {}, media: {'v.mp4': media}));
      final long = await drain(router.route(head('/$token/v.mp4', range: 'bytes=200-299')));
      expect(long.$2, const PlaybackBodyError.longer(expected: 100));
      await cancelled.future.timeout(const Duration(seconds: 1));
    });

    test('a synchronous source that overruns while being listened to', () async {
      final cancelled = Completer<void>();
      late final StreamController<List<int>> source;
      source = StreamController<List<int>>(
        sync: true,
        onListen: () => source
          ..add(Uint8List(80))
          ..add(Uint8List(80)),
        onCancel: cancelled.complete,
      );
      final media = MediaResource(totalSize: 1000, prefix: Uint8List(0), read: (_) => source.stream);
      final router = PlaybackRouter();
      final token = router.register(PlaybackAssets(playlists: {}, media: {'v.mp4': media}));
      final long = await drain(router.route(head('/$token/v.mp4', range: 'bytes=200-299')));
      expect(long.$1.length, 100);
      expect(long.$2, const PlaybackBodyError.longer(expected: 100));
      await cancelled.future.timeout(const Duration(seconds: 1));
    });

    test('pausing a body pauses the read underneath', () async {
      var paused = 0;
      var resumed = 0;
      late final StreamController<List<int>> source;
      source = StreamController<List<int>>(onPause: () => paused++, onResume: () => resumed++);
      final media = MediaResource(totalSize: 1000, prefix: Uint8List(100), read: (_) => source.stream);
      final router = PlaybackRouter();
      final token = router.register(PlaybackAssets(playlists: {}, media: {'v.mp4': media}));
      final result = router.route(head('/$token/v.mp4', range: 'bytes=50-149'));
      if (result is! RouteMedia) fail('expected media');
      final received = <int>[];
      final subscription = result.body.listen(received.addAll);
      await pumpEventQueue();
      subscription.pause();
      await pumpEventQueue();
      expect(paused, 1);
      subscription.resume();
      await pumpEventQueue();
      expect(resumed, 1);
      source.add(Uint8List(50));
      await source.close();
      await subscription.asFuture<void>();
      expect(received.length, 100);
    });
  });
}
