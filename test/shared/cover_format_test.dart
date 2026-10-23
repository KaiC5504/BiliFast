import 'package:bili_core/devlog.dart';
import 'package:bilifast/shared/cover_format.dart';
import 'package:bilifast/shared/cover_preset.dart';
import 'package:bilifast/shared/ios/picture_api.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// ImageIO's answer as the fake gives it: [width] × [height] opaque grey pixels.
DecodedPicture picture(int width, int height, {double decodeMs = 12.5, int? rowBytes, int? length}) => DecodedPicture(
  pixels: Uint8List.fromList(List.filled(length ?? (rowBytes ?? width * 4) * height, 0x80)),
  width: width,
  height: height,
  rowBytes: rowBytes ?? width * 4,
  decodeMs: decodeMs,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySink logs;
  late Logger logger;

  setUp(() {
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
  });

  List<Map<String, Object?>> lines(String msg) => [
    for (final event in logs.events)
      if (event.msg == msg) event.f.map((key, value) => MapEntry(key, value.toJson())),
  ];

  final avifData = Uint8List.fromList([1, 2, 3]);
  const cover = 'https://i0.hdslb.com/bfs/archive/a.jpg';
  const asked = 'https://i1.hdslb.com/bfs/archive/a.jpg';
  const feedAvif = '$asked@630w_473h_85q_!pegasus-ios-v2.avif';

  test('on the PC and in tests AVIF presets are asked at their exact size and the channel is never reached', () {
    final format = CoverFormat.platform();
    expect(format.avif, isFalse);
    expect(format.name, 'jpg');
    expect(format.address(cover, CoverPreset.feed), isNull);
    expect(
      format.address(cover, CoverPreset.space),
      '$asked@384w_216h_1e_1c_85q.webp',
      reason: 'webp needs no ImageIO',
    );
    expect(CoverFormat.shared.avif, isFalse);
  });

  test("with a decoder a cover asks for its preset; only Bilibili's image hosts, without @ or a query, take it", () {
    final format = CoverFormat(decode: (_, _, _) async => null, logger: logger);
    expect(format.name, 'avif');
    expect(format.address(cover, CoverPreset.feed), feedAvif);
    expect(format.address('//i2.hdslb.com/bfs/archive/a.jpg', CoverPreset.related), '$asked@360w_202h_1e_1c_85q.avif');
    expect(format.address(cover, CoverPreset.space), '$asked@384w_216h_1e_1c_85q.webp');
    expect(format.address(cover, CoverPreset.exact), isNull, reason: 'exact is its exact size, AVIF or not');
    for (final given in [
      'https://i0.hdslb.com/bfs/archive/d.jpg?sign=x',
      'https://i0.hdslb.com/bfs/archive/e.jpg@100w.webp',
      'https://example.com/f.jpg',
    ]) {
      expect(format.address(given, CoverPreset.feed), isNull, reason: '$given takes no preset: its exact size then');
    }
  });

  test('the format is logged once, the first time a cover is asked for', () {
    final format = CoverFormat(decode: (_, _, _) async => null, logger: logger);
    expect(lines('cover format'), isEmpty);
    format.address(cover, CoverPreset.feed);
    format.address('$cover.2', CoverPreset.history);
    expect(lines('cover format'), [
      {'format': 'avif'},
    ]);
    CoverFormat(logger: logger).address(cover, CoverPreset.feed);
    expect(lines('cover format').last, {'format': 'jpg'});
  });

  test('sameCover is one cover whichever suffix it is asked with', () {
    expect(CoverFormat.sameCover(feedAvif), asked);
    expect(CoverFormat.sameCover('$asked@633w_475h_1c_90q.jpg'), asked);
    expect(CoverFormat.sameCover(asked), asked);
    expect(CoverFormat.sameCover('$asked?sign=a@b'), '$asked?sign=a@b');
  });

  test("a decode hands the box to ImageIO and draws its pixels at the size it answered, with ImageIO's ms", () async {
    final boxes = <(int, int, int)>[];
    final format = CoverFormat(
      decode: (data, width, height) async {
        boxes.add((data.length, width, height));
        return picture(6, 4, decodeMs: 31.25);
      },
      logger: logger,
    );
    final decoded = await format.decodeAvif(feedAvif, avifData, 633, 475);
    expect(boxes, [(3, 633, 475)]);
    expect(decoded?.decodeMs, 31.25);
    final frame = await decoded!.codec.getNextFrame();
    expect((frame.image.width, frame.image.height), (6, 4));
    expect(decoded.codec.frameCount, 1);
    frame.image.dispose();
    expect(logs.events, isEmpty);
  });

  test(
    'null or a throw three times in a row turns AVIF off for the session; each failed cover is marked failed',
    () async {
      final answers = <Future<DecodedPicture?> Function()>[
        () async => null,
        () async => throw PlatformException(code: 'decode-error', message: 'secret detail'),
        () async => null,
      ];
      final format = CoverFormat(decode: (_, _, _) => answers.removeAt(0)(), logger: logger);
      for (var i = 0; i < 3; i++) {
        final address = format.address('$cover.$i', CoverPreset.feed)!;
        expect(address, endsWith('.$i@630w_473h_85q_!pegasus-ios-v2.avif'), reason: 'before AVIF went off');
        expect(await format.decodeAvif(address, avifData, 60, 60), isNull);
        expect(format.failed(address), isTrue, reason: 'its AVIF failed');
        if (i < 2) expect(format.address('$cover.$i', CoverPreset.feed), address, reason: 'its provider stays one');
      }
      expect(lines('avif decode failed'), [
        {'reason': 'null'},
        {'reason': 'platform decode-error'},
      ], reason: 'each reason once');
      expect(format.avif, isFalse);
      expect(format.name, 'jpg');
      expect(lines('avif off'), [
        {'failures': 3},
      ]);
      expect(format.address('$cover.new', CoverPreset.history), isNull);
      expect(format.address('$cover.new', CoverPreset.space), endsWith('.webp'), reason: 'webp needs no ImageIO');
      expect('${logs.events}', isNot(contains('secret detail')));
    },
  );

  test('pixels shorter than their size say, an empty size, or a failing channel are failures too', () async {
    final answers = <Future<DecodedPicture?> Function()>[
      () async => picture(4, 4, length: 20),
      () async => picture(4, 4, rowBytes: 8),
      () async => picture(0, 4),
      () async => throw StateError('codec'),
    ];
    final format = CoverFormat(decode: (_, _, _) => answers.removeAt(0)(), logger: logger);
    for (var i = 0; i < 4; i++) {
      expect(await format.decodeAvif('$cover.$i@.avif', avifData, 60, 60), isNull);
    }
    expect([for (final line in lines('avif decode failed')) line['reason']], ['short', 'empty', 'StateError']);
    expect(lines('avif off'), hasLength(1), reason: 'once, however many failures follow');
  });

  test('a success resets the count, so failures apart never turn AVIF off', () async {
    final answers = [null, null, picture(2, 2), null, null, picture(2, 2), null];
    final format = CoverFormat(decode: (_, _, _) async => answers.removeAt(0), logger: logger);
    for (var i = 0; i < 7; i++) {
      await format.decodeAvif(format.address('$cover.$i', CoverPreset.feed)!, avifData, 60, 60);
    }
    expect(format.avif, isTrue);
    expect(lines('avif off'), isEmpty);
    expect(format.failed(format.address('$cover.0', CoverPreset.feed)!), isTrue, reason: 'a failed cover stays failed');
    expect(format.failed(format.address('$cover.2', CoverPreset.feed)!), isFalse);
  });

  test('a status from the CDN marks that cover failed without counting against the decoder', () {
    final format = CoverFormat(decode: (_, _, _) async => null, logger: logger);
    for (var i = 0; i < 4; i++) {
      format.refused(format.address('$cover.$i', CoverPreset.feed)!, 404);
    }
    expect(format.avif, isTrue);
    expect(format.failed(format.address('$cover.1', CoverPreset.feed)!), isTrue);
    expect(
      format.failed(format.address('$cover.1', CoverPreset.related)!),
      isFalse,
      reason: 'another preset, another ask',
    );
    expect(lines('avif refused'), [
      {'status': 404},
    ]);
  });

  group('cover downloads', () {
    void download(CoverFormat format, CoverPreset preset, String kind, int i, {double? decodeMs}) => format.downloaded(
      preset,
      kind,
      (firstByteMs: 100 + i * 10, totalMs: 200 + i * 10, bytes: 1024 * (20 + i)),
      decodeMs: decodeMs,
    );

    test('every 10th download of a preset and format logs their medians and slowest', () {
      final format = CoverFormat(logger: logger);
      for (var i = 0; i < 9; i++) {
        download(format, CoverPreset.feed, 'avif', i, decodeMs: 4.0 + i);
        download(format, CoverPreset.feed, 'jpg', i);
      }
      expect(lines('cover downloads'), isEmpty);
      download(format, CoverPreset.feed, 'avif', 9, decodeMs: null);
      expect(lines('cover downloads'), [
        {
          'preset': 'feed',
          'format': 'avif',
          'n': 10,
          'firstByteMs': 145,
          'firstByteMaxMs': 190,
          'kb': 25,
          'decodeMsMax': 12,
        },
      ]);
      download(format, CoverPreset.feed, 'jpg', 9);
      expect(lines('cover downloads').last, {
        'preset': 'feed',
        'format': 'jpg',
        'n': 10,
        'firstByteMs': 145,
        'firstByteMaxMs': 190,
        'kb': 25,
      }, reason: 'no ImageIO for a JPEG');
    });

    test('each line is the 10 since the last, counted apart per preset', () {
      final format = CoverFormat(logger: logger);
      for (var i = 0; i < 20; i++) {
        download(format, CoverPreset.history, 'avif', i);
      }
      for (var i = 0; i < 10; i++) {
        download(format, CoverPreset.related, 'avif', 100);
      }
      expect(
        [for (final line in lines('cover downloads')) (line['preset'], line['n'], line['firstByteMs'])],
        [('history', 10, 145), ('history', 20, 245), ('related', 10, 1100)],
      );
      expect(lines('cover downloads').first.containsKey('decodeMsMax'), isFalse, reason: 'none decoded');
    });
  });
}
