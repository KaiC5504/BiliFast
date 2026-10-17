import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

import 'playback_fixtures.dart';

Future<PreparedPlayback> prepareFixture(HeaderFixture fixture) => PlaybackBuilder.prepare(fixture.choice,
    fetchHeaders: (_, _) async => (bytes: fixture.bytes, total: fixture.total));

Matcher throwsPlayback(PlaybackErrorKind kind, [String? detail]) => throwsA(isA<PlaybackError>()
    .having((error) => error.kind, 'kind', kind)
    .having((error) => error.detail, 'detail', detail));

bool contains4cc(Uint8List bytes, String code) => latin1.decode(bytes).contains(code);

void main() {
  late CapturedLog log;
  setUp(() => log = CapturedLog());
  tearDown(() => log.stop());

  group('ported from LocalServerTests', () {
    test('prepare parses the SIDX and keeps the init in memory', () async {
      final fixture = headerFixture(withMoov: true);
      final prepared = await prepareFixture(fixture);
      expect(prepared.video.segments, hasLength(1));
      expect(prepared.audio.segments, hasLength(1));
      expect(prepared.rewroteHEV1, isFalse);
      final playlists = PlaybackBuilder.directAssets(prepared).playlists;
      expect(playlists.keys.toSet(), {'master.m3u8', 'v.m3u8', 'a.m3u8'});
      final video = playlists['v.m3u8']!;
      expect(video,
          contains('#EXT-X-MAP:URI="https://primary.invalid/upgcxcode/80.m4s?deadline=1&upsig=sig",BYTERANGE="24@0"'));
      expect(video, contains('#EXT-X-BYTERANGE:1000@68'));
      // Swift's direct playlists named each other through the bilinative:// scheme; here they are relative.
      final master = playlists['master.m3u8']!;
      expect(master, endsWith('\nv.m3u8\n'));
      expect(master, contains('URI="a.m3u8"'));
    });

    test('prepare fetches both tracks at once', () async {
      final fixture = headerFixture(withMoov: true);
      final pending = <TrackKind, Completer<({Uint8List bytes, int total})>>{};
      final prepared = PlaybackBuilder.prepare(fixture.choice, fetchHeaders: (kind, _) {
        final completer = Completer<({Uint8List bytes, int total})>();
        pending[kind] = completer;
        return completer.future;
      });
      await Future<void>.delayed(Duration.zero);
      expect(pending.keys.toSet(), {TrackKind.video, TrackKind.audio}, reason: 'both requested before either answers');
      pending[TrackKind.audio]!.complete((bytes: fixture.bytes, total: fixture.total));
      pending[TrackKind.video]!.complete((bytes: fixture.bytes, total: fixture.total));
      expect((await prepared).audio.totalSize, fixture.total);
    });

    test('a hev1 label over hvc1 bytes is declared hvc1', () async {
      final fixture = headerFixture(withMoov: true, videoEntry: 'hvc1', videoCodecs: 'hev1.1.6.L120.90');
      final prepared = await prepareFixture(fixture);
      expect(prepared.rewroteHEV1, isFalse);
      expect(prepared.sourceEntry, 'hvc1');
      final master = PlaybackBuilder.directAssets(prepared).playlists['master.m3u8']!;
      expect(master, contains('CODECS="hvc1.1.6.L120.90,'));
    });

    test('real hev1 bytes are rewritten and declared hev1 in direct mode', () async {
      final fixture = headerFixture(withMoov: true, videoEntry: 'hev1', videoCodecs: 'hev1.1.6.L120.90');
      final prepared = await prepareFixture(fixture);
      expect(prepared.rewroteHEV1, isTrue);
      expect(prepared.sourceEntry, 'hev1');
      final master = PlaybackBuilder.directAssets(prepared).playlists['master.m3u8']!;
      expect(master, contains('CODECS="hev1.1.6.L120.90,'));
    });

    test('prepare rejects headers without a complete moov', () async {
      final fixture = headerFixture(withMoov: false);
      await expectLater(prepareFixture(fixture), throwsPlayback(PlaybackErrorKind.noSidx));
    });

    test('direct mode plays from the first address that answers', () async {
      final fixture = headerFixture(
          withMoov: true, backupHosts: ['whole.invalid', 'skewed.invalid', 'backup.invalid']);
      final transport = FixtureTransport(bytes: fixture.bytes, total: fixture.total, answers: {
        'primary.invalid': FixtureAnswer.refuse,
        'whole.invalid': FixtureAnswer.wholeFile,
        'skewed.invalid': FixtureAnswer.wrongRange,
      });
      final prepared = await PlaybackBuilder.prepareDirect(fixture.choice, transport: transport);
      expect(prepared.video.mediaUrl, startsWith('https://backup.invalid/'));
      expect(prepared.audio.mediaUrl, startsWith('https://backup.invalid/'));
      final playlists = PlaybackBuilder.directAssets(prepared).playlists;
      for (final name in ['v.m3u8', 'a.m3u8']) {
        final playlist = playlists[name]!;
        expect(playlist, contains('https://backup.invalid/'), reason: name);
        for (final refused in ['primary.invalid', 'whole.invalid', 'skewed.invalid']) {
          expect(playlist, isNot(contains(refused)), reason: '$name $refused');
        }
      }

      final open = FixtureTransport(bytes: fixture.bytes, total: fixture.total);
      final direct = await PlaybackBuilder.prepareDirect(fixture.choice, transport: open);
      expect(direct.video.mediaUrl, startsWith('https://primary.invalid/'));
    });

    test('direct mode fails typed when every address refuses', () async {
      final fixture = headerFixture(withMoov: true);
      final transport = FixtureTransport(bytes: fixture.bytes, total: fixture.total, answers: {
        'primary.invalid': FixtureAnswer.refuse,
        'backup.invalid': FixtureAnswer.refuse,
      });
      await expectLater(
          PlaybackBuilder.prepareDirect(fixture.choice, transport: transport), throwsPlayback(PlaybackErrorKind.noSource));
    });

    test('direct mode moves on from an address that hangs, both tracks at once', () async {
      final fixture = headerFixture(withMoov: true);
      final transport = FixtureTransport(
          bytes: fixture.bytes, total: fixture.total, answers: {'primary.invalid': FixtureAnswer.hang});
      final prepared = await PlaybackBuilder.prepareDirect(fixture.choice, transport: transport, candidateSeconds: 0.05);
      expect(prepared.video.mediaUrl, fixture.choice.video.backupURLs[0]);
      expect(prepared.audio.mediaUrl, fixture.choice.audio.backupURLs[0]);
      // Both primaries were waited out side by side, not one after the other.
      expect(transport.requests.take(2).map((request) => request.host), ['primary.invalid', 'primary.invalid']);
      expect(transport.cancelledRequests, ['primary.invalid', 'primary.invalid']);
    });
  });

  group('prepare (BTR)', () {
    test('the init segment is rewritten from hev1 to hvc1 for the video track only', () async {
      final fixture = headerFixture(withMoov: true, videoEntry: 'hev1', videoCodecs: 'hev1.1.6.L120.90');
      final prepared = await prepareFixture(fixture);
      expect(prepared.rewroteHEV1, isTrue);
      expect(contains4cc(prepared.video.headers, 'hvc1'), isTrue);
      expect(contains4cc(prepared.video.headers, 'hev1'), isFalse);
      expect(prepared.audio.headers, fixture.bytes, reason: 'audio headers are served as fetched');
      expect(fixture.bytes, isNot(prepared.video.headers), reason: 'the fetched bytes are not patched in place');
      expect(prepared.video.headers.length, fixture.bytes.length);
    });

    test('the SIDX gives each track its segments and the fetched total', () async {
      final fixture = headerFixture(withMoov: true);
      final prepared = await prepareFixture(fixture);
      final segment = prepared.video.segments.single;
      expect(segment.range, ByteRange(fixture.bytes.length, fixture.bytes.length + 999));
      expect(segment.duration, 2);
      expect(prepared.video.totalSize, fixture.total);
      expect(prepared.video.initRange, fixture.choice.video.initialization);
      expect(prepared.video.mediaUrl, fixture.choice.video.baseURL);
      expect(prepared.audio.mediaUrl, fixture.choice.audio.baseURL);
    });

    test('an unplayable hev1 throws codecUnplayable with the reason', () async {
      final fixture = headerFixture(withMoov: true, videoEntry: 'hev1', nalTypes: [32, 33]);
      await expectLater(prepareFixture(fixture),
          throwsPlayback(PlaybackErrorKind.codecUnplayable, 'hev1 without VPS/SPS/PPS in hvcC'));
    });

    test('an unplayable hev1 in the audio headers is not checked', () async {
      final fixture = headerFixture(withMoov: true);
      final broken = headerFixture(withMoov: true, videoEntry: 'hev1', nalTypes: [32]);
      final prepared = await PlaybackBuilder.prepare(fixture.choice.withAudioRanges(broken.choice),
          fetchHeaders: (kind, _) async => kind == TrackKind.video
              ? (bytes: fixture.bytes, total: fixture.total)
              : (bytes: broken.bytes, total: broken.total));
      expect(prepared.audio.headers, broken.bytes);
    });

    test('headers without a SIDX throw noSidx and say why', () async {
      final fixture = headerFixture(withMoov: true, withSidx: false);
      await expectLater(prepareFixture(fixture), throwsPlayback(PlaybackErrorKind.noSidx));
      final event = log.named('headers unusable').single;
      expect(event.level, LogLevel.warn);
      expect(event.f, {'track': const LogString('video'), 'reason': const LogString('sidx missing or not flat')});
    });

    test('a moov that runs past the init range throws noSidx', () async {
      final fixture = headerFixture(withMoov: true, videoEntry: 'hvc1');
      final video = fixture.choice.video;
      final cut = TrackChoice(
          video: video.withInitialization(ByteRange(0, video.initialization.end - 1)), audio: fixture.choice.audio);
      await expectLater(
          PlaybackBuilder.prepare(cut, fetchHeaders: (_, _) async => (bytes: fixture.bytes, total: fixture.total)),
          throwsPlayback(PlaybackErrorKind.noSidx));
      expect(log.named('headers unusable').single.f['reason'], const LogString('no complete moov in init range'));
    });

    test('an init range past the end of the headers throws noSidx', () async {
      final fixture = headerFixture(withMoov: true);
      final audio = fixture.choice.audio;
      final long = TrackChoice(
          video: fixture.choice.video, audio: audio.withInitialization(ByteRange(0, fixture.bytes.length)));
      await expectLater(
          PlaybackBuilder.prepare(long, fetchHeaders: (_, _) async => (bytes: fixture.bytes, total: fixture.total)),
          throwsPlayback(PlaybackErrorKind.noSidx));
      expect(log.named('headers unusable').single.f['track'], const LogString('audio'));
    });

    test('a failed video fetch wins at once; an audio failure counts once the video is in', () async {
      final fixture = headerFixture(withMoov: true);
      final audioPending = Completer<({Uint8List bytes, int total})>();
      await expectLater(
          PlaybackBuilder.prepare(fixture.choice,
              fetchHeaders: (kind, _) =>
                  kind == TrackKind.video ? Future.error(const RipperError.badResponse(403)) : audioPending.future),
          throwsA(const RipperError.badResponse(403)));
      audioPending.completeError(const RipperError(RipperErrorKind.stalled));

      final videoPending = Completer<({Uint8List bytes, int total})>();
      final both = PlaybackBuilder.prepare(fixture.choice,
          fetchHeaders: (kind, _) => kind == TrackKind.video
              ? videoPending.future
              : Future.error(const RipperError(RipperErrorKind.firstByteTimeout)));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      videoPending.completeError(const RipperError.badResponse(404));
      await expectLater(both, throwsA(const RipperError.badResponse(404)), reason: 'the video error still wins');

      await expectLater(
          PlaybackBuilder.prepare(fixture.choice,
              fetchHeaders: (kind, _) async => kind == TrackKind.video
                  ? (bytes: fixture.bytes, total: fixture.total)
                  : throw const RipperError(RipperErrorKind.firstByteTimeout)),
          throwsA(const RipperError(RipperErrorKind.firstByteTimeout)));
    });
  });

  group('prepareDirect', () {
    test('a 403 primary loses to the first backup that works, and the log says so', () async {
      final fixture = headerFixture(withMoov: true, backupHosts: ['dead.invalid', 'good.invalid', 'later.invalid']);
      final transport = FixtureTransport(bytes: fixture.bytes, total: fixture.total, answers: {
        'primary.invalid': FixtureAnswer.refuse,
        'dead.invalid': FixtureAnswer.refuse,
      });
      final prepared = await PlaybackBuilder.prepareDirect(fixture.choice, transport: transport);
      expect(prepared.video.mediaUrl, fixture.choice.video.backupURLs[1]);
      expect(prepared.audio.mediaUrl, fixture.choice.audio.backupURLs[1]);
      expect(transport.requests.map((request) => request.host), isNot(contains('later.invalid')));
      expect(transport.requests.map((request) => request.range).toSet(), {ByteRange(0, fixture.bytes.length - 1)});
      expect(transport.cancelledBodies, hasLength(4), reason: 'every refused body is dropped, not left open');

      final failures = log.named('direct headers failed');
      expect(failures, hasLength(4));
      expect(failures.first.level, LogLevel.warn);
      expect(failures.first.f['error'], const LogString('badResponse(403)'));
      expect(failures.first.f['url'], isA<LogString>());
      final sources = log.named('direct source');
      expect(sources, hasLength(2));
      expect(sources.first.level, LogLevel.info);
      expect(sources.first.f['refused'], const LogInt(2));
      expect(sources.first.f['candidates'], const LogInt(4));
    });

    test('a candidate without headers within candidateSeconds is cancelled and the next tried', () async {
      final fixture = headerFixture(withMoov: true);
      final transport = FixtureTransport(
          bytes: fixture.bytes, total: fixture.total, answers: {'primary.invalid': FixtureAnswer.hang});
      final prepared = await PlaybackBuilder.prepareDirect(fixture.choice, transport: transport, candidateSeconds: 0.05);
      expect(prepared.video.mediaUrl, startsWith('https://backup.invalid/'));
      expect(transport.cancelledRequests, ['primary.invalid', 'primary.invalid']);
      expect(log.named('direct headers failed').first.f['error'], const LogString('CandidateTimeout()'));
    });

    test('a candidate whose body stalls is cancelled through its subscription and the next tried', () async {
      final fixture = headerFixture(withMoov: true);
      final transport = FixtureTransport(
          bytes: fixture.bytes, total: fixture.total, answers: {'primary.invalid': FixtureAnswer.stallBody});
      final prepared = await PlaybackBuilder.prepareDirect(fixture.choice, transport: transport, candidateSeconds: 0.05);
      expect(prepared.audio.mediaUrl, startsWith('https://backup.invalid/'));
      expect(transport.cancelledBodies, ['primary.invalid', 'primary.invalid']);
    });

    test('every candidate failing throws noSource and logs an error', () async {
      final fixture = headerFixture(withMoov: true, backupHosts: ['a.invalid', 'b.invalid']);
      final transport = FixtureTransport(bytes: fixture.bytes, total: fixture.total, answers: {
        'primary.invalid': FixtureAnswer.hang,
        'a.invalid': FixtureAnswer.shortBody,
        'b.invalid': FixtureAnswer.noTotal,
      });
      await expectLater(PlaybackBuilder.prepareDirect(fixture.choice, transport: transport, candidateSeconds: 0.05),
          throwsPlayback(PlaybackErrorKind.noSource));
      final event = log.named('no direct source').first;
      expect(event.level, LogLevel.error);
      expect(event.f, {'refused': const LogInt(3), 'candidates': const LogInt(3)});
    });

    test('a 206 whose Content-Range is not the requested range is rejected', () async {
      final fixture = headerFixture(withMoov: true);
      final transport = FixtureTransport(
          bytes: fixture.bytes, total: fixture.total, answers: {'primary.invalid': FixtureAnswer.wrongRange});
      final prepared = await PlaybackBuilder.prepareDirect(fixture.choice, transport: transport);
      expect(prepared.video.mediaUrl, startsWith('https://backup.invalid/'));
      expect(log.named('direct headers failed').first.f['error'], const LogString('badResponse(206)'));
      expect(transport.cancelledBodies, ['primary.invalid', 'primary.invalid']);
    });

    test('a 206 without a total is rejected', () async {
      final fixture = headerFixture(withMoov: true);
      final transport = FixtureTransport(
          bytes: fixture.bytes, total: fixture.total, answers: {'primary.invalid': FixtureAnswer.noTotal});
      final prepared = await PlaybackBuilder.prepareDirect(fixture.choice, transport: transport);
      expect(prepared.video.mediaUrl, startsWith('https://backup.invalid/'));
    });

    test('a short or long body is rejected', () async {
      final fixture = headerFixture(withMoov: true, backupHosts: ['long.invalid', 'backup.invalid']);
      final transport = FixtureTransport(bytes: fixture.bytes, total: fixture.total, answers: {
        'primary.invalid': FixtureAnswer.shortBody,
        'long.invalid': FixtureAnswer.longBody,
      });
      final prepared = await PlaybackBuilder.prepareDirect(fixture.choice, transport: transport);
      expect(prepared.video.mediaUrl, startsWith('https://backup.invalid/'));
      final length = fixture.bytes.length;
      expect(log.named('direct headers failed').map((event) => event.f['error']).toSet(), {
        LogString('lengthMismatch(got ${length - 1}, expected $length)'),
        LogString('lengthMismatch(got ${length + 1}, expected $length)'),
      });
    });

    test('an address that is not a URL is skipped', () async {
      final fixture = headerFixture(withMoov: true);
      final video = fixture.choice.video;
      final choice = TrackChoice(video: video.withAddresses('http://[::1', video.backupURLs), audio: fixture.choice.audio);
      final prepared = await PlaybackBuilder.prepareDirect(choice,
          transport: FixtureTransport(bytes: fixture.bytes, total: fixture.total));
      expect(prepared.video.mediaUrl, video.backupURLs.first);
      expect(log.named('direct headers failed').single.f['error'], const LogString('invalidURL'));
    });

    test('the headers are fetched with the parsed SIDX and patched only in the served copy', () async {
      final fixture = headerFixture(withMoov: true, videoEntry: 'hev1', videoCodecs: 'hev1.1.6.L120.90');
      final prepared = await PlaybackBuilder.prepareDirect(fixture.choice,
          transport: FixtureTransport(bytes: fixture.bytes, total: fixture.total));
      expect(prepared.rewroteHEV1, isTrue);
      expect(prepared.sourceEntry, 'hev1');
      expect(prepared.video.totalSize, fixture.total);
      expect(prepared.video.segments.single.range.start, fixture.bytes.length);
    });

    test('cancelling stops the candidates and throws CancelledException', () async {
      final fixture = headerFixture(withMoov: true);
      final transport = FixtureTransport(
          bytes: fixture.bytes, total: fixture.total, answers: {'primary.invalid': FixtureAnswer.hang});
      final cancel = CancelToken();
      final prepared = PlaybackBuilder.prepareDirect(fixture.choice, transport: transport, cancel: cancel);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cancel.cancel();
      await expectLater(prepared, throwsA(isA<CancelledException>()));
      expect(transport.requests.map((request) => request.host), ['primary.invalid', 'primary.invalid']);
      expect(transport.cancelledRequests, ['primary.invalid', 'primary.invalid']);
      expect(log.named('direct headers failed'), isEmpty);
    });

    test('a video track without a source cancels the audio request', () async {
      final fixture = headerFixture(withMoov: true);
      final choice = TrackChoice(
          video: fixture.choice.video.withAddresses('https://refused.invalid/v.m4s', const []),
          audio: fixture.choice.audio);
      final transport = FixtureTransport(bytes: fixture.bytes, total: fixture.total, answers: {
        'refused.invalid': FixtureAnswer.refuse,
        'primary.invalid': FixtureAnswer.hang,
      });
      await expectLater(PlaybackBuilder.prepareDirect(choice, transport: transport, candidateSeconds: 30),
          throwsPlayback(PlaybackErrorKind.noSource));
      expect(transport.cancelledRequests, ['primary.invalid']);
    });
  });

  group('within', () {
    test('returns the value when the body is quick enough', () async {
      expect(await PlaybackBuilder.within(1, (_) async => 7), 7);
    });

    test('cancels the body and throws CandidateTimeout at the deadline', () async {
      CancelToken? seen;
      await expectLater(
          PlaybackBuilder.within(0.02, (token) {
            seen = token;
            return Completer<int>().future;
          }),
          throwsA(isA<CandidateTimeout>()));
      expect(seen!.isCancelled, isTrue);
    });

    test('a cancelled parent throws CancelledException, not a timeout', () async {
      final parent = CancelToken();
      final running = PlaybackBuilder.within(5, (_) => Completer<int>().future, cancel: parent);
      parent.cancel();
      await expectLater(running, throwsA(isA<CancelledException>()));
    });

    test('a body error passes through', () async {
      await expectLater(PlaybackBuilder.within(1, (_) => Future<int>.error(const RipperError.badResponse(500))),
          throwsA(const RipperError.badResponse(500)));
    });
  });

  group('assets', () {
    test('ripperAssets serves v.mp4 and a.mp4 from the patched prefix and reads through the engine', () async {
      final fixture = headerFixture(withMoov: true, videoEntry: 'hev1', videoCodecs: 'hev1.1.6.L120.90');
      final prepared = await prepareFixture(fixture);
      final reads = <(TrackKind, ByteRange)>[];
      final assets = PlaybackBuilder.ripperAssets(prepared, read: (kind, range) {
        reads.add((kind, range));
        return Stream.value([kind.index]);
      });
      expect(assets.media.keys.toSet(), {'v.mp4', 'a.mp4'});
      final video = assets.media['v.mp4']!;
      final audio = assets.media['a.mp4']!;
      expect(video.totalSize, fixture.total);
      expect(audio.totalSize, fixture.total);
      expect(video.prefix, prepared.video.headers);
      expect(contains4cc(video.prefix, 'hvc1'), isTrue);
      expect(audio.prefix, fixture.bytes);

      expect(await video.read(ByteRange(68, 1067)).toList(), [
        [TrackKind.video.index],
      ]);
      expect(await audio.read(ByteRange(100, 199)).toList(), [
        [TrackKind.audio.index],
      ]);
      expect(reads, [(TrackKind.video, ByteRange(68, 1067)), (TrackKind.audio, ByteRange(100, 199))]);

      final playlists = assets.playlists;
      expect(playlists.keys.toSet(), {'master.m3u8', 'v.m3u8', 'a.m3u8'});
      final initLength = fixture.choice.video.initialization.length;
      expect(playlists['v.m3u8'], contains('#EXT-X-MAP:URI="v.mp4",BYTERANGE="$initLength@0"'));
      expect(playlists['v.m3u8'], contains('#EXT-X-BYTERANGE:1000@${fixture.bytes.length}\nv.mp4\n'));
      expect(playlists['a.m3u8'], contains('\na.mp4\n'));
      expect(playlists['a.m3u8'], isNot(contains('v.mp4')));
      // The served bytes say hvc1 after the rewrite, so the label follows them.
      expect(playlists['master.m3u8'], contains('CODECS="hvc1.1.6.L120.90,mp4a.40.2"'));
      expect(playlists['master.m3u8'], contains('URI="a.m3u8"'));
      expect(playlists['master.m3u8'], endsWith('\nv.m3u8\n'));
    });

    test('directAssets points the media URIs at the addresses that answered and serves no media', () async {
      final fixture = headerFixture(withMoov: true, backupHosts: ['backup.invalid']);
      final transport = FixtureTransport(
          bytes: fixture.bytes, total: fixture.total, answers: {'primary.invalid': FixtureAnswer.refuse});
      final prepared = await PlaybackBuilder.prepareDirect(fixture.choice, transport: transport);
      final assets = PlaybackBuilder.directAssets(prepared);
      expect(assets.media, isEmpty);
      final video = fixture.choice.video.backupURLs.single;
      final audio = fixture.choice.audio.backupURLs.single;
      expect(assets.playlists['v.m3u8'], contains('#EXT-X-MAP:URI="$video",BYTERANGE="24@0"'));
      expect(assets.playlists['v.m3u8'], contains('#EXT-X-BYTERANGE:1000@68\n$video\n'));
      expect(assets.playlists['a.m3u8'], contains('#EXT-X-BYTERANGE:1000@68\n$audio\n'));
      expect(assets.playlists['master.m3u8'], contains('URI="a.m3u8"'));
      expect(assets.playlists['master.m3u8'], endsWith('\nv.m3u8\n'));
    });

    test('the master playlist declares the variant through CodecMapper', () async {
      final dolby = headerFixture(withMoov: true, videoCodecs: 'dvh1.08.07', videoId: 126, frameRate: '29.412');
      final master = PlaybackBuilder.directAssets(await prepareFixture(dolby)).playlists['master.m3u8']!;
      expect(master, '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="default",DEFAULT=YES,AUTOSELECT=YES,URI="a.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=3000000,AVERAGE-BANDWIDTH=2000000,CODECS="hvc1.2.4.L153.b0,mp4a.40.2",SUPPLEMENTAL-CODECS="dvh1.08.07/db4h",RESOLUTION=1920x1080,FRAME-RATE=29.412,VIDEO-RANGE=HLG,AUDIO="audio"
v.m3u8
''');

      final hdr = headerFixture(
          withMoov: true, videoCodecs: 'hev1.2.4.L153.90', videoId: 125, audioCodecs: '', frameRate: null);
      final hdrMaster = PlaybackBuilder.ripperAssets(await prepareFixture(hdr), read: (_, _) => const Stream.empty())
          .playlists['master.m3u8']!;
      expect(hdrMaster, contains('CODECS="hev1.2.4.L153.90,mp4a.40.2"'), reason: 'an empty audio codec falls back to AAC');
      expect(hdrMaster, contains('FRAME-RATE=30.000,VIDEO-RANGE=PQ,'));
      expect(hdrMaster, isNot(contains('SUPPLEMENTAL-CODECS')));
    });
  });
}

extension on DashStream {
  DashStream withInitialization(ByteRange initialization) => copy(initialization: initialization);

  DashStream withAddresses(String baseURL, List<String> backupURLs) => copy(baseURL: baseURL, backupURLs: backupURLs);

  DashStream copy({String? baseURL, List<String>? backupURLs, ByteRange? initialization, ByteRange? indexRange}) =>
      DashStream(
        id: id,
        baseURL: baseURL ?? this.baseURL,
        backupURLs: backupURLs ?? this.backupURLs,
        bandwidth: bandwidth,
        mimeType: mimeType,
        codecs: codecs,
        codecid: codecid,
        width: width,
        height: height,
        frameRate: frameRate,
        initialization: initialization ?? this.initialization,
        indexRange: indexRange ?? this.indexRange,
      );
}

extension on TrackChoice {
  /// The audio stream's init and index ranges taken from [other]'s audio.
  TrackChoice withAudioRanges(TrackChoice other) => TrackChoice(
      video: video,
      audio: audio.copy(initialization: other.audio.initialization, indexRange: other.audio.indexRange));
}
