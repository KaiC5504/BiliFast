import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/local_http.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/local_source.dart';
import 'package:test/test.dart';

import '../dash_hls/playback_fixtures.dart';

const _segments = 4;
const _segmentBytes = 300 * 1024;

RangeTransport _ioTransport() => IoRangeTransport();

typedef _Track = ({Uint8List bytes, ByteRange init, ByteRange index});

List<int> _u32(int value) => [for (var shift = 24; shift >= 0; shift -= 8) (value >> shift) & 0xff];

List<int> _box(String type, List<int> payload) => [..._u32(8 + payload.length), ...ascii.encode(type), ...payload];

/// ftyp, an empty moov and a version 0 sidx over [_segments] segments of [_segmentBytes], then random media, so a
/// read from the wrong offset can't match by accident.
_Track _mp4(int seed) {
  final ftyp = _box('ftyp', [...ascii.encode('isom'), ..._u32(0)]);
  final moov = _box('moov', []);
  final references = [
    for (var index = 0; index < _segments; index++) ...[..._u32(_segmentBytes), ..._u32(2000), ..._u32(0x90000000)],
  ];
  final sidx = _box('sidx', [
    ..._u32(0), ..._u32(1), ..._u32(1000), ..._u32(0), ..._u32(0), 0, 0, 0, _segments, ...references,
  ]);
  final header = [...ftyp, ...moov, ...sidx];
  final random = Random(seed);
  final bytes = Uint8List(header.length + _segments * _segmentBytes)..setAll(0, header);
  for (var index = header.length; index < bytes.length; index++) {
    bytes[index] = random.nextInt(256);
  }
  return (
    bytes: bytes,
    init: ByteRange(0, ftyp.length + moov.length - 1),
    index: ByteRange(ftyp.length + moov.length, header.length - 1),
  );
}

/// As the playurl answer gives it, signed address and all; a 离线缓存 part keeps it [DashStream.withoutAddresses].
DashStream _stream(_Track track, {required int id, required String codecs}) => DashStream(
  id: id,
  baseURL: 'https://primary.invalid/upgcxcode/$id.m4s?deadline=1&upsig=sig',
  backupURLs: ['https://backup.invalid/upgcxcode/$id.m4s?deadline=1&upsig=sig'],
  bandwidth: id < 1000 ? 4000000 : 128000,
  mimeType: id < 1000 ? 'video/mp4' : 'audio/mp4',
  codecs: codecs,
  codecid: id < 1000 ? 7 : 0,
  width: id < 1000 ? 1920 : 0,
  height: id < 1000 ? 1080 : 0,
  frameRate: id < 1000 ? '30' : null,
  initialization: track.init,
  indexRange: track.index,
);

Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<bool> _eventually(bool Function() check) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (check()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return check();
}

Future<({int status, Uint8List body})> _get(Uri url, {String? range}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    if (range != null) request.headers.set('range', range);
    final response = await request.close();
    return (status: response.statusCode, body: await _collect(response));
  } finally {
    client.close(force: true);
  }
}

Matcher _throwsNoSource() =>
    throwsA(isA<PlaybackError>().having((error) => error.kind, 'kind', PlaybackErrorKind.noSource));

