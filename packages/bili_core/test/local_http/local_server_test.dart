import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bili_core/local_http.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

List<int> staticContent(int size, int start, int end) => [for (var i = start; i <= end; i++) (i * 13) & 0xFF];

/// master.m3u8 plus a media file "v.mp4" whose first 100 bytes come from memory.
String registerStaticAssets(PlaybackRouter router, int size, {void Function(ByteRange range)? onRead}) {
  final all = Uint8List.fromList(staticContent(size, 0, size - 1));
  final media = MediaResource(
    totalSize: size,
    prefix: all.sublist(0, 100),
    read: (range) {
      onRead?.call(range);
      return Stream.value(all.sublist(range.start, range.end + 1));
    },
  );
  return router.register(PlaybackAssets(playlists: {'master.m3u8': '#EXTM3U\n'}, media: {'v.mp4': media}));
}

/// "hang.mp4": every read starts ([onRead]), yields [first] and then nothing; [onEnd] fires when the read is cancelled.
String registerHangingAsset(
  PlaybackRouter router, {
  required void Function() onRead,
  required void Function() onEnd,
  List<int> first = const [],
}) {
  final media = MediaResource(
    totalSize: 10000,
    prefix: Uint8List(0),
    read: (_) {
      onRead();
      final controller = StreamController<List<int>>(onCancel: onEnd);
      if (first.isNotEmpty) controller.add(first);
      return controller.stream;
    },
  );
  return router.register(PlaybackAssets(playlists: {}, media: {'hang.mp4': media}));
}

Future<({int status, HttpHeaders headers, List<int> body})> fetch(Uri url, {String method = 'GET', String? range}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, url);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final body = await response.fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    return (status: response.statusCode, headers: response.headers, body: body);
  } finally {
    client.close(force: true);
  }
}

/// Sends [request] as is and collects everything until the server closes the connection.
Future<List<int>> exchange(int port, List<int> request) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  socket.done.ignore();
  socket.add(request);
  final bytes = await socket.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
  socket.destroy();
  return bytes;
}

Future<String> exchangeText(int port, String request) async => latin1.decode(await exchange(port, latin1.encode(request)));

