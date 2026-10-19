@Tags(['needs-merge'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

const _segments = 6;
const _segmentBytes = 200 * 1024;

RangeTransport _ioTransport() => IoRangeTransport();

typedef _Track = ({Uint8List bytes, ByteRange init, ByteRange index});

List<int> _u32(int value) => [for (var shift = 24; shift >= 0; shift -= 8) (value >> shift) & 0xff];

List<int> _box(String type, List<int> payload) => [..._u32(8 + payload.length), ...ascii.encode(type), ...payload];

/// ftyp, an empty moov and a version 0 sidx whose references cover the media that follows.
_Track _mp4({required int seed, bool withSidx = true}) {
  final ftyp = _box('ftyp', [...ascii.encode('isom'), ..._u32(0)]);
  final moov = _box('moov', []);
  final references = [
    for (var index = 0; index < _segments; index++) ...[..._u32(_segmentBytes), ..._u32(2000), ..._u32(0x90000000)],
  ];
  final sidx = withSidx
      ? _box('sidx', [..._u32(0), ..._u32(1), ..._u32(1000), ..._u32(0), ..._u32(0), 0, 0, 0, _segments, ...references])
      : _box('free', List.filled(36, 0));
  final header = [...ftyp, ...moov, ...sidx];
  final media = [for (var index = 0; index < _segments * _segmentBytes; index++) (index * 31 + seed) & 0xff];
  return (
    bytes: Uint8List.fromList([...header, ...media]),
    init: ByteRange(0, ftyp.length + moov.length - 1),
    index: ByteRange(ftyp.length + moov.length, header.length - 1),
  );
}

/// A CDN node on loopback: serves its files with byte ranges and counts the requests.
final class _CdnNode {
  _CdnNode._(this._server, this.files);

  static Future<_CdnNode> start(Map<String, Uint8List> files) async {
    final node = _CdnNode._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), files);
    node._server.listen(node._handle);
    return node;
  }

  final HttpServer _server;
  final Map<String, Uint8List> files;
  int requests = 0;
  bool _stopped = false;

  int get port => _server.port;

  Future<void> _handle(HttpRequest request) async {
    requests += 1;
    final file = files[request.uri.path];
    final response = request.response;
    if (file == null) {
      response.statusCode = 404;
      return response.close();
    }
    final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(request.headers.value('range') ?? '');
    final start = match == null ? 0 : int.parse(match[1]!);
    final end = match == null ? file.length - 1 : int.parse(match[2]!);
    response
      ..statusCode = match == null ? 200 : 206
      ..headers.set('content-range', 'bytes $start-$end/${file.length}')
      ..contentLength = end - start + 1
      ..add(Uint8List.sublistView(file, start, end + 1));
    await response.close();
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _server.close(force: true);
  }
}

DashStream _stream(_CdnNode node, String path, _Track track, {required int id, required String codecs}) => DashStream(
      id: id,
      baseURL: 'http://127.0.0.1:${node.port}$path?deadline=1&os=test',
      backupURLs: const [],
      bandwidth: 1000000,
      mimeType: id < 1000 ? 'video/mp4' : 'audio/mp4',
      codecs: codecs,
      codecid: id < 1000 ? 7 : 0,
      width: 1920,
      height: 1080,
      frameRate: '30',
      initialization: track.init,
      indexRange: track.index,
    );

Future<({int status, Uint8List body})> _get(Uri url, {String? range}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    if (range != null) request.headers.set('range', range);
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return (status: response.statusCode, body: builder.takeBytes());
  } finally {
    client.close(force: true);
  }
}

