import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/dash_hls.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

import '../../bin/ripper_bench.dart';
import '../api/fixtures.dart';
import '../dash_hls/mp4_builder.dart';
import '../engine/support/loopback_server.dart';

/// Written by a temporary test directory; deleted with it.
Future<String> _saved(String json) async {
  final directory = await Directory.systemTemp.createTemp('ripper_bench_test');
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}${Platform.pathSeparator}playurl.json');
  await file.writeAsString(json);
  return file.path;
}

typedef _FakeMedia = ({Uint8List bytes, int initEnd, int indexEnd, List<MediaSegment> segments});

/// ftyp, an empty moov and a version 0 sidx of [count] 2-second references, then the pattern up to [total] bytes.
_FakeMedia _fakeMedia({required int total, required int count}) {
  final ftyp = MP4Builder.box('ftyp', [...ascii.encode('isom'), ...MP4Builder.be32(0)]);
  final moov = MP4Builder.box('moov', []);
  final sidxLength = MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: []).length;
  final header = ftyp.length + moov.length + sidxLength + 12 * count;
  final payload = total - header;
  final sizes = [
    for (var index = 0; index < count; index++) payload ~/ count + (index == count - 1 ? payload % count : 0),
  ];
  final sidx = MP4Builder.sidx(
    version: 0,
    timescale: 1000,
    earliest: 0,
    firstOffset: 0,
    refs: [for (final size in sizes) (size, 2000)],
  );
  final bytes = Uint8List(total)..setAll(0, [...ftyp, ...moov, ...sidx]);
  bytes.setAll(header, LoopbackServer.pattern(header, total - 1));
  return (
    bytes: bytes,
    initEnd: ftyp.length + moov.length - 1,
    indexEnd: header - 1,
    segments: SidxParser.parse(Uint8List.sublistView(bytes, 0, header), absoluteStart: 0)!,
  );
}

String _loopbackPlayURL(_FakeMedia media, List<int> ports) {
  String url(int port, int id) =>
      'http://127.0.0.1:$port/upgcxcode/00/00/1/1-1-$id.m4s?deadline=1760000000&os=loop&upsig=0123456789abcdef';
  Map<String, Object> stream(int id, String codecs, int codecid, int bandwidth) => {
    'id': id,
    'baseUrl': url(ports.first, id),
    'backupUrl': [for (final port in ports.skip(1)) url(port, id)],
    'bandwidth': bandwidth,
    'mimeType': id < 30000 ? 'video/mp4' : 'audio/mp4',
    'codecs': codecs,
    'width': id < 30000 ? 1920 : 0,
    'height': id < 30000 ? 1080 : 0,
    'frameRate': id < 30000 ? '30' : '',
    'SegmentBase': {'Initialization': '0-${media.initEnd}', 'indexRange': '${media.initEnd + 1}-${media.indexEnd}'},
    'codecid': codecid,
  };
  return jsonEncode({
    'code': 0,
    'message': '0',
    'ttl': 1,
    'data': {
      'quality': 80,
      'accept_quality': [80],
      'accept_description': ['高清 1080P'],
      'dash': {
        'duration': 2 * media.segments.length,
        'video': [stream(80, 'hev1.1.6.L120.90', 12, 2000000)],
        'audio': [stream(30280, 'mp4a.40.2', 0, 320000)],
      },
    },
  });
}

