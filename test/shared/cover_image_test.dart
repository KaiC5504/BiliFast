import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/devlog.dart';
import 'package:bilifast/shared/cover_format.dart';
import 'package:bilifast/shared/cover_preset.dart';
import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:bilifast/shared/ios/picture_api.g.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stored_pictures.dart';

/// A plain [width] × [height] PNG, standing in for the CDN's JPEG.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = const Color(0xFF808080));
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

const _cover = 'https://i0.hdslb.com/bfs/archive/cover.jpg';

/// [_cover] as the CDN is asked for it at [width] × [height] px: from i1, a quality 90 JPEG.
String _at(int width, int height) => 'https://i1.hdslb.com/bfs/archive/cover.jpg@${width}w_${height}h_1c_90q.jpg';

/// [_cover] as asked by 推荐's preset.
const _feedAvif = 'https://i1.hdslb.com/bfs/archive/cover.jpg@630w_473h_85q_!pegasus-ios-v2.avif';

/// A 推荐 card's cover box.
const _cardCover = SizedBox(
  width: 211,
  height: 158.25,
  child: RemoteImage(_cover, size: Size(211, 158.25), cover: true),
);

/// A 推荐 card's cover box, naming its preset.
const _feedCover = SizedBox(
  width: 211,
  height: 158.25,
  child: RemoteImage(_cover, size: Size(211, 158.25), cover: true, preset: CoverPreset.feed),
);

final _avifBytes = Uint8List.fromList([0, 0, 0, 0x1C, ...'ftypavif'.codeUnits]);

/// ImageIO's answer as the fake gives it: [width] × [height] grey pixels.
DecodedPicture _pixels(int width, int height, {double decodeMs = 20}) => DecodedPicture(
  pixels: Uint8List.fromList(List.filled(width * height * 4, 0x80)),
  width: width,
  height: height,
  rowBytes: width * 4,
  decodeMs: decodeMs,
);

