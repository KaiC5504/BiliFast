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

  Future<void> stop() => _server.close(force: true);
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
