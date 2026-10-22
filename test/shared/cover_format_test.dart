import 'package:bili_core/devlog.dart';
import 'package:bilifast/shared/cover_format.dart';
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

  test('on the PC and in tests covers are webp and the channel is never reached', () {
    final format = CoverFormat.platform();
    expect(format.avif, isFalse);
    expect(format.name, 'webp');
    expect(format.address(cover), '$cover@.webp');
    expect(CoverFormat.shared.avif, isFalse);
  });

  test("with a decoder a cover asks for AVIF; only Bilibili's image hosts, without @ or a query, take the format", () {
    final format = CoverFormat(decode: (_, _, _) async => null, logger: logger);
    expect(format.name, 'avif');
    for (final (given, asked) in [
      (cover, '$cover@.avif'),
      ('http://i1.hdslb.com/bfs/archive/b.jpg', 'https://i0.hdslb.com/bfs/archive/b.jpg@.avif'),
      ('//i2.hdslb.com/bfs/archive/c.png', 'https://i0.hdslb.com/bfs/archive/c.png@.avif'),
      ('https://i0.hdslb.com/bfs/archive/d.jpg?sign=x', 'https://i0.hdslb.com/bfs/archive/d.jpg?sign=x'),
      ('https://i0.hdslb.com/bfs/archive/e.jpg@100w.webp', 'https://i0.hdslb.com/bfs/archive/e.jpg@100w.webp'),
      ('https://example.com/f.jpg', 'https://example.com/f.jpg'),
    ]) {
      expect(format.address(given), asked, reason: given);
    }
  });

  test('the format is logged once, the first time a cover is asked for', () {
    final format = CoverFormat(decode: (_, _, _) async => null, logger: logger);
    expect(lines('cover format'), isEmpty);
    format.address(cover);
    format.address('$cover.2');
    expect(lines('cover format'), [
      {'format': 'avif'},
    ]);
    CoverFormat(logger: logger).address(cover);
    expect(lines('cover format').last, {'format': 'webp'});
  });

  test('webpOf and sameCover', () {
    expect(CoverFormat.webpOf('$cover@.avif'), '$cover@.webp');
    expect(CoverFormat.webpOf('$cover@.webp'), '$cover@.webp');
    expect(CoverFormat.sameCover('$cover@.avif'), cover);
    expect(CoverFormat.sameCover('$cover@.webp'), cover);
    expect(CoverFormat.sameCover('$cover@240w_180h_1c.webp'), '$cover@240w_180h_1c.webp');
  });

  test("a decode hands the box to ImageIO and draws its pixels at the size it answered, with ImageIO's ms", () async {
    final asked = <(int, int, int)>[];
    final format = CoverFormat(
      decode: (data, width, height) async {
        asked.add((data.length, width, height));
        return picture(6, 4, decodeMs: 31.25);
      },
      logger: logger,
    );
    final decoded = await format.decodeAvif('$cover@.avif', avifData, 660, 480);
    expect(asked, [(3, 660, 480)]);
    expect(decoded?.decodeMs, 31.25);
    final frame = await decoded!.codec.getNextFrame();
    expect((frame.image.width, frame.image.height), (6, 4));
    expect(decoded.codec.frameCount, 1);
    frame.image.dispose();
    expect(logs.events, isEmpty);
  });

  test(
    'null or a throw three times in a row turns AVIF off for the session; each failed cover then asks for webp',
    () async {
      final answers = <Future<DecodedPicture?> Function()>[
        () async => null,
        () async => throw PlatformException(code: 'decode-error', message: 'secret detail'),
        () async => null,
      ];
      final format = CoverFormat(decode: (_, _, _) => answers.removeAt(0)(), logger: logger);
      for (var i = 0; i < 3; i++) {
        final address = format.address('$cover.$i');
        expect(address, '$cover.$i@.avif', reason: 'before AVIF went off');
        expect(await format.decodeAvif(address, avifData, 60, 60), isNull);
        expect(format.address('$cover.$i'), '$cover.$i@.webp', reason: 'its AVIF failed');
      }
      expect(lines('avif decode failed'), [
        {'reason': 'null'},
        {'reason': 'platform decode-error'},
      ], reason: 'each reason once');
      expect(format.avif, isFalse);
      expect(format.name, 'webp');
      expect(lines('avif off'), [
        {'failures': 3},
      ]);
      expect(format.address('$cover.new'), '$cover.new@.webp');
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
      await format.decodeAvif('$cover.$i@.avif', avifData, 60, 60);
    }
    expect(format.avif, isTrue);
    expect(lines('avif off'), isEmpty);
    expect(format.address('$cover.0'), '$cover.0@.webp', reason: 'a failed cover stays on webp');
    expect(format.address('$cover.2'), '$cover.2@.avif');
  });

  test('a status from the CDN moves that cover to webp without counting against the decoder', () {
    final format = CoverFormat(decode: (_, _, _) async => null, logger: logger);
    for (var i = 0; i < 4; i++) {
      format.refused('$cover.$i@.avif', 400);
    }
    expect(format.avif, isTrue);
    expect(format.address('$cover.1'), '$cover.1@.webp');
    expect(lines('avif refused'), [
      {'status': 400},
    ]);
  });
}