void main() {
  late Directory folder;
  late ImageDiskCache cache;
  late List<String> downloads;
  late Map<String, Object> answers;
  late Uint8List wide;
  late MemorySink logs;

  /// The decoder's asks, as (bytes, box width, box height).
  late List<(int, int, int)> decodes;

  setUp(() {
    downloads = [];
    answers = {};
    decodes = [];
    logs = MemorySink();
    Logger.shared.add(logs);
  });

  tearDown(() {
    Logger.shared.remove(logs);
    // `image failed` names the host and path on purpose; every other line names none.
    for (final event in logs.events.where((event) => event.msg != 'image failed')) {
      final line = [event.msg, for (final value in event.f.values) '${value.toJson()}'].join(' ');
      for (final part in ['hdslb', 'http', '/bfs/', '.jpg', '.avif', '.webp']) {
        expect(line, isNot(contains(part)), reason: 'no address reaches the log: "$line"');
      }
    }
    ImageDiskCache.shared = null;
    CoverFormat.shared = CoverFormat();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  /// Pictures kept in a temporary folder; each download is answered from [answers] by address (bytes, or an error to
  /// throw; [wide], a 400×200 picture, otherwise) and recorded in [downloads].
  Future<void> keep(WidgetTester tester) => tester.runAsync(() async {
    wide = await _png(400, 200);
    folder = await Directory.systemTemp.createTemp('cover_image');
    cache = ImageDiskCache(
      folder: folder.path,
      fetch: (url, _) async {
        downloads.add('$url');
        final answer = answers['$url'] ?? wide;
        if (answer is Uint8List) return answer;
        throw answer;
      },
    );
    ImageDiskCache.shared = cache;
  });

  /// ImageIO standing in: each decode recorded in [decodes] and answered by [answer].
  void avifOn(FutureOr<DecodedPicture?> Function() answer) {
    CoverFormat.shared = CoverFormat(
      decode: (data, width, height) async {
        decodes.add((data.length, width, height));
        return answer();
      },
    );
  }

  Iterable<LogEvent> lines(String msg) => logs.events.where((event) => event.msg == msg);

  Future<void> drop(WidgetTester tester) => tester.runAsync(() async {
    await cache.settle();
    await folder.delete(recursive: true);
  });

  /// Downloads, decodes and frames, with real time between them for the disk and the decoder.
  Future<void> arrive(WidgetTester tester, {int rounds = 20}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// [images] at [ratio] device pixels to the point.
  Future<void> show(WidgetTester tester, List<Widget> images, {double ratio = 1}) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(devicePixelRatio: ratio),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Column(mainAxisSize: MainAxisSize.min, children: images),
        ),
      ),
    ),
  );

  /// The network pictures shown (an avatar's default face is an asset).
  List<StoredNetworkImage> providers(WidgetTester tester) => [
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      if (image.image case final StoredNetworkImage network) network,
  ];

  List<ui.Image?> painted(WidgetTester tester) => [
    for (final raw in tester.widgetList<RawImage>(find.byType(RawImage))) raw.image,
  ];

  test('the decode size covers the box, keeps the shape and never passes the picture', () {
    (int?, int?) target(int width, int height, Size box) {
      final size = StoredNetworkImage.covering(width, height, box);
      return (size.width, size.height);
    }

    expect(target(1920, 1080, const Size(633, 475)), (null, 475));
    expect(target(1080, 1920, const Size(633, 475)), (633, null));
    expect(target(1920, 1080, const Size(1320, 700)), (1320, null));
    expect(target(633, 475, const Size(633, 475)), (null, null), reason: 'the size asked for decodes as is');
    expect(target(400, 300, const Size(633, 475)), (null, null));
    expect(target(0, 0, const Size(633, 475)), (null, null));
  });

  test("a cover's address names its size as a quality 90 JPEG, only on Bilibili's hosts and only where the address "
      'has no suffix or query yet', () {
    expect(coverImageUrl(_cover, width: 633, height: 475), _at(633, 475));
    expect(
      coverImageUrl('//i2.hdslb.com/bfs/archive/cover.jpg', width: 633, height: 475),
      _at(633, 475),
      reason: 'i0 and i2 are asked from i1',
    );
    expect(coverImageUrl('https://example.com/cover.jpg', width: 633, height: 475), 'https://example.com/cover.jpg');
    expect(
      coverImageUrl('https://i0.hdslb.com/bfs/archive/signed.jpg?sign=x', width: 633, height: 475),
      'https://i1.hdslb.com/bfs/archive/signed.jpg?sign=x',
    );
    expect(
      coverImageUrl('https://i1.hdslb.com/bfs/archive/cover.jpg@100w.webp', width: 633, height: 475),
      'https://i1.hdslb.com/bfs/archive/cover.jpg@100w.webp',
    );
  });

  testWidgets("a 推荐 card's cover is asked at its box's exact size in device pixels, given or laid out", (tester) async {
    for (final (ratio, width, height) in [(3.0, 633, 475), (2.0, 422, 317)]) {
      await show(tester, [
        _cardCover,
        const SizedBox(width: 211, height: 158.25, child: RemoteImage(_cover, cover: true)),
      ], ratio: ratio);
      expect(providers(tester).map((image) => (image.url, image.box)), [
        (_at(width, height), Size(width.toDouble(), height.toDouble())),
        (_at(width, height), Size(width.toDouble(), height.toDouble())),
      ], reason: 'at ${ratio}x');
    }
  });

  testWidgets('float error in a box never adds a pixel', (tester) async {
    const width = 628 / 3;
    const height = width / (4 / 3);
    expect(height * 3, greaterThan(471), reason: 'the float error this guards against');
    await show(tester, [
      const SizedBox(width: width, height: height, child: RemoteImage(_cover, cover: true)),
    ], ratio: 3);
    expect(providers(tester).single.url, _at(628, 471));
    expect(providers(tester).single.box, const Size(628, 471));
  });

  testWidgets('a precache and its draw share one download and one decode, drawn the frame it shows', (tester) async {
    await keep(tester);
    answers[_at(633, 475)] = (await tester.runAsync(() => _png(633, 475)))!;
    await show(tester, [const SizedBox()], ratio: 3);
    final context = tester.element(find.byType(SizedBox));
    final ready = await tester.runAsync(
      () => RemoteImage.precache(context, _cover, size: const Size(211, 158.25), cover: true),
    );
    expect(ready, isTrue);
    expect(PaintingBinding.instance.imageCache.currentSize, 1);

    await show(tester, [_cardCover], ratio: 3);
    final image = painted(tester).single;
    expect(image, isNotNull, reason: 'drawn the frame it shows');
    expect((image!.width, image.height), (633, 475), reason: 'decoded as it came');
    expect(PaintingBinding.instance.imageCache.currentSize, 1);
    expect(PaintingBinding.instance.imageCache.pendingImageCount, 0, reason: 'no second decode');
    expect(downloads, [_at(633, 475)]);
    await drop(tester);
  });

  testWidgets('a cover whose box has no known size is asked at 480 px a side', (tester) async {
    await keep(tester);
    await show(tester, [const SizedBox()]);
    final context = tester.element(find.byType(SizedBox));
    expect(await tester.runAsync(() => RemoteImage.precache(context, _cover, cover: true)), isTrue);
    expect(downloads, [_at(480, 480)]);
    await drop(tester);
  });

  testWidgets('two boxes of different size are two addresses, each downloaded', (tester) async {
    await keep(tester);
    await show(tester, [
      const SizedBox(width: 100, height: 100, child: RemoteImage(_cover, cover: true)),
      const SizedBox(width: 600, height: 400, child: RemoteImage(_cover, cover: true)),
    ]);
    expect(providers(tester).map((image) => image.url), [_at(100, 100), _at(600, 400)]);
    await arrive(tester);
    expect(painted(tester), everyElement(isNotNull));
    expect(downloads, unorderedEquals([_at(100, 100), _at(600, 400)]));
    await drop(tester);
  });

  testWidgets('an answer larger than the box decodes only as large as covering it needs; an address that takes no '
      'size is one download for every box', (tester) async {
    await keep(tester);
    const elsewhere = 'https://example.com/cover.jpg';
    await show(tester, [
      const SizedBox(width: 100, height: 100, child: RemoteImage(elsewhere, cover: true)),
      const SizedBox(width: 200, height: 150, child: RemoteImage(elsewhere, cover: true)),
    ]);
    expect(providers(tester).map((image) => (image.url, image.box)), [
      (elsewhere, const Size(100, 100)),
      (elsewhere, const Size(200, 150)),
    ]);
    await arrive(tester);
    final [small!, big!] = painted(tester);
    expect((small.width, small.height), (200, 100), reason: '400×200 covering 100×100');
    expect((big.width, big.height), (300, 150), reason: '400×200 covering 200×150');
    expect(downloads, [elsewhere]);
    await drop(tester);
  });

  test("a cover's key is its address and its box; its description leaves out the query", () {
    final asked = _at(633, 475);
    final cover = StoredNetworkImage(asked, box: const Size(633, 475));
    expect(cover, StoredNetworkImage(asked, box: const Size(633, 475)));
    expect(cover.hashCode, StoredNetworkImage(asked, box: const Size(633, 475)).hashCode);
    expect(cover, isNot(StoredNetworkImage(asked, box: const Size(422, 317))));
    expect(cover, isNot(StoredNetworkImage(asked)));
    expect(cover.cacheKey, same(cover));
    expect(
      '$cover',
      'StoredNetworkImage("i1.hdslb.com/bfs/archive/cover.jpg@633w_475h_1c_90q.jpg", still: true, box: 633×475)',
    );
    expect(
      '${const StoredNetworkImage('https://i1.hdslb.com/bfs/archive/signed.jpg?sign=SECRET', box: Size(40, 40))}',
      'StoredNetworkImage("i1.hdslb.com/bfs/archive/signed.jpg", still: true, box: 40×40)',
    );
  });

  testWidgets('a cover never moves, even when the CDN answers a moving picture', (tester) async {
    await keep(tester);
    answers[_at(633, 475)] = animatedGif;
    await show(tester, [_cardCover], ratio: 3);
    final cover = providers(tester).single;
    expect(cover.still, isTrue);

    Future<int> frames(ImageProvider provider) async {
      var shown = 0;
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((info, _) {
        shown++;
        info.dispose();
      });
      stream.addListener(listener);
      for (var step = 0; step < 10; step++) {
        // Decoding runs on the engine's real clock; the frame timer on the test's.
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      stream.removeListener(listener);
      return shown;
    }

    expect(await frames(cover), 1);
    expect(await frames(StoredNetworkImage(cover.url, still: false)), greaterThan(1), reason: 'the picture does move');
    await drop(tester);
  });

  testWidgets('faces and other pictures keep their webp in 60 px steps; a cover takes its exact size whatever its '
      'CDN suffix', (tester) async {
    await show(tester, [
      const SizedBox(width: 40, height: 40, child: RemoteImage.avatar('https://i0.hdslb.com/bfs/face/f.jpg')),
      const SizedBox(width: 40, height: 40, child: RemoteImage('https://i0.hdslb.com/bfs/garb/frame.png')),
      const SizedBox(width: 40, height: 40, child: RemoteImage(_cover, cover: true)),
      const SizedBox(width: 40, height: 40, child: RemoteImage(_cover, cdnSuffix: '@672w_378h_1c.webp')),
      const SizedBox(width: 40, height: 30, child: RemoteImage(_cover, cdnSuffix: '@672w_378h_1c.webp', cover: true)),
    ]);
    expect(providers(tester).map((image) => (image.url, image.box)), [
      ('https://i1.hdslb.com/bfs/face/f.jpg@60w_60h_1c.webp', null),
      ('https://i1.hdslb.com/bfs/garb/frame.png@60w_60h_1c.webp', null),
      (_at(40, 40), const Size(40, 40)),
      ('https://i1.hdslb.com/bfs/archive/cover.jpg@672w_378h_1c.webp', null),
      (_at(40, 30), const Size(40, 30)),
    ]);
  });

  test("a cover's preset only names its downloads; the JPEG an AVIF falls back on is part of its key", () {
    final avif = StoredNetworkImage(
      _feedAvif,
      box: const Size(633, 475),
      preset: CoverPreset.feed,
      jpegFallback: _at(633, 475),
    );
    expect(avif, StoredNetworkImage(_feedAvif, box: const Size(633, 475), jpegFallback: _at(633, 475)));
    expect(avif.hashCode, StoredNetworkImage(_feedAvif, box: const Size(633, 475)).hashCode);
    expect(avif, isNot(const StoredNetworkImage(_feedAvif, box: Size(633, 475), preset: CoverPreset.feed)));
  });

  group("the official app's presets", () {
    /// A new widget each time, so showing it again rebuilds the same element.
    Widget coverBox(String cover, {double width = 100, double height = 100, CoverPreset? preset = CoverPreset.feed}) =>
        SizedBox(
          width: width,
          height: height,
          child: RemoteImage(cover, cover: true, preset: preset),
        );

    /// [cover] as [preset] asks for it.
    String presetOf(String cover, [CoverPreset preset = CoverPreset.feed]) =>
        '${secureImageUrl(cover)}${preset.suffix}';

    Future<void> forgotten(WidgetTester tester, String address) => tester.runAsync(() async {
      for (var i = 0; i < 50 && cache.fileOf(address).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    testWidgets('without ImageIO an AVIF preset asks its exact size as JPEG; the webp preset is asked as it is and '
        'decoded only as large as covering its box needs', (tester) async {
      await keep(tester);
      await show(tester, [
        coverBox(_cover),
        coverBox(_cover, preset: CoverPreset.space),
        coverBox(_cover, width: 128, height: 72, preset: null),
      ]);
      expect(providers(tester).map((image) => (image.url, image.box, image.preset, image.jpegFallback)), [
        (_at(100, 100), const Size(100, 100), CoverPreset.feed, null),
        (presetOf(_cover, CoverPreset.space), const Size(100, 100), CoverPreset.space, null),
        (_at(128, 72), const Size(128, 72), CoverPreset.related, null),
      ]);
      expect(
        presetOf(_cover, CoverPreset.space),
        'https://i1.hdslb.com/bfs/archive/cover.jpg@384w_216h_1e_1c_85q.webp',
      );
      await arrive(tester);
      final [feed!, space!, related!] = painted(tester);
      expect((feed.width, feed.height), (200, 100), reason: '400×200 covering 100×100');
      expect((space.width, space.height), (200, 100));
      expect((related.width, related.height), (144, 72));
      expect(downloads, unorderedEquals([_at(100, 100), presetOf(_cover, CoverPreset.space), _at(128, 72)]));
      expect(decodes, isEmpty, reason: 'ImageIO is never asked on the PC');
      await drop(tester);
    });

    testWidgets("with ImageIO 推荐's cover asks its preset's AVIF and draws ImageIO's pixels; a precache and its "
        'draw, preset named or not, share one download and one decode', (tester) async {
      await keep(tester);
      avifOn(() => _pixels(6, 4, decodeMs: 37.4));
      answers[_feedAvif] = _avifBytes;
      await show(tester, [const SizedBox()], ratio: 3);
      final context = tester.element(find.byType(SizedBox));
      final ready = await tester.runAsync(
        () =>
            RemoteImage.precache(context, _cover, size: const Size(211, 158.25), cover: true, preset: CoverPreset.feed),
      );
      expect(ready, isTrue);
      expect(decodes, [(_avifBytes.length, 633, 475)], reason: 'the box in device pixels');

      await show(tester, [_feedCover], ratio: 3);
      final provider = providers(tester).single;
      expect((provider.url, provider.box, provider.jpegFallback), (_feedAvif, const Size(633, 475), _at(633, 475)));
      final image = painted(tester).single!;
      expect((image.width, image.height), (6, 4), reason: "ImageIO's size");
      await show(tester, [_cardCover], ratio: 3);
      expect(providers(tester).single.preset, CoverPreset.feed, reason: "a 4:3 box's preset is 推荐's");
      expect(painted(tester).single, isNotNull, reason: 'drawn the frame it shows');
      expect(downloads, [_feedAvif]);
      expect(decodes, hasLength(1), reason: 'the draws are the precache');
      expect(PaintingBinding.instance.imageCache.currentSize, 1);
      expect(CoverFormat.shared.avif, isTrue);
      expect(lines('cover format').single.f['format']?.toJson(), 'avif');
      await drop(tester);
    });

    testWidgets("a cover that names no preset takes its box's", (tester) async {
      await keep(tester);
      avifOn(() => _pixels(2, 2));
      await show(tester, [
        coverBox(_cover, width: 128, height: 72, preset: null),
        coverBox(_cover, width: 172, height: 96.67, preset: null),
        coverBox(_cover, width: 440, height: 247.67, preset: null),
      ], ratio: 3);
      expect(providers(tester).map((image) => (image.preset, image.url)), [
        (CoverPreset.history, presetOf(_cover, CoverPreset.history)),
        (CoverPreset.list, presetOf(_cover, CoverPreset.list)),
        (CoverPreset.player, presetOf(_cover, CoverPreset.player)),
      ]);
      await arrive(tester);
      await drop(tester);
    });

    for (final (kind, Object answer, FutureOr<DecodedPicture?> Function() decode, decoded) in [
      (
        'the CDN refuses',
        NetworkImageLoadException(statusCode: 404, uri: Uri.parse(_feedAvif)),
        () => _pixels(2, 2),
        0,
      ),
      ('ImageIO answers null for', _avifBytes, () => null, 1),
      ('ImageIO throws for', _avifBytes, () => throw PlatformException(code: 'decode-error'), 1),
    ]) {
      testWidgets('an AVIF $kind shows its exact-size JPEG in the same box', (tester) async {
        await keep(tester);
        avifOn(decode);
        answers[_feedAvif] = answer;
        await show(tester, [_feedCover], ratio: 3);
        await arrive(tester);
        final image = painted(tester).single!;
        expect((image.width, image.height), (400, 200), reason: "the JPEG's decode, no larger than it came");
        expect(providers(tester).single.url, _feedAvif, reason: 'one provider, falling back within');
        expect(downloads, [_feedAvif, _at(633, 475)], reason: 'the JPEG at the same box');
        expect(decodes, hasLength(decoded));
        expect(lines('image failed'), isEmpty, reason: 'no visible error');
        expect(CoverFormat.shared.address(_cover, CoverPreset.feed), isNull, reason: 'its exact size from now on');
        expect(CoverFormat.shared.avif, isTrue, reason: 'one failure');
        if (decoded == 0) {
          expect(lines('avif refused').single.f['status']?.toJson(), 404);
        } else {
          expect(lines('avif decode failed'), hasLength(1));
          await forgotten(tester, _feedAvif);
          expect(cache.fileOf(_feedAvif).existsSync(), isFalse, reason: "a stored AVIF that doesn't decode goes");
          expect(cache.fileOf(_at(633, 475)).existsSync(), isTrue);
        }
        await drop(tester);
      });
    }

    testWidgets('three AVIF decode failures in a row turn AVIF off: every cover after asks its exact size', (
      tester,
    ) async {
      await keep(tester);
      avifOn(() => null);
      const covers = ['$_cover.1', '$_cover.2', '$_cover.3'];
      for (final cover in covers) {
        answers[presetOf(cover)] = _avifBytes;
      }
      await show(tester, [for (final cover in covers) coverBox(cover, width: 60, height: 60)]);
      expect(providers(tester).map((image) => image.url), [for (final cover in covers) presetOf(cover)]);
      await arrive(tester);
      expect(painted(tester), everyElement(isNotNull), reason: 'each shown from its JPEG');
      expect(CoverFormat.shared.avif, isFalse);
      expect(lines('avif off').single.f['failures']?.toJson(), 3);
      await show(tester, [coverBox('$_cover.4', width: 60, height: 60)]);
      expect(providers(tester).single.url, 'https://i1.hdslb.com/bfs/archive/cover.jpg.4@60w_60h_1c_90q.jpg');
      await arrive(tester);
      await drop(tester);
    });

    testWidgets('a cover shown from its JPEG after its AVIF failed stays up when it is next built for the JPEG', (
      tester,
    ) async {
      await keep(tester);
      avifOn(() => null);
      answers[_feedAvif] = _avifBytes;
      await show(tester, [coverBox(_cover)]);
      await arrive(tester);
      final first = painted(tester).single!;
      expect(providers(tester).single.url, _feedAvif);

      // Rebuilt in place, the cover now asks its JPEG, which comes from storage only once real time runs.
      await show(tester, [coverBox(_cover)]);
      expect(providers(tester).single.url, _at(100, 100));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value, 1, reason: 'no new fade');
      expect(painted(tester).single?.isCloneOf(first), isTrue, reason: 'gapless playback paints the old frame');
      await arrive(tester);
      expect(painted(tester).single?.isCloneOf(first), isFalse, reason: 'the JPEG is in');
      expect(tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value, 1);
      expect(downloads, [_feedAvif, _at(100, 100)], reason: 'the JPEG came from storage');
      await drop(tester);
    });

    testWidgets("every 10th network download of a preset and format logs `cover downloads`, under its box's preset "
        'when it names none; covers from storage count none', (tester) async {
      await keep(tester);
      avifOn(() => _pixels(2, 2, decodeMs: 7.6));
      final avif = Uint8List.fromList([..._avifBytes, ...List.filled(30 * 1024, 0)]);
      Widget related(String cover) => coverBox(cover, width: 30, height: 15, preset: null);
      Widget space(String cover) => coverBox(cover, width: 15, height: 15, preset: CoverPreset.space);
      final stored = [for (var i = 0; i < 10; i++) '$_cover.stored$i'];
      await tester.runAsync(() async {
        await Directory(folder.path).create(recursive: true);
        for (final cover in stored) {
          await cache.fileOf(presetOf(cover, CoverPreset.related)).writeAsBytes(avif);
        }
      });
      await show(tester, [for (final cover in stored) related(cover)]);
      await arrive(tester);
      expect(painted(tester), everyElement(isNotNull));
      expect(downloads, isEmpty);

      final covers = [for (var i = 0; i < 10; i++) '$_cover.$i'];
      for (final cover in covers) {
        answers[presetOf(cover, CoverPreset.related)] = avif;
      }
      await show(tester, [for (final cover in covers.take(9)) related(cover)]);
      await arrive(tester);
      expect(lines('cover downloads'), isEmpty);
      await show(tester, [for (final cover in covers) related(cover), for (final cover in covers) space(cover)]);
      await arrive(tester);
      expect(downloads, hasLength(20));
      final logged = [
        for (final line in lines('cover downloads')) line.f.map((key, value) => MapEntry(key, value.toJson())),
      ];
      expect(logged, hasLength(2));
      // Whichever finished its 10th first logs first.
      final avifLine = logged.singleWhere((line) => line['format'] == 'avif');
      final webpLine = logged.singleWhere((line) => line['format'] == 'webp');
      expect(avifLine, {
        'preset': 'related',
        'format': 'avif',
        'n': 10,
        'firstByteMs': avifLine['firstByteMs'],
        'firstByteMaxMs': avifLine['firstByteMaxMs'],
        'kb': 30,
        'decodeMsMax': 8,
      });
      expect(avifLine['firstByteMs'], isA<int>());
      expect(avifLine['firstByteMaxMs'], greaterThanOrEqualTo(avifLine['firstByteMs']! as int));
      expect(webpLine, {
        'preset': 'space',
        'format': 'webp',
        'n': 10,
        'firstByteMs': webpLine['firstByteMs'],
        'firstByteMaxMs': webpLine['firstByteMaxMs'],
        'kb': (wide.length / 1024).round(),
      });
      await drop(tester);
    });
  });
}