void main() {
  group('arguments', () {
    test('only --playurl is required; the rest default as in Swift', () {
      final options = BenchOptions.parse(['--playurl', 'saved.json']);
      expect(options.playurl, 'saved.json');
      expect(options.megabytes, 16);
      expect(options.mode, NodeMode.overseas);
      expect(options.quality, 80);
      expect(options.codec, VideoCodec.hevc);
      expect(options.seeks, 0);
      expect(options.hurry, isTrue);
      expect(options.repeat, 1);
    });

    test('every flag', () {
      final options = BenchOptions.parse([
        '--mb', '24', '--mode', 'mainland', '--quality', '120', '--codec', 'av1', //
        '--seeks', '8', '--no-hurry', '--repeat', '3', '--playurl', 'saved.json',
      ]);
      expect(options.playurl, 'saved.json');
      expect(options.megabytes, 24);
      expect(options.mode, NodeMode.mainland);
      expect(options.quality, 120);
      expect(options.codec, VideoCodec.av1);
      expect(options.seeks, 8);
      expect(options.hurry, isFalse);
      expect(options.repeat, 3);
    });

    test('unreadable values fall back the way Swift parses them', () {
      final options = BenchOptions.parse([
        '--playurl',
        'p',
        '--mb',
        'lots',
        '--quality',
        'best',
        '--codec',
        'vp9',
        '--mode',
        'moon',
      ]);
      expect(options.megabytes, 16);
      expect(options.quality, 80);
      expect(options.codec, VideoCodec.hevc);
      expect(options.mode, NodeMode.overseas);
      expect(BenchOptions.parse(['--playurl', 'p', '--codec', 'avc']).codec, VideoCodec.avc);
    });

    test('usage errors', () {
      for (final arguments in [
        <String>[],
        ['--playurl'],
        ['--mb', '24'],
        ['--playurl', 'p', '--seeks', '0'],
        ['--playurl', 'p', '--seeks', 'many'],
        ['--playurl', 'p', '--repeat', '0'],
        ['--playurl', 'p', '--mb', '0'],
        ['--playurl', 'p', '--frobnicate', '1'],
        ['--playurl', 'p', '--seeks'],
      ]) {
        expect(() => BenchOptions.parse(arguments), throwsA(isA<UsageError>()), reason: '$arguments');
      }
    });

    test('--bv and --cookies are refused: the bench never calls the API', () {
      for (final flag in ['--bv', '--cookies']) {
        expect(
          () => BenchOptions.parse(['--playurl', 'p', flag, 'x']),
          throwsA(isA<UsageError>().having((error) => '$error', 'message', contains('never calls'))),
        );
      }
    });

    test('a usage error prints as Swift prints it', () {
      expect(errorLine(const UsageError()), startsWith('error: usage: ripper_bench --playurl file.json [--mb 16]'));
    });
  });

  group('seeded offsets', () {
    // Printed by Bench.swift's SeededGenerator and Int64.random(in:using:), compiled with Swift 6.4.1.
    test('the generator matches Swift for seed 17', () {
      final generator = SeededGenerator(17);
      expect(
        [for (var index = 0; index < 4; index++) BigInt.from(generator.next()).toUnsigned(64).toString()],
        ['9260656408219841379', '7220676901988789713', '6056616057409641356', '4130155771025092611'],
      );
    });

    test('ranged draws match Swift, rejections included', () {
      final small = SeededGenerator(17);
      expect(
        [for (var index = 0; index < 16; index++) small.nextInRange(0, 2)],
        [1, 1, 0, 0, 0, 0, 0, 1, 0, 2, 0, 0, 1, 1, 2, 0],
      );
      final wide = SeededGenerator(99);
      expect(
        [for (var index = 0; index < 6; index++) wide.nextInRange(0, 0x7FFFFFFFFFFFFFFC)],
        [
          2412192838258505200,
          291991308351747281,
          7699299500860434810,
          943729858380535403,
          1568516910111292537,
          2164399061527425848,
        ],
      );
    });

    test('the cold-seek offsets match Swift for the same file size', () {
      List<int> offsets(int total, int count) {
        final segments = [MediaSegment(index: 0, range: ByteRange(0, total - 1), startTime: 0, duration: 1)];
        return [
          for (final seek in coldSeekPlan(segments, total: total, count: count, generator: SeededGenerator(17)))
            seek.offset,
        ];
      }

      expect(offsets(6 << 20, 8), [2262280, 1833230, 1588404, 1183229, 381532, 630674, 436266, 2850092]);
      expect(offsets(3000000, 8), [527946, 444690, 397182, 318560, 162993, 211338, 173614, 642009]);
      expect(offsets(1234567890, 12), [
        649465859, 519996377, 446118010, 323853148, 81934265, 157115007, //
        98450774, 826843321, 91385351, 891713229, 360440687, 155356980,
      ]);
    });

    test('each read starts at its segment and runs 4 MiB or to the end of the file', () {
      const total = 1234567890;
      const segmentBytes = 1 << 20;
      final segments = [
        for (var index = 0; index * segmentBytes < total; index++)
          MediaSegment(
            index: index,
            range: ByteRange(index * segmentBytes, min((index + 1) * segmentBytes, total) - 1),
            startTime: index * 2.0,
            duration: 2,
          ),
      ];
      final plan = coldSeekPlan(segments, total: total, count: 3, generator: SeededGenerator(17));
      expect(plan.first.segment.index, 649465859 ~/ segmentBytes);
      expect(plan.first.range, ByteRange(619 * segmentBytes, 623 * segmentBytes - 1));
      final small = _fakeMedia(total: 6 << 20, count: 24);
      final seeks = coldSeekPlan(small.segments, total: 6 << 20, count: 2, generator: SeededGenerator(17));
      expect(seeks[0].range.start, greaterThan(2 << 20));
      expect(seeks[0].range.end, (6 << 20) - 1, reason: 'starts past 2 MiB, so 4 MiB would run off the end');
      expect(seeks[1].range.start, small.segments[6].range.start);
      expect(seeks[1].range.end, seeks[1].range.start + seekBytes - 1);
    });

    test('a file too small for cold seeks is refused as Swift refuses it', () {
      expect(() => coldSeekSpan(2 << 20), throwsA(const BiliError.decoding('video too small for cold seeks')));
    });

    test('median', () {
      expect(median([]), isNull);
      expect(median([3]), 3);
      expect(median([5, 1, 3]), 3);
      expect(median([4, 1, 3, 2]), 2.5);
    });
  });

  group('saved playurl', () {
    test('picks the video track the way Swift does and describes it without the signed URL', () async {
      final info = await Bench.loadPlayURL(await _saved(Fixtures.playURL));
      final hevc = Bench.chooseVideo(info, quality: 120, codec: VideoCodec.hevc);
      expect(
        Bench.describe(hevc),
        'video 120 hev1.1.6.L153.90 3840x2160 12000 kbps on upos-sz-mirrorcos.bilivideo.com',
      );
      expect(hevc.indexRange, ByteRange(1105, 1688));
      expect(Bench.chooseVideo(info, quality: 120, codec: VideoCodec.avc).codecs, 'avc1.640034');
      // 1080P only comes in AV1: the codec order falls through to it.
      expect(Bench.chooseVideo(info, quality: 80, codec: VideoCodec.hevc).codecid, VideoCodec.av1.codecid);
    });

    test('an error reply or a playurl without DASH fails as in Swift', () async {
      await expectLater(
        Bench.loadPlayURL(await _saved(Fixtures.notFound)),
        throwsA(const BiliError.api(code: -404, message: '啥都木有')),
      );
      final durl = await Bench.loadPlayURL(await _saved(Fixtures.durlOnly));
      expect(() => Bench.chooseVideo(durl, quality: 80, codec: VideoCodec.hevc), throwsA(BiliError.notDash));
    });

    test('errors are redacted before they are printed', () {
      final error = HttpException(
        'Connection closed before full header was received',
        uri: Uri.parse('https://upos-sz-mirrorcos.bilivideo.com/x/1-1-100112.m4s?deadline=1760000000&upsig=abcdef0123'),
      );
      final line = errorLine(error);
      expect(line, startsWith('error: '));
      expect(line, contains('upos-sz-mirrorcos.bilivideo.com'));
      expect(line, isNot(contains('upsig')));
      expect(line, isNot(contains('abcdef0123')));
      expect(line, isNot(contains('100112')));
      expect(
        errorLine(Exception('cut at https://upos-hz-mirrorakam.akamaized.net/upgcxcode/12/34/5-1-30120.m4s?deadli')),
        'error: Exception: cut at upos-hz-mirrorakam.akamaized.net',
      );
    });
  });

  group('loopback run', () {
    late _FakeMedia media;
    late LoopbackServer primary;
    late LoopbackServer backup;
    late String playurl;
    late NodeMode loopback;

    setUp(() async {
      media = _fakeMedia(total: 6 << 20, count: 24);
      primary = await LoopbackServer.start({'/upgcxcode/00/00/1/1-1-80.m4s': Media(media.bytes)});
      backup = await LoopbackServer.start({'/upgcxcode/00/00/1/1-1-80.m4s': Media(media.bytes)});
      playurl = await _saved(_loopbackPlayURL(media, [primary.port, backup.port]));
      loopback = CustomNodes([
        NodeAddress('127.0.0.1', port: primary.port),
        NodeAddress('127.0.0.1', port: backup.port),
      ]);
    });

    tearDown(() async {
      await primary.stop();
      await backup.stop();
    });

    final seconds = r'\d+\.\d\d';
    final nodeLine = RegExp(
      r'^  127\.0\.0\.1:\d+: \d+ req, \d+ failed, first byte \d+ ms, '
      r'(\d+\.\d\d MB/s|-) per connection, (healthy|untested|blocked|banned)( \(addresses: .+\))?$',
    );

    void expectRedacted(List<String> lines) {
      for (final line in lines) {
        for (final secret in ['http', '?', 'deadline', 'upsig', '0123456789abcdef', 'upgcxcode']) {
          expect(line, isNot(contains(secret)), reason: line);
        }
      }
    }

    test('one connection against Ripper, twice, with the medians', () async {
      final lines = <String>[];
      await Bench(
        BenchOptions(playurl: playurl, megabytes: 2, mode: loopback, repeat: 2),
        say: lines.add,
        policy: MediaURLPolicy.any,
      ).run();
      expectRedacted(lines);
      expect(lines.first, 'video 80 hev1.1.6.L120.90 1920x1080 2000 kbps on 127.0.0.1:${primary.port}');
      var wanted = 0;
      for (final segment in media.segments) {
        if (wanted >= 2 << 20) break;
        wanted += segment.range.length;
      }
      final runs = [
        for (var index = 0; index < lines.length; index++)
          if (lines[index].startsWith('run ')) index,
      ];
      expect([for (final index in runs) lines[index]], ['run 1 of 2', 'run 2 of 2']);
      for (final start in runs) {
        expect(
          lines[start + 1],
          matches(
            '^one connection: 2097152 bytes in $seconds s = $seconds MB/s \\(HTTP 206, primary on 127\\.0\\.0\\.1:${primary.port}\\)\$',
          ),
        );
        expect(lines[start + 2], matches('^ripper:         $wanted bytes in $seconds s = $seconds MB/s\$'));
        expect(lines[start + 3], matches(r'^connections \d+, requests \d+, failures 0, duplicate \d+\.\d%$'));
        final nodes = lines.skip(start + 4).takeWhile((line) => line.startsWith('  ')).toList();
        expect(nodes, isNotEmpty);
        for (final line in nodes) {
          expect(line, matches(nodeLine));
        }
      }
      expect(
        lines[lines.length - 2],
        matches('^median one connection over 2 of 2 runs: $seconds MB/s \\(truncated or refused runs left out\\)\$'),
      );
      expect(lines.last, matches('^median ripper over 2 runs: $seconds MB/s\$'));
      expect(primary.requests('/upgcxcode/00/00/1/1-1-80.m4s'), greaterThan(4));
    });

    test('cold seeks at Swift\'s offsets, without hurry', () async {
      final lines = <String>[];
      await Bench(
        BenchOptions(playurl: playurl, mode: loopback, seeks: 3, hurry: false),
        say: lines.add,
        policy: MediaURLPolicy.any,
      ).run();
      expectRedacted(lines);
      final plan = coldSeekPlan(media.segments, total: 6 << 20, count: 3, generator: SeededGenerator(17));
      expect([for (final seek in plan) seek.offset], [2262280, 1833230, 1588404]);
      expect(lines.take(2), [
        'video 80 hev1.1.6.L120.90 1920x1080 2000 kbps on 127.0.0.1:${primary.port}',
        // Swift's line has no unit after the total either.
        'cold seeks: 3 x 4.0 MiB, seed 17, hurry off, offsets 0.3-4.0 MiB of 6.0',
      ]);
      for (final (index, seek) in plan.indexed) {
        expect(
          lines[2 + index],
          matches(
            '^seek ${index + 1}/3 at ${RegExp.escape(mib(seek.range.start))} MiB: first MiB $seconds s, '
            '${RegExp.escape(mib(seek.range.length))} MiB $seconds s '
            r'\(connections \d+, requests \d+, failures 0, duplicate \d+\.\d%\)$',
          ),
        );
      }
      expect(lines.skip(5), [
        matches('^median first MiB: $seconds s over 3 of 3 seeks\$'),
        matches('^median 4.0 MiB: $seconds s over 3 of 3 seeks\$'),
      ]);
    });

    test('repeated seek runs continue the seeded sequence and end with the median of their medians', () async {
      final lines = <String>[];
      await Bench(
        BenchOptions(playurl: playurl, mode: loopback, seeks: 2, repeat: 2),
        say: lines.add,
        policy: MediaURLPolicy.any,
      ).run();
      final plan = coldSeekPlan(media.segments, total: 6 << 20, count: 4, generator: SeededGenerator(17));
      final labels = [
        for (final line in lines)
          if (line.startsWith('seek ')) line.substring(0, line.indexOf(':')),
      ];
      expect(labels, [
        for (final (index, seek) in plan.indexed) 'seek ${index % 2 + 1}/2 at ${mib(seek.range.start)} MiB',
      ]);
      expect(lines.where((line) => line.startsWith('run ')), ['run 1 of 2', 'run 2 of 2']);
      expect(lines.skip(lines.length - 2), [
        matches('^median first MiB over 2 of 2 runs: $seconds s \\(median of the runs\' medians\\)\$'),
        matches('^median 4.0 MiB over 2 of 2 runs: $seconds s\$'),
      ]);
    });

    test('a refused primary falls back to the backup for the single connection', () async {
      await primary.stop();
      final lines = <String>[];
      await Bench(
        BenchOptions(playurl: playurl, megabytes: 1, mode: loopback),
        say: lines.add,
        policy: MediaURLPolicy.any,
      ).run();
      expectRedacted(lines);
      expect(lines[1], startsWith('baseline probe: primary on 127.0.0.1:${primary.port} failed: SocketException'));
      expect(lines[2], contains('(HTTP 206, backup 1 on 127.0.0.1:${backup.port})'));
    });
  });
}