void main() {
  late _Track video;
  late _Track audio;
  late _CdnNode first;
  late _CdnNode second;
  late IsolatePlaybackEngine engine;
  late MemorySink log;

  PlaybackRequest request(PlaybackMode mode, {String videoPath = '/upgcxcode/v.m4s'}) => PlaybackRequest(
        choice: TrackChoice(
          video: _stream(first, videoPath, video, id: 80, codecs: 'avc1.640032'),
          audio: _stream(first, '/upgcxcode/a.m4s', audio, id: 30280, codecs: 'mp4a.40.2'),
        ),
        mode: mode,
        mediaHeaders: const {'User-Agent': 'test', 'Referer': 'https://www.bilibili.com/'},
      );

  setUp(() async {
    video = _mp4(seed: 7);
    audio = _mp4(seed: 11);
    final files = {
      '/upgcxcode/v.m4s': video.bytes,
      '/upgcxcode/a.m4s': audio.bytes,
      '/upgcxcode/nosidx.m4s': _mp4(seed: 3, withSidx: false).bytes,
    };
    first = await _CdnNode.start(files);
    second = await _CdnNode.start(files);
    log = MemorySink();
    Logger.shared.add(log);
    engine = await IsolatePlaybackEngine.start(
      transportFactory: _ioTransport,
      options: EngineOptions(
        nodeMode: CustomNodes([NodeAddress('127.0.0.1', port: first.port), NodeAddress('127.0.0.1', port: second.port)]),
        policy: MediaURLPolicy.any,
        config: const RipperConfig(fixedConcurrency: 8, pieceRounds: 2, firstByteTimeoutMs: 2000),
        statsInterval: const Duration(milliseconds: 200),
      ),
    );
  });

  tearDown(() async {
    await engine.dispose();
    Logger.shared.remove(log);
    await first.stop();
    await second.stop();
  });

  test('BTR: the local server serves the playlists and the media byte-exact', () async {
    final source = await engine.prepare(request(PlaybackMode.btr));
    expect(source.mode, PlaybackMode.btr);
    expect(source.master.host, '127.0.0.1');
    expect(source.video.path, endsWith('/v.mp4'));
    expect(source.audio.path, endsWith('/a.mp4'));
    expect(source.rewroteHEV1, isFalse);

    final master = await _get(source.master);
    expect(master.status, 200);
    expect(utf8.decode(master.body), allOf(contains('v.m3u8'), contains('a.m3u8')));
    final playlist = await _get(source.master.resolve('v.m3u8'));
    expect(utf8.decode(playlist.body), allOf(contains('v.mp4'), contains('#EXT-X-BYTERANGE')));

    final whole = await _get(source.video, range: 'bytes=0-${video.bytes.length - 1}');
    expect(whole.status, 206);
    expect(whole.body, video.bytes);
    final start = audio.index.end + 1 + 2 * _segmentBytes;
    final end = start + _segmentBytes - 1;
    final part = await _get(source.audio, range: 'bytes=$start-$end');
    expect(part.body, Uint8List.sublistView(audio.bytes, start, end + 1));
    expect(first.requests + second.requests, greaterThan(4), reason: 'headers, then pieces of both tracks');

    // The engine isolate's log events reach this isolate's Logger.shared.
    expect(await _eventually(() => log.events.any((event) => event.cat == LogCategory.engine && event.msg == 'headers')),
        isTrue);
  });

  test('stats arrive about once an interval while a BTR playback is registered', () async {
    final snapshots = <EngineSnapshot>[];
    final subscription = engine.stats.listen(snapshots.add);
    addTearDown(subscription.cancel);
    final source = await engine.prepare(request(PlaybackMode.btr));
    await _get(source.video, range: 'bytes=0-${video.bytes.length - 1}');
    expect(await _eventually(() => snapshots.any((snapshot) => snapshot.deliveredBytes > 0)), isTrue);
    final last = snapshots.last;
    expect(last.transport, 'dart:io');
    expect(last.concurrency, 8);
    expect(last.nodeStates.map((status) => status.node).toSet(), hasLength(2));
    await engine.release(source.token);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final count = snapshots.length;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(snapshots.length, count, reason: 'no stats without a BTR playback');
  });

  test('setNodeMode moves the sessions prepared after it to the new nodes', () async {
    final snapshots = <EngineSnapshot>[];
    final subscription = engine.stats.listen(snapshots.add);
    addTearDown(subscription.cancel);
    Set<String> latestNodes() => {for (final status in snapshots.last.nodeStates) status.node};

    final before = await engine.prepare(request(PlaybackMode.btr));
    await _get(before.video, range: 'bytes=0-${video.bytes.length - 1}');
    expect(await _eventually(() => snapshots.isNotEmpty && latestNodes().length == 2), isTrue);
    await engine.release(before.token);

    // Another host name, so the request's own 127.0.0.1 address is out of the mode too.
    engine.setNodeMode(CustomNodes([NodeAddress('localhost', port: second.port)]));
    snapshots.clear();
    final after = await engine.prepare(request(PlaybackMode.btr));
    final whole = await _get(after.video, range: 'bytes=0-${video.bytes.length - 1}');
    expect(whole.body, video.bytes);
    expect(await _eventually(() => snapshots.isNotEmpty), isTrue);
    expect(latestNodes(), hasLength(1), reason: 'only the new mode\'s node');
    expect(latestNodes().single, 'localhost:${second.port}');
    bool logged(LogEvent event) => event.msg == 'node mode' && event.f['mode'] == const LogString('custom 1');
    expect(await _eventually(() => log.events.any(logged)), isTrue);
  });

  test('release forgets the playlists, and releasing again or an unknown token is a no-op', () async {
    final source = await engine.prepare(request(PlaybackMode.btr));
    await engine.release(source.token);
    expect((await _get(source.master)).status, 404);
    await engine.release(source.token);
    await engine.release('unknown');
  });

  test('ensureServing binds again after the server stopped answering', () async {
    expect(await engine.ensureServing(), isFalse);
    await engine.debugStopServer();
    expect(await engine.ensureServing(), isTrue);
    final source = await engine.prepare(request(PlaybackMode.btr));
    expect((await _get(source.master)).status, 200);
    expect(await engine.ensureServing(), isFalse);
  });

  test('direct: the playlists come from the local server and the media from the CDN', () async {
    final wanted = request(PlaybackMode.direct);
    final source = await engine.prepare(wanted);
    expect(source.mode, PlaybackMode.direct);
    expect(source.video, Uri.parse(wanted.choice.video.baseURL));
    expect(source.audio, Uri.parse(wanted.choice.audio.baseURL));
    expect(source.mediaHeaders, wanted.mediaHeaders);
    expect(source.master.host, '127.0.0.1');
    final playlist = await _get(source.master.resolve('v.m3u8'));
    expect(utf8.decode(playlist.body), contains(wanted.choice.video.baseURL));
  });

  test('errors cross the isolate as the same PlaybackError and RipperError values', () async {
    await expectLater(
      engine.prepare(request(PlaybackMode.btr, videoPath: '/upgcxcode/nosidx.m4s')),
      throwsA(isA<PlaybackError>().having((error) => error.kind, 'kind', PlaybackErrorKind.noSidx)),
    );
    await expectLater(
      engine.prepare(request(PlaybackMode.btr, videoPath: '/upgcxcode/missing.m4s')),
      throwsA(const RipperError.badResponse(404)),
    );
  });

  test('PlaybackEngine.start spawns the isolate engine', () async {
    final started = await PlaybackEngine.start(transportFactory: _ioTransport);
    addTearDown(started.dispose);
    expect(started, isA<IsolatePlaybackEngine>());
    expect(await started.ensureServing(), isFalse);
  });

  test('after dispose every call fails as closed', () async {
    await engine.dispose();
    await expectLater(engine.prepare(request(PlaybackMode.btr)), throwsA(const RipperError(RipperErrorKind.closed)));
    await expectLater(engine.ensureServing(), throwsA(const RipperError(RipperErrorKind.closed)));
    // Fire-and-forget calls have nobody to fail to; they are dropped.
    engine
      ..updatePlayhead('gone', seconds: 1, rate: 1)
      ..reportBuffer('gone', aheadSeconds: 1, playing: true)
      ..reportStall('gone')
      ..dropCache()
      ..dropPrefetch('gone');
    expect(await engine.fatals.isEmpty, isTrue, reason: 'the fatal reports end with the engine');
  });

  group('playhead, buffer, stalls and fatal reports', () {
    late List<EngineSnapshot> snapshots;
    late PreparedSource source;

    /// The video track's media segment [index], as the player asks for it.
    Future<void> segment(int index) {
      final start = video.index.end + 1 + index * _segmentBytes;
      return _get(source.video, range: 'bytes=$start-${start + _segmentBytes - 1}');
    }

    /// Segment 0 is the player's; the other five arrive as prefetch and wait in the cache.
    Future<void> playFirstAndPrefetch() async {
      final subscription = engine.stats.listen(snapshots.add);
      addTearDown(subscription.cancel);
      source = await engine.prepare(request(PlaybackMode.btr));
      await segment(0);
      expect(await _eventually(() => snapshots.any((snapshot) => snapshot.deliveredBytes >= _segments * _segmentBytes)),
          isTrue);
    }

    Future<EngineSnapshot> snapshotWithMisses(int misses) async {
      expect(await _eventually(() => snapshots.lastOrNull?.cacheMisses == misses), isTrue);
      return snapshots.last;
    }

    setUp(() => snapshots = []);

    test('a playhead update reaches the session without a reply: segments it left behind leave the cache', () async {
      await playFirstAndPrefetch();
      await segment(1);
      engine.updatePlayhead(source.token, seconds: 100, rate: 1);
      // Commands are handled in order, so the update was applied once this answer is in.
      expect(await engine.ensureServing(), isFalse);
      await segment(2);
      final snapshot = await snapshotWithMisses(2);
      expect(snapshot.cacheHits, 1, reason: 'segment 1 came from the cache; segment 2 was dropped and fetched again');
    });

    test('dropCache empties the cache; buffer and stall reports are taken without a reply', () async {
      await playFirstAndPrefetch();
      engine
        ..reportBuffer(source.token, aheadSeconds: 12, playing: true)
        ..reportStall(source.token)
        ..reportStall('unknown')
        ..dropCache();
      expect(await engine.ensureServing(), isFalse);
      await segment(1);
      final snapshot = await snapshotWithMisses(2);
      expect(snapshot.cacheHits, 0);
    });

    test('dropPrefetch empties only the named playback\'s cache; each snapshot names the playback it describes',
        () async {
      Future<void> read(PreparedSource from, int index) {
        final start = video.index.end + 1 + index * _segmentBytes;
        return _get(from.video, range: 'bytes=$start-${start + _segmentBytes - 1}');
      }

      await playFirstAndPrefetch();
      final covered = source;
      expect(snapshots.last.token, covered.token);
      final shown = await engine.prepare(request(PlaybackMode.btr));
      await read(shown, 0);
      expect(
          await _eventually(() => snapshots.any((snapshot) =>
              snapshot.token == shown.token && snapshot.deliveredBytes >= _segments * _segmentBytes)),
          isTrue);
      engine.dropPrefetch(covered.token);
      expect(await engine.ensureServing(), isFalse);
      await read(shown, 1);
      expect(await _eventually(() => snapshots.last.token == shown.token && snapshots.last.cacheHits == 1), isTrue,
          reason: 'the playback on top kept its prefetch');

      await engine.release(shown.token);
      await read(covered, 1);
      expect(await _eventually(() => snapshots.last.token == covered.token && snapshots.last.cacheMisses == 2), isTrue);
      expect(snapshots.last.cacheHits, 0, reason: 'the covered playback\'s prefetch was dropped');
    });

    test('a BTR read that fails after every retry is reported with its token', () async {
      source = await engine.prepare(request(PlaybackMode.btr));
      final fatal = engine.fatals.first.timeout(const Duration(seconds: 10));
      await first.stop();
      await second.stop();
      try {
        await segment(3);
      } on IOException {
        // The local server breaks the response off.
      }
      final report = await fatal;
      expect(report.token, source.token);
      expect(report.message, isNotEmpty);
    });
  });

  test('by default the engine\'s debug events stay in its isolate', () async {
    final source = await engine.prepare(request(PlaybackMode.btr));
    await _get(source.video, range: 'bytes=0-${video.bytes.length - 1}');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(log.events.where((event) => event.cat == LogCategory.engine && event.level == LogLevel.debug), isEmpty);
  });

  // BiliFast's own startup and seek speed-ups, as the app runs them.
  group('startup and seek', () {
    late IsolatePlaybackEngine fast;

    setUp(() async {
      fast = await IsolatePlaybackEngine.start(
        transportFactory: _ioTransport,
        options: EngineOptions(
          nodeMode:
              CustomNodes([NodeAddress('127.0.0.1', port: first.port), NodeAddress('127.0.0.1', port: second.port)]),
          policy: MediaURLPolicy.any,
          config: const RipperConfig(
            fixedConcurrency: 8,
            pieceRounds: 2,
            firstByteTimeoutMs: 2000,
            primeStart: true,
            streamAdopted: true,
            seekBurst: true,
            audioFirst: true,
          ),
          statsInterval: const Duration(milliseconds: 200),
          forwardDebugLogs: true,
        ),
      );
    });

    tearDown(() => fast.dispose());

    Iterable<LogEvent> named(String msg) =>
        log.events.where((event) => event.cat == LogCategory.engine && event.msg == msg);
    int done(String msg) => named(msg).where((event) => event.f['outcome'] == const LogString('done')).length;

    test('prepare primes both tracks at the start position, and the player\'s read takes it over', () async {
      final wanted = request(PlaybackMode.btr);
      final source = await fast.prepare(PlaybackRequest(
          choice: wanted.choice, mode: wanted.mode, mediaHeaders: wanted.mediaHeaders, startSeconds: 4.5));
      expect(await _eventually(() => done('prime') == 2), isTrue);
      final primes = named('prime').toList();
      expect(primes.map((event) => event.f['track']).toSet(), {const LogString('video'), const LogString('audio')});
      expect(primes.every((event) => event.f['segment'] == const LogInt(2)), isTrue, reason: '4.5 s is in segment 2');
      final start = video.index.end + 1 + 2 * _segmentBytes;
      final range = '$start-${start + _segmentBytes - 1}';
      final segment = await _get(source.video, range: 'bytes=$range');
      expect(segment.body, Uint8List.sublistView(video.bytes, start, start + _segmentBytes));
      expect(
          await _eventually(() => named('read').any((event) =>
              event.f['range'] == LogString(range) &&
              (event.f['source'] == const LogString('memory') || event.f['source'] == const LogString('prime')))),
          isTrue,
          reason: 'the primed segment came from memory');
    });

    test('a hint starts both tracks where the finger rests', () async {
      final source = await fast.prepare(request(PlaybackMode.btr));
      fast.hint(source.token, 9);
      expect(await _eventually(() => done('hint') == 2), isTrue);
      expect(named('hint').every((event) => event.f['segment'] == const LogInt(4)), isTrue);
    });

    test('preconnect opens a connection to every node of the playurl', () async {
      final before = (first: first.requests, second: second.requests);
      fast.preconnect([request(PlaybackMode.btr).choice.video.baseURL]);
      expect(await _eventually(() => named('preconnect').isNotEmpty), isTrue);
      final event = named('preconnect').single;
      expect(event.f['nodes'], const LogInt(2));
      expect(event.f['answered'], const LogInt(2));
      expect(first.requests, before.first + 1);
      expect(second.requests, before.second + 1);
    });

    test('preconnect after setNodeMode warms only the new mode\'s nodes', () async {
      final before = (first: first.requests, second: second.requests);
      // Another host name, so the playurl's own 127.0.0.1 address is out of the mode too.
      fast.setNodeMode(CustomNodes([NodeAddress('localhost', port: second.port)]));
      fast.preconnect([request(PlaybackMode.btr).choice.video.baseURL]);
      expect(await _eventually(() => named('preconnect').isNotEmpty), isTrue);
      final event = named('preconnect').single;
      expect(event.f['nodes'], const LogInt(1));
      expect(event.f['answered'], const LogInt(1));
      expect(first.requests, before.first, reason: 'the old mode\'s other node is left cold');
      expect(second.requests, before.second + 1);
    });

    test('the engine\'s debug events reach this isolate when asked', () async {
      final source = await fast.prepare(request(PlaybackMode.btr));
      await _get(source.video, range: 'bytes=0-${video.bytes.length - 1}');
      expect(await _eventually(() => named('piece').any((event) => event.level == LogLevel.debug)), isTrue);
    });
  });
}

Future<bool> _eventually(bool Function() condition, {double seconds = 3}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return condition();
}