void main() {
  test('serves playlists and ranges', () async {
    final router = PlaybackRouter();
    final server = await LocalServer.start(router);
    addTearDown(server.close);
    final token = registerStaticAssets(router, 10000);

    final playlist = await fetch(server.url(token, 'master.m3u8'));
    expect(playlist.status, 200);
    expect(utf8.decode(playlist.body), '#EXTM3U\n');

    final ranged = await fetch(server.url(token, 'v.mp4'), range: 'bytes=50-149');
    expect(ranged.status, 206);
    expect(ranged.headers.value('content-range'), 'bytes 50-149/10000');
    expect(ranged.body, staticContent(10000, 50, 149));

    final missing = await fetch(Uri.parse('http://127.0.0.1:${server.port}/nope/master.m3u8'));
    expect(missing.status, 404);
  });

  test('HEAD sends headers without reading media', () async {
    final router = PlaybackRouter();
    final server = await LocalServer.start(router);
    addTearDown(server.close);
    var reads = 0;
    final token = registerStaticAssets(router, 10000, onRead: (_) => reads++);

    final media = await fetch(server.url(token, 'v.mp4'), method: 'HEAD', range: 'bytes=500-1499');
    expect(media.status, 206);
    expect(media.headers.value('content-length'), '1000');
    expect(media.body, isEmpty);
    expect(reads, 0);

    final playlist = await fetch(server.url(token, 'master.m3u8'), method: 'HEAD');
    expect(playlist.status, 200);
    expect(playlist.body, isEmpty);

    await fetch(server.url(token, 'v.mp4'), range: 'bytes=500-1499');
    expect(reads, 1);
  });

  test('a restart after close during a restart begins a new listener', () async {
    final router = PlaybackRouter();
    final server = await LocalServer.start(router);
    addTearDown(server.close);
    final first = server.restart();
    await server.close();
    await server.restart();
    await expectLater(first, throwsStateError);
    expect(server.isRunning, isTrue);
    final token = registerStaticAssets(router, 1000);
    final response = await fetch(server.url(token, 'master.m3u8'));
    expect(response.status, 200);
  });

  test('a restart drops the old listener quietly and the new one answers', () async {
    final server = await LocalServer.start(PlaybackRouter());
    addTearDown(server.close);
    var stops = 0;
    server.onStop = () => stops++;
    expect(await server.answers(), isTrue);

    final oldPort = server.port;
    await server.restart();
    expect(server.isRunning, isTrue);
    expect(server.port, isNot(oldPort));
    expect(await server.answers(), isTrue);
    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, oldPort, timeout: const Duration(seconds: 3)),
      throwsA(isA<SocketException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(stops, 0);
  });

  test('a client disconnect ends the engine read promptly', () async {
    final router = PlaybackRouter();
    final server = await LocalServer.start(router);
    addTearDown(server.close);
    final readStarted = Completer<void>();
    final readEnded = Completer<void>();
    final token = registerHangingAsset(
      router,
      onRead: () {
        if (!readStarted.isCompleted) readStarted.complete();
      },
      onEnd: readEnded.complete,
    );

    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    socket.done.ignore();
    socket.add(latin1.encode('GET /$token/hang.mp4 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n'));
    await readStarted.future.timeout(const Duration(seconds: 5));
    socket.destroy();
    await readEnded.future.timeout(const Duration(milliseconds: 1500));
  });

  group('beyond the Swift tests', () {
    test('a client that disconnects mid-body cancels the media stream', () async {
      final router = PlaybackRouter();
      final server = await LocalServer.start(router);
      addTearDown(server.close);
      final readEnded = Completer<void>();
      final token = registerHangingAsset(router, onRead: () {}, onEnd: readEnded.complete, first: List.filled(4000, 9));

      final client = HttpClient();
      final request = await client.getUrl(server.url(token, 'hang.mp4'));
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(response.contentLength, 10000);
      var received = 0;
      final gotSome = Completer<void>();
      final subscription = response.listen((chunk) {
        received += chunk.length;
        if (received >= 4000 && !gotSome.isCompleted) gotSome.complete();
      }, onError: (Object _) {});
      await gotSome.future.timeout(const Duration(seconds: 5));
      await subscription.cancel();
      client.close(force: true);
      await readEnded.future.timeout(const Duration(milliseconds: 1500));
      expect(received, 4000);
    });

    test('exact response shapes: HEAD, playlist and failures', () async {
      final router = PlaybackRouter();
      final server = await LocalServer.start(router);
      addTearDown(server.close);
      var reads = 0;
      final token = registerStaticAssets(router, 10000, onRead: (_) => reads++);
      final port = server.port;

      expect(
        await exchangeText(port, 'HEAD /$token/v.mp4 HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=500-1499\r\n\r\n'),
        'HTTP/1.1 206 Partial Content\r\nContent-Type: video/mp4\r\nAccept-Ranges: bytes\r\nContent-Length: 1000\r\n'
        'Content-Range: bytes 500-1499/10000\r\nConnection: close\r\n\r\n',
      );
      expect(
        await exchangeText(port, 'HEAD /$token/v.mp4 HTTP/1.1\r\n\r\n'),
        'HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nAccept-Ranges: bytes\r\nContent-Length: 10000\r\n'
        'Connection: close\r\n\r\n',
      );
      expect(reads, 0);
      expect(
        await exchangeText(port, 'GET /$token/master.m3u8?x=1 HTTP/1.1\r\n\r\n'),
        'HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\nContent-Length: 8\r\nConnection: close\r\n\r\n'
        '#EXTM3U\n',
      );
      expect(
        await exchangeText(port, 'HEAD /$token/master.m3u8 HTTP/1.1\r\n\r\n'),
        'HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\nContent-Length: 8\r\nConnection: close\r\n\r\n',
      );
      expect(
        await exchangeText(port, 'GET /nope/master.m3u8 HTTP/1.1\r\n\r\n'),
        'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n',
      );
      expect(
        await exchangeText(port, 'POST /$token/master.m3u8 HTTP/1.1\r\nContent-Length: 0\r\n\r\n'),
        'HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n',
      );
      expect(
        await exchangeText(port, 'GET /$token/v.mp4 HTTP/1.1\r\nRange: bytes=20000-\r\n\r\n'),
        'HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */10000\r\nContent-Length: 0\r\nConnection: close\r\n\r\n',
      );
      expect(reads, 0);
    });

    test('a range across the prefix boundary splices prefix and read bytes', () async {
      final router = PlaybackRouter();
      final server = await LocalServer.start(router);
      addTearDown(server.close);
      final all = Uint8List.fromList(staticContent(10000, 0, 9999));
      final reads = <ByteRange>[];
      final media = MediaResource(
        totalSize: 10000,
        prefix: all.sublist(0, 100),
        read: (range) async* {
          reads.add(range);
          for (var start = range.start; start <= range.end; start += 7) {
            await Future<void>.delayed(Duration.zero);
            yield all.sublist(start, min(start + 7, range.end + 1));
          }
        },
      );
      final token = router.register(PlaybackAssets(playlists: {}, media: {'v.mp4': media}));

      final bytes = await exchange(server.port, latin1.encode('GET /$token/v.mp4 HTTP/1.1\r\nRange: bytes=37-160\r\n\r\n'));
      final head = latin1.encode(
        'HTTP/1.1 206 Partial Content\r\nContent-Type: video/mp4\r\nAccept-Ranges: bytes\r\nContent-Length: 124\r\n'
        'Content-Range: bytes 37-160/10000\r\nConnection: close\r\n\r\n',
      );
      expect(bytes.sublist(0, head.length), head);
      expect(bytes.sublist(head.length), all.sublist(37, 161));
      expect(reads, [ByteRange(100, 160)]);
    });

    test('a restart gives a new port that serves the same token', () async {
      final router = PlaybackRouter();
      final server = await LocalServer.start(router);
      addTearDown(server.close);
      final token = registerStaticAssets(router, 10000);
      final before = server.url(token, 'v.mp4');
      expect(before.toString(), 'http://127.0.0.1:${server.port}/$token/v.mp4');

      await server.restart();
      final after = server.url(token, 'v.mp4');
      expect(after.port, isNot(before.port));
      expect(after.path, before.path);
      final response = await fetch(after, range: 'bytes=0-199');
      expect(response.status, 206);
      expect(response.body, staticContent(10000, 0, 199));
    });

    test('concurrent restarts share one listener', () async {
      final server = await LocalServer.start(PlaybackRouter());
      addTearDown(server.close);
      final first = server.restart();
      final second = server.restart();
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(await server.answers(), isTrue);
    });

    test('close ends open connections, cancels their reads and stops answering', () async {
      final router = PlaybackRouter();
      final server = await LocalServer.start(router);
      var stops = 0;
      server.onStop = () => stops++;
      final readStarted = Completer<void>();
      final readEnded = Completer<void>();
      final token = registerHangingAsset(
        router,
        onRead: () {
          if (!readStarted.isCompleted) readStarted.complete();
        },
        onEnd: readEnded.complete,
      );

      final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      socket.done.ignore();
      socket.add(latin1.encode('GET /$token/hang.mp4 HTTP/1.1\r\n\r\n'));
      final endedByServer = socket.drain<void>().then((_) {}, onError: (Object _) {});
      await readStarted.future.timeout(const Duration(seconds: 5));

      await server.close();
      await readEnded.future.timeout(const Duration(seconds: 1));
      await endedByServer.timeout(const Duration(seconds: 2));
      socket.destroy();
      expect(server.isRunning, isFalse);
      expect(await server.answers(), isFalse);
      expect(stops, 1);
    });

    test('a request split across packets is answered', () async {
      final router = PlaybackRouter();
      final server = await LocalServer.start(router);
      addTearDown(server.close);
      final token = registerStaticAssets(router, 1000);

      final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      socket.done.ignore();
      final received = socket.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      for (final piece in ['GET /$token/mas', 'ter.m3u8 HTTP/1.1\r\nHo', 'st: x\r\n', '\r\n']) {
        socket.add(latin1.encode(piece));
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final text = latin1.decode(await received);
      socket.destroy();
      expect(text, startsWith('HTTP/1.1 200 OK\r\n'));
      expect(text, endsWith('\r\n\r\n#EXTM3U\n'));
    });

    test('an invalid or oversized request gets a 400 and the connection closes', () async {
      final server = await LocalServer.start(PlaybackRouter());
      addTearDown(server.close);
      const badRequest = 'HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n';
      expect(await exchangeText(server.port, 'NONSENSE\r\n\r\n'), badRequest);
      expect(await exchangeText(server.port, 'A' * 17000), badRequest);
    });

    test('a read that fails mid-body ends the connection short of Content-Length', () async {
      final router = PlaybackRouter();
      final server = await LocalServer.start(router);
      addTearDown(server.close);
      final media = MediaResource(
        totalSize: 1000,
        prefix: Uint8List(0),
        read: (_) async* {
          yield List.filled(30, 5);
          throw StateError('engine gave up');
        },
      );
      final token = router.register(PlaybackAssets(playlists: {}, media: {'v.mp4': media}));

      final text = await exchangeText(server.port, 'GET /$token/v.mp4 HTTP/1.1\r\nRange: bytes=200-299\r\n\r\n');
      final split = text.indexOf('\r\n\r\n') + 4;
      expect(text.substring(0, split), contains('Content-Length: 100\r\n'));
      expect(text.length - split, 30);
    });

    test('a client that stops reading pauses the media read', () async {
      final router = PlaybackRouter();
      final server = await LocalServer.start(router);
      addTearDown(server.close);
      const total = 64 << 20;
      var produced = 0;
      final media = MediaResource(
        totalSize: total,
        prefix: Uint8List(0),
        read: (range) async* {
          final chunk = Uint8List(64 << 10);
          while (produced < range.length) {
            produced += chunk.length;
            yield chunk;
          }
        },
      );
      final token = router.register(PlaybackAssets(playlists: {}, media: {'v.mp4': media}));

      final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      socket.done.ignore();
      var received = 0;
      final subscription = socket.listen((chunk) => received += chunk.length);
      subscription.pause();
      socket.add(latin1.encode('GET /$token/v.mp4 HTTP/1.1\r\n\r\n'));

      var last = -1;
      for (var attempt = 0; attempt < 50 && produced != last; attempt++) {
        last = produced;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(produced, lessThan(total ~/ 2), reason: 'the read ran ahead of a client that reads nothing');
      expect(produced, greaterThan(0));

      subscription.resume();
      await subscription.asFuture<void>();
      socket.destroy();
      expect(produced, total);
      expect(received, greaterThan(total));
    });
  });
}