void main() {
  late Directory folder;
  late _Track video;
  late _Track audio;
  late DashStream videoStream;
  late DashStream audioStream;
  late String videoPath;
  late String audioPath;
  late LocalPlaybackRequest request;
  late CapturedLog log;

  setUpAll(() {
    video = _mp4(7);
    audio = _mp4(11);
    videoStream = _stream(video, id: 120, codecs: 'avc1.640034');
    audioStream = _stream(audio, id: 30280, codecs: 'mp4a.40.2');
  });

  setUp(() {
    folder = Directory.systemTemp.createTempSync('local_source_');
    videoPath = '${folder.path}${Platform.pathSeparator}v.m4s';
    audioPath = '${folder.path}${Platform.pathSeparator}a.m4s';
    File(videoPath).writeAsBytesSync(video.bytes);
    File(audioPath).writeAsBytesSync(audio.bytes);
    request = LocalPlaybackRequest(
      video: videoStream.withoutAddresses(),
      audio: audioStream.withoutAddresses(),
      videoPath: videoPath,
      audioPath: audioPath,
    );
    log = CapturedLog();
  });

  tearDown(() {
    log.stop();
    // On Windows this fails while any file in it is still open.
    folder.deleteSync(recursive: true);
  });

  Future<PreparedPlayback> prepareBtr(TrackChoice choice, Map<TrackKind, Uint8List> files) => PlaybackBuilder.prepare(
    choice,
    fetchHeaders: (kind, stream) async {
      final file = files[kind]!;
      return (bytes: Uint8List.sublistView(file, 0, stream.indexRange.end + 1), total: file.length);
    },
  );

  group('prepare', () {
    test('builds what a BTR playback of the same streams builds, with the same playlists and media', () async {
      final local = await LocalSource.prepare(request);
      final btr = await prepareBtr(TrackChoice(video: videoStream, audio: audioStream), {
        TrackKind.video: video.bytes,
        TrackKind.audio: audio.bytes,
      });
      expect(local.video.headers, btr.video.headers);
      expect(local.video.headers, Uint8List.sublistView(video.bytes, 0, video.index.end + 1));
      expect(local.audio.headers, btr.audio.headers);
      expect(local.video.totalSize, video.bytes.length);
      expect(local.audio.totalSize, audio.bytes.length);
      expect(local.video.segments, hasLength(_segments));
      expect(local.rewroteHEV1, btr.rewroteHEV1);
      expect(local.sourceEntry, btr.sourceEntry);

      final assets = LocalSource.assets(local, request);
      final ripper = PlaybackBuilder.ripperAssets(btr, read: (_, _) => const Stream.empty(), peakBandwidth: true);
      expect(assets.playlists, ripper.playlists);
      expect(assets.playlists['v.m3u8'], contains('#EXT-X-MAP:URI="v.mp4",BYTERANGE="${video.init.length}@0"'));
      expect(assets.playlists['a.m3u8'], contains('\na.mp4\n'));
      expect(assets.playlists.values.join(), isNot(contains('invalid')), reason: 'no address reaches a playlist');
      expect(assets.media.keys.toSet(), ripper.media.keys.toSet());
      for (final name in ['v.mp4', 'a.mp4']) {
        expect(assets.media[name]!.prefix, ripper.media[name]!.prefix, reason: name);
        expect(assets.media[name]!.totalSize, ripper.media[name]!.totalSize, reason: name);
      }
      expect(log.named('local source').single.f, {
        'videoBytes': LogInt(video.bytes.length),
        'audioBytes': LogInt(audio.bytes.length),
        'segments': const LogInt(_segments),
        'rewroteHEV1': const LogBool(false),
      });
      expect(LocalSource.openFiles, 0);
    });

    test('a hev1 init is served as hvc1 exactly as in BTR, and the file keeps its own bytes', () async {
      final fixture = headerFixture(withMoov: true, videoEntry: 'hev1', videoCodecs: 'hev1.1.6.L120.90');
      final file = Uint8List.fromList([...fixture.bytes, ...List.filled(fixture.total - fixture.bytes.length, 9)]);
      File(videoPath).writeAsBytesSync(file);
      File(audioPath).writeAsBytesSync(file);
      final hev1 = LocalPlaybackRequest(
        video: fixture.choice.video.withoutAddresses(),
        audio: fixture.choice.audio.withoutAddresses(),
        videoPath: videoPath,
        audioPath: audioPath,
      );
      final local = await LocalSource.prepare(hev1);
      final btr = await prepareBtr(fixture.choice, {TrackKind.video: file, TrackKind.audio: file});
      expect(local.rewroteHEV1, isTrue);
      expect(local.sourceEntry, 'hev1');
      expect(local.video.headers, btr.video.headers);
      expect(latin1.decode(local.video.headers), allOf(contains('hvc1'), isNot(contains('hev1'))));
      expect(latin1.decode(File(videoPath).readAsBytesSync()), contains('hev1'));

      final assets = LocalSource.assets(local, hev1);
      final ripper = PlaybackBuilder.ripperAssets(btr, read: (_, _) => const Stream.empty(), peakBandwidth: true);
      expect(assets.playlists, ripper.playlists);
      expect(assets.playlists['master.m3u8'], contains('CODECS="hvc1.1.6.L120.90,mp4a.40.2"'));
      expect(assets.media['v.mp4']!.prefix, ripper.media['v.mp4']!.prefix);
    });

    test('a missing file throws noSource and logs which, by name only', () async {
      File(videoPath).deleteSync();
      await expectLater(LocalSource.prepare(request), _throwsNoSource());
      expect(log.named('local file unusable').single.f, {
        'track': const LogString('video'),
        'file': const LogString('v.m4s'),
        'reason': const LogString('missing'),
      });
      expect(await _eventually(() => LocalSource.openFiles == 0), isTrue, reason: "the audio file's read closes too");

      File(videoPath).writeAsBytesSync(video.bytes);
      File(audioPath).deleteSync();
      await expectLater(LocalSource.prepare(request), _throwsNoSource());
      expect(log.named('local file unusable').last.f['track'], const LogString('audio'));
      expect(LocalSource.openFiles, 0);
    });

    test('a file shorter than its headers throws noSource', () async {
      File(audioPath).writeAsBytesSync(Uint8List.sublistView(audio.bytes, 0, audio.index.end));
      await expectLater(LocalSource.prepare(request), _throwsNoSource());
      expect(log.named('local file unusable').single.f, {
        'track': const LogString('audio'),
        'file': const LogString('a.m4s'),
        'reason': const LogString('short'),
        'size': LogInt(audio.index.end),
        'needed': LogInt(audio.index.end + 1),
      });
      expect(LocalSource.openFiles, 0);
    });

    test('a file cut short in its media throws noSource', () async {
      File(videoPath).writeAsBytesSync(Uint8List.sublistView(video.bytes, 0, video.bytes.length - 1));
      await expectLater(LocalSource.prepare(request), _throwsNoSource());
      expect(log.named('local file unusable').single.f, {
        'track': const LogString('video'),
        'file': const LogString('v.m4s'),
        'reason': const LogString('short'),
        'size': LogInt(video.bytes.length - 1),
        'needed': LogInt(video.bytes.length),
      });
      expect(log.named('local source'), isEmpty);
    });

    test('an unreadable file throws noSource without its path in the log', () async {
      File(videoPath).deleteSync();
      Directory(videoPath).createSync();
      await expectLater(LocalSource.prepare(request), _throwsNoSource());
      final event = log.named('local file unusable').single;
      expect(event.f['file'], const LogString('v.m4s'));
      expect(event.f['reason'], isNot(const LogString('missing')));
      expect(event.encode(), isNot(contains(folder.path.split(Platform.pathSeparator).last)));
      expect(await _eventually(() => LocalSource.openFiles == 0), isTrue);
    });
  });

  group('reads', () {
    late MediaResource videoMedia;
    late MediaResource audioMedia;

    setUp(() async {
      final assets = LocalSource.assets(await LocalSource.prepare(request), request);
      videoMedia = assets.media['v.mp4']!;
      audioMedia = assets.media['a.mp4']!;
    });

    test('are byte-exact at the prefix boundary, in the middle and at the end', () async {
      final prefixEnd = videoMedia.prefix.length - 1;
      expect(prefixEnd, video.index.end);
      final ranges = [
        ByteRange(prefixEnd - 9, prefixEnd + 10),
        ByteRange(prefixEnd, prefixEnd),
        ByteRange(prefixEnd + 1, prefixEnd + 1),
        ByteRange(prefixEnd + 1, prefixEnd + _segmentBytes),
        ByteRange(300000, 1000000),
        ByteRange(video.bytes.length - 5, video.bytes.length - 1),
        ByteRange(0, video.bytes.length - 1),
      ];
      for (final range in ranges) {
        expect(
          await _collect(PlaybackRouter.body(videoMedia, range)),
          Uint8List.sublistView(video.bytes, range.start, range.end + 1),
          reason: '$range',
        );
      }
      final middle = ByteRange(audio.index.end + 1 + 2 * _segmentBytes, audio.index.end + 3 * _segmentBytes);
      expect(
        await _collect(PlaybackRouter.body(audioMedia, middle)),
        Uint8List.sublistView(audio.bytes, middle.start, middle.end + 1),
      );
      expect(LocalSource.openFiles, 0);
    });

    test('come a chunk at a time, never the whole range at once', () async {
      final range = ByteRange(videoMedia.prefix.length, video.bytes.length - 1);
      final chunks = await videoMedia.read(range).toList();
      expect(chunks.length, greaterThan(3));
      expect(chunks.every((chunk) => chunk.length <= LocalSource.readChunk), isTrue);
      expect(chunks.fold(0, (sum, chunk) => sum + chunk.length), range.length);
    });

    test('open nothing until listened to, and a cancelled read closes the file', () async {
      final range = ByteRange(videoMedia.prefix.length, video.bytes.length - 1);
      PlaybackRouter.body(videoMedia, range);
      expect(LocalSource.openFiles, 0);

      final first = Completer<void>();
      final reading = PlaybackRouter.body(videoMedia, range).listen((_) {
        if (!first.isCompleted) first.complete();
      });
      await first.future;
      expect(LocalSource.openFiles, 1);
      await reading.cancel();
      expect(LocalSource.openFiles, 0, reason: "the cancel's future waits for the close");

      late final StreamSubscription<List<int>> paused;
      paused = PlaybackRouter.body(videoMedia, range).listen((_) => paused.pause());
      expect(await _eventually(() => paused.isPaused), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(LocalSource.openFiles, 1);
      await paused.cancel();
      expect(LocalSource.openFiles, 0);
    });

    test('of a file cut short or gone since prepare fail, naming the file and not its folder', () async {
      File(videoPath).writeAsBytesSync(Uint8List.sublistView(video.bytes, 0, video.bytes.length - 100));
      final tail = ByteRange(video.bytes.length - 300, video.bytes.length - 1);
      await expectLater(
        _collect(PlaybackRouter.body(videoMedia, tail)),
        throwsA(const PlaybackBodyError.shorter(expected: 300, received: 200)),
      );

      File(audioPath).deleteSync();
      final range = ByteRange(audioMedia.prefix.length, audioMedia.prefix.length + 99);
      final folderName = folder.path.split(Platform.pathSeparator).last;
      await expectLater(
        _collect(PlaybackRouter.body(audioMedia, range)),
        throwsA(
          predicate<Object>((error) => '$error'.contains('a.m4s') && !'$error'.contains(folderName), 'names a.m4s only'),
        ),
      );
      expect(LocalSource.openFiles, 0);
    });
  });

  group('through the engine', () {
    late IsolatePlaybackEngine engine;

    setUp(() async {
      engine = await IsolatePlaybackEngine.start(transportFactory: _ioTransport);
    });

    tearDown(() => engine.dispose());

    test('prepareLocal serves the playlists and both files byte-exact from the local server', () async {
      final source = await engine.prepareLocal(request);
      expect(source.mode, PlaybackMode.local);
      expect(source.master.host, '127.0.0.1');
      expect(source.video.path, endsWith('/v.mp4'));
      expect(source.audio.path, endsWith('/a.mp4'));
      expect(source.rewroteHEV1, isFalse);
      expect(source.mediaHeaders, isEmpty);

      final master = await _get(source.master);
      expect(master.status, 200);
      expect(utf8.decode(master.body), allOf(contains('URI="a.m3u8"'), endsWith('\nv.m3u8\n')));
      final playlist = utf8.decode((await _get(source.master.resolve('v.m3u8'))).body);
      expect(playlist, allOf(contains('#EXT-X-MAP:URI="v.mp4"'), contains('#EXT-X-BYTERANGE:$_segmentBytes@')));

      final boundary = ByteRange(video.index.end - 99, video.index.end + 100);
      final across = await _get(source.video, range: boundary.headerValue);
      expect(across.status, 206);
      expect(across.body, Uint8List.sublistView(video.bytes, boundary.start, boundary.end + 1));
      final middle = ByteRange(500000, 900000);
      expect(
        (await _get(source.video, range: middle.headerValue)).body,
        Uint8List.sublistView(video.bytes, middle.start, middle.end + 1),
      );
      final whole = await _get(source.audio);
      expect(whole.status, 200);
      expect(whole.body, audio.bytes);

      await engine.release(source.token);
      expect((await _get(source.master)).status, 404);
    });

    test('prepareLocal of a missing file throws noSource across the isolate', () async {
      File(audioPath).deleteSync();
      await expectLater(engine.prepareLocal(request), _throwsNoSource());
    });
  });
}
