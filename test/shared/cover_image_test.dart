import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:bilifast/shared/remote_image.dart';
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

/// A 推荐 card's cover box.
const _cardCover = SizedBox(
  width: 211,
  height: 158.25,
  child: RemoteImage(_cover, size: Size(211, 158.25), cover: true),
);

void main() {
  late Directory folder;
  late ImageDiskCache cache;
  late List<String> downloads;
  late Map<String, Uint8List> answers;
  late Uint8List wide;

  setUp(() {
    downloads = [];
    answers = {};
  });

  tearDown(() {
    ImageDiskCache.shared = null;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  /// Pictures kept in a temporary folder; each download is answered from [answers] by address ([wide], a 400×200
  /// picture, otherwise) and recorded in [downloads].
  Future<void> keep(WidgetTester tester) => tester.runAsync(() async {
    wide = await _png(400, 200);
    folder = await Directory.systemTemp.createTemp('cover_image');
    cache = ImageDiskCache(
      folder: folder.path,
      fetch: (url, _) async {
        downloads.add('$url');
        return answers['$url'] ?? wide;
      },
    );
    ImageDiskCache.shared = cache;
  });

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
}
