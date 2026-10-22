import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/devlog.dart';
import 'package:bilifast/shared/cover_format.dart';
import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:bilifast/shared/ios/picture_api.g.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A plain [width] × [height] PNG, standing in for the CDN's webp.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = const Color(0xFF808080));
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// ImageIO's answer as the fake gives it: [width] × [height] grey pixels.
DecodedPicture _pixels(int width, int height, {double decodeMs = 20}) => DecodedPicture(
  pixels: Uint8List.fromList(List.filled(width * height * 4, 0x80)),
  width: width,
  height: height,
  rowBytes: width * 4,
  decodeMs: decodeMs,
);

const _cover = 'https://i0.hdslb.com/bfs/archive/cover.jpg';
const _avif = '$_cover@.avif';
const _webp = '$_cover@.webp';

/// A 推荐 card's cover box.
const _cardCover = SizedBox(
  width: 211,
  height: 158.25,
  child: RemoteImage(_cover, size: Size(211, 158.25), cover: true),
);

final _avifBytes = Uint8List.fromList([0, 0, 0, 0x1C, ...'ftypavif'.codeUnits]);

void main() {
  late Directory folder;
  late ImageDiskCache cache;
  late List<String> downloads;
  late Map<String, Object> answers;
  late MemorySink logs;
  late Uint8List webpBytes;

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
    ImageDiskCache.shared = null;
    CoverFormat.shared = CoverFormat();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  /// Pictures kept in a temporary folder; each download is answered from [answers] by address (bytes, or an error to
  /// throw) and recorded in [downloads].
  Future<void> keep(WidgetTester tester) => tester.runAsync(() async {
    webpBytes = await _png(400, 200);
    folder = await Directory.systemTemp.createTemp('cover_image');
    cache = ImageDiskCache(
      folder: folder.path,
      fetch: (url, _) async {
        downloads.add('$url');
        final answer = answers['$url'] ?? webpBytes;
        if (answer is Uint8List) return answer;
        throw answer;
      },
    );
    ImageDiskCache.shared = cache;
  });

  Future<void> drop(WidgetTester tester) => tester.runAsync(() async {
    await cache.settle();
    await folder.delete(recursive: true);
  });

  void avifOn(FutureOr<DecodedPicture?> Function() answer) {
    CoverFormat.shared = CoverFormat(
      decode: (data, width, height) async {
        decodes.add((data.length, width, height));
        return answer();
      },
    );
  }

  /// Downloads, decodes and frames, with real time between them for the disk and the decoder.
  Future<void> arrive(WidgetTester tester, {int rounds = 20}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// [images] at 1×, so boxes are their sizes in points rounded up to 60.
  Future<void> show(WidgetTester tester, List<Widget> images) => tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 1),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Column(mainAxisSize: MainAxisSize.min, children: images),
        ),
      ),
    ),
  );

  /// A new widget each time, so showing it again rebuilds the same element.
  Widget coverBox(String cover, {double side = 100}) =>
      SizedBox(width: side, height: side, child: RemoteImage(cover, cover: true));

  /// The network pictures shown (an avatar's default face is an asset).
  List<StoredNetworkImage> providers(WidgetTester tester) => [
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      if (image.image case final StoredNetworkImage network) network,
  ];

  List<ui.Image?> painted(WidgetTester tester) => [
    for (final raw in tester.widgetList<RawImage>(find.byType(RawImage))) raw.image,
  ];

  Iterable<LogEvent> lines(String msg) => logs.events.where((event) => event.msg == msg);

  test('the decode size covers the box, keeps the shape and never passes the picture', () {
    (int?, int?) target(int width, int height, Size box) {
      final size = StoredNetworkImage.covering(width, height, box);
      return (size.width, size.height);
    }

    expect(target(1920, 1080, const Size(660, 480)), (null, 480));
    expect(target(1080, 1920, const Size(660, 480)), (660, null));
    expect(target(1920, 1080, const Size(1320, 700)), (1320, null));
    expect(target(400, 300, const Size(660, 480)), (null, null));
    expect(target(0, 0, const Size(660, 480)), (null, null));
  });

  test("a cover's cache key is its address and its box: two boxes are two decodes", () {
    const small = StoredNetworkImage(_webp, box: Size(240, 180));
    expect(small, const StoredNetworkImage(_webp, box: Size(240, 180)));
    expect(small.hashCode, const StoredNetworkImage(_webp, box: Size(240, 180)).hashCode);
    expect(small, isNot(const StoredNetworkImage(_webp, box: Size(480, 300))));
    expect(small, isNot(const StoredNetworkImage(_webp)));
    expect(small.cacheKey, same(small));
    expect('$small', 'StoredNetworkImage("i0.hdslb.com/bfs/archive/cover.jpg@.webp", still: true, box: 240×180)');
  });

  testWidgets('on the PC a cover asks for the full-size webp and decodes it only as large as covering its box needs', (
    tester,
  ) async {
    await keep(tester);
    await show(tester, [
      const SizedBox(width: 100, height: 100, child: RemoteImage(_cover, cover: true)),
      const SizedBox(width: 600, height: 400, child: RemoteImage(_cover, cover: true)),
    ]);
    expect(providers(tester).map((image) => (image.url, image.box)), [
      (_webp, const Size(120, 120)),
      (_webp, const Size(600, 420)),
    ]);
    await arrive(tester);
    final [small!, big!] = painted(tester);
    expect((small.width, small.height), (240, 120), reason: '400×200 covering 120×120');
    expect((big.width, big.height), (400, 200), reason: 'never larger than the picture');
    expect(downloads, [_webp], reason: 'one download serves both boxes');
    expect(decodes, isEmpty, reason: 'ImageIO is never asked on the PC');
    await drop(tester);
  });

  testWidgets('a precache and its draw share one decode; the precache says nothing of ImageIO for a webp', (
    tester,
  ) async {
    await keep(tester);
    await show(tester, [const SizedBox()]);
    final context = tester.element(find.byType(SizedBox));
    final decoded = <double>[];
    final ready = await tester.runAsync(
      () => RemoteImage.precache(context, _cover, size: const Size(211, 158.25), cover: true, onDecoded: decoded.add),
    );
    expect(ready, isTrue);
    expect(decoded, isEmpty);
    await show(tester, [_cardCover]);
    expect(painted(tester).single, isNotNull, reason: 'drawn the frame it shows');
    expect(providers(tester).single.box, const Size(240, 180));
    expect(downloads, [_webp]);
    await drop(tester);
  });

  testWidgets("with ImageIO a cover asks for AVIF and draws ImageIO's pixels at the size it answered", (tester) async {
    await keep(tester);
    avifOn(() => _pixels(6, 4, decodeMs: 37.4));
    answers[_avif] = _avifBytes;
    await show(tester, [const SizedBox()]);
    final context = tester.element(find.byType(SizedBox));
    final decoded = <double>[];
    final ready = await tester.runAsync(
      () => RemoteImage.precache(context, _cover, size: const Size(211, 158.25), cover: true, onDecoded: decoded.add),
    );
    expect(ready, isTrue);
    expect(decoded, [37.4]);
    expect(decodes, [(_avifBytes.length, 240, 180)], reason: "the box in device pixels, in the 60 px steps");

    await show(tester, [_cardCover]);
    expect(providers(tester).single.url, _avif);
    final image = painted(tester).single!;
    expect((image.width, image.height), (6, 4));
    expect(downloads, [_avif]);
    expect(decodes, hasLength(1), reason: 'the draw is the precache');
    expect(CoverFormat.shared.avif, isTrue);
    await drop(tester);
  });

  for (final (kind, FutureOr<DecodedPicture?> Function() answer, reason) in [
    ('answers null', () => null, 'null'),
    ('throws', () => throw PlatformException(code: 'decode-error'), 'platform decode-error'),
  ]) {
    testWidgets('an AVIF ImageIO $kind for shows its webp in the same place, and the stored AVIF is forgotten', (
      tester,
    ) async {
      await keep(tester);
      avifOn(answer);
      answers[_avif] = _avifBytes;
      await show(tester, [const SizedBox(width: 100, height: 100, child: RemoteImage(_cover, cover: true))]);
      await arrive(tester);
      final image = painted(tester).single!;
      expect((image.width, image.height), (240, 120), reason: "the webp's decode");
      expect(downloads, [_avif, _webp]);
      await tester.runAsync(cache.settle);
      await tester.runAsync(() async {
        for (var i = 0; i < 50 && cache.fileOf(_avif).existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(cache.fileOf(_avif).existsSync(), isFalse);
      expect(cache.fileOf(_webp).existsSync(), isTrue);
      expect(lines('image failed'), isEmpty, reason: 'no visible error');
      expect(lines('avif decode failed').single.f['reason']?.toJson(), reason);
      expect(CoverFormat.shared.address(_cover), _webp, reason: 'the cover asks for webp from now on');
      expect(CoverFormat.shared.avif, isTrue, reason: 'one failure');
      await drop(tester);
    });
  }

  testWidgets('an AVIF stored on the phone that no longer decodes is deleted, so it is not read again', (tester) async {
    await keep(tester);
    avifOn(() => null);
    await tester.runAsync(() async {
      await Directory(folder.path).create(recursive: true);
      await cache.fileOf(_avif).writeAsBytes(_avifBytes);
    });
    await show(tester, [const SizedBox(width: 100, height: 100, child: RemoteImage(_cover, cover: true))]);
    await arrive(tester);
    expect(painted(tester).single, isNotNull);
    expect(downloads, [_webp], reason: 'the AVIF came from storage');
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && cache.fileOf(_avif).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(cache.fileOf(_avif).existsSync(), isFalse);
    await drop(tester);
  });

  testWidgets('an AVIF the CDN refuses shows its webp, without counting against ImageIO', (tester) async {
    await keep(tester);
    avifOn(() => _pixels(2, 2));
    answers[_avif] = NetworkImageLoadException(statusCode: 400, uri: Uri.parse(_avif));
    await show(tester, [const SizedBox(width: 100, height: 100, child: RemoteImage(_cover, cover: true))]);
    await arrive(tester);
    expect(painted(tester).single, isNotNull);
    expect(downloads, [_avif, _webp]);
    expect(decodes, isEmpty);
    expect(lines('avif refused').single.f['status']?.toJson(), 400);
    expect(lines('image failed'), isEmpty);
    await drop(tester);
  });

  testWidgets('three AVIF failures in a row turn AVIF off: every cover after asks for webp', (tester) async {
    await keep(tester);
    avifOn(() => null);
    const covers = ['$_cover.1', '$_cover.2', '$_cover.3'];
    for (final cover in covers) {
      answers['$cover@.avif'] = _avifBytes;
    }
    await show(tester, [for (final cover in covers) coverBox(cover, side: 60)]);
    expect(providers(tester).map((image) => image.url), everyElement(endsWith('@.avif')));
    await arrive(tester);
    expect(painted(tester), everyElement(isNotNull), reason: 'each shown from its webp');
    expect(CoverFormat.shared.avif, isFalse);
    expect(lines('avif off').single.f['failures']?.toJson(), 3);
    await show(tester, [coverBox('$_cover.4', side: 60)]);
    expect(providers(tester).single.url, '$_cover.4@.webp');
    await arrive(tester);
    await drop(tester);
  });

  testWidgets('a cover shown from its webp after its AVIF failed stays up when it is next built for the webp', (
    tester,
  ) async {
    await keep(tester);
    avifOn(() => null);
    answers[_avif] = _avifBytes;
    await show(tester, [coverBox(_cover)]);
    await arrive(tester);
    final first = painted(tester).single!;
    expect(providers(tester).single.url, _avif);

    // Rebuilt in place, the cover now asks for its webp, which comes from storage only once real time runs.
    await show(tester, [coverBox(_cover)]);
    expect(providers(tester).single.url, _webp);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final opacity = tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;
    expect(opacity, 1, reason: 'the same cover, not a new picture fading in');
    expect(painted(tester).single?.isCloneOf(first), isTrue, reason: 'gapless playback paints the old frame');
    await arrive(tester);
    expect(painted(tester).single?.isCloneOf(first), isFalse, reason: 'the webp is in');
    expect(tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value, 1);
    expect(downloads, [_avif, _webp], reason: 'the webp came from storage');
    await drop(tester);
  });

  testWidgets('faces and other pictures keep their box-sized addresses while covers go full size', (tester) async {
    avifOn(() => null);
    await show(tester, [
      const SizedBox(width: 40, height: 40, child: RemoteImage.avatar('https://i0.hdslb.com/bfs/face/f.jpg')),
      const SizedBox(width: 40, height: 40, child: RemoteImage('https://i0.hdslb.com/bfs/garb/frame.png')),
      const SizedBox(width: 40, height: 40, child: RemoteImage(_cover, cover: true)),
    ]);
    expect(providers(tester).map((image) => (image.url, image.box)), [
      ('https://i0.hdslb.com/bfs/face/f.jpg@60w_60h_1c.webp', null),
      ('https://i0.hdslb.com/bfs/garb/frame.png@60w_60h_1c.webp', null),
      (_avif, const Size(60, 60)),
    ]);
  });
}
