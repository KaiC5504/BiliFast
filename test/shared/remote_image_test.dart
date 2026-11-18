import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/devlog.dart';
import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stored_pictures.dart';

/// Answers every image request with [animatedGif]; nothing reaches the network. While [hold] is pending, answers
/// wait for it.
final class _GifClient implements HttpClient {
  final asked = <Uri>[];
  Future<void>? hold;
  int aborted = 0;

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    asked.add(url);
    return _GifRequest(this, hold);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GifRequest implements HttpClientRequest {
  _GifRequest(this._client, this._hold);

  final _GifClient _client;
  final Future<void>? _hold;

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async {
    await _hold;
    return _GifResponse();
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) => _client.aborted++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Headers implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GifResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => animatedGif.length;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(animatedGif as List<int>)
          .listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _red = Color(0xFFFF0000);

/// A [width] × [height] PNG, red over its top half and blue under it.
Future<Uint8List> _halves(WidgetTester tester, int width, int height) async => (await tester.runAsync(() async {
  final recorder = ui.PictureRecorder();
  final half = height / 2;
  Canvas(recorder)
    ..drawRect(Rect.fromLTWH(0, 0, width.toDouble(), half), Paint()..color = _red)
    ..drawRect(Rect.fromLTWH(0, half, width.toDouble(), half), Paint()..color = const Color(0xFF0000FF));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}))!;

Future<Color> _pixel(WidgetTester tester, ui.Image image, int x, int y) async {
  final rgba = (await tester.runAsync(image.toByteData))!;
  final at = (y * image.width + x) * 4;
  return Color.fromARGB(rgba.getUint8(at + 3), rgba.getUint8(at), rgba.getUint8(at + 1), rgba.getUint8(at + 2));
}

void main() {
  tearDown(
    () => PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages(),
  );

  /// Frames [provider] hands its listener over a second of playback.
  Future<int> framesShown(WidgetTester tester, ImageProvider provider) async {
    var frames = 0;
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      frames++;
      info.dispose();
    });
    stream.addListener(listener);
    for (var step = 0; step < 10; step++) {
      // Decoding runs on the engine's real clock; the frame timer on the test's.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    stream.removeListener(listener);
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    return frames;
  }

  testWidgets('an animated picture shows its first frame and asks for no more, unless it moves', (tester) async {
    const url = 'https://i0.hdslb.com/bfs/face/moving.gif@120w_120h_1c.webp';
    debugNetworkImageHttpClientProvider = _GifClient.new;
    try {
      expect(await framesShown(tester, const NetworkImage(url)), greaterThan(1), reason: 'the GIF does move');
      expect(await framesShown(tester, const StoredNetworkImage(url)), 1);
      expect(await framesShown(tester, const StoredNetworkImage(url, still: false)), greaterThan(1));
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  testWidgets('a still picture is not the moving one in the cache', (tester) async {
    const url = 'https://i0.hdslb.com/bfs/archive/a.jpg';
    Future<Object> key(ImageProvider provider) => provider.obtainKey(ImageConfiguration.empty);
    expect(const StoredNetworkImage(url), const StoredNetworkImage(url));
    expect(await key(const StoredNetworkImage(url)), const StoredNetworkImage(url));
    expect(await key(const StoredNetworkImage(url)), isNot(const NetworkImage(url)));
    expect(const NetworkImage(url), isNot(const StoredNetworkImage(url)));
    expect(const StoredNetworkImage(url), isNot(const StoredNetworkImage(url, still: false)));
    expect(await key(const StoredNetworkImage(url, still: false)), const NetworkImage(url));
  });

  testWidgets('covers, faces and badges are still; emotes and 装扮 pictures move', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            for (final url in [
              'https://i0.hdslb.com/bfs/archive/cover.gif',
              '//i1.hdslb.com/bfs/face/face.gif',
              'https://i0.hdslb.com/bfs/activity-plat/static/badge.png',
              'https://i0.hdslb.com/bfs/emote/doge.gif',
              'http://i0.hdslb.com/bfs/garb/item/sticker.gif',
            ])
              SizedBox.square(dimension: 40, child: RemoteImage(url)),
          ],
        ),
      ),
    );
    final providers = [for (final image in tester.widgetList<Image>(find.byType(Image))) image.image];
    expect(providers.map((provider) => (provider as StoredNetworkImage).still), [true, true, true, false, false]);
    expect(providers.whereType<NetworkImage>(), hasLength(5), reason: 'all of them are network pictures');
  });

  test('its description leaves out the query', () {
    expect(
      '${const StoredNetworkImage('https://i0.hdslb.com/bfs/archive/a.jpg?sign=secret')}',
      'StoredNetworkImage("i0.hdslb.com/bfs/archive/a.jpg", still: true)',
    );
  });

  testWidgets('a download that stalls gives up after 30 s, logged by kind with the host and path only', (tester) async {
    final logs = MemorySink();
    Logger.shared.add(logs);
    addTearDown(() => Logger.shared.remove(logs));
    final client = _GifClient()..hold = Completer<void>().future;
    debugNetworkImageHttpClientProvider = () => client;
    try {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.square(
              dimension: 40,
              child: RemoteImage('https://i5.hdslb.com/bfs/archive/stalled.jpg?sign=SECRET'),
            ),
          ),
        ),
      );
      Iterable<LogEvent> failures() => logs.events.where((event) => event.msg == 'image failed');
      await tester.pump(const Duration(seconds: 29));
      expect(failures(), isEmpty);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      final failure = failures().single;
      expect(failure.f['error']?.toJson(), 'TimeoutException');
      expect(failure.f['host']?.toJson(), 'i5.hdslb.com');
      expect(failure.f['path']?.toJson(), '/bfs/archive/stalled.jpg');
      expect(client.aborted, 1, reason: 'the connection is closed');
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  group('with pictures kept on the phone', () {
    const url = 'https://i0.hdslb.com/bfs/archive/kept.jpg@240w_180h_1c.webp';
    late Directory folder;
    late ImageDiskCache cache;
    late List<Uint8List> answers;
    late int downloads;
    late List<String> asked;
    Object? failure;
    late Map<String, Object> refusing;

    setUp(() {
      answers = [];
      downloads = 0;
      asked = [];
      failure = null;
      refusing = {};
    });

    tearDown(() => ImageDiskCache.shared = null);

    Future<void> keep(WidgetTester tester) => tester.runAsync(() async {
      folder = await Directory.systemTemp.createTemp('remote_image');
      cache = ImageDiskCache(
        folder: folder.path,
        fetch: (url, _) async {
          downloads++;
          asked.add('$url');
          if (refusing['$url'] ?? failure case final failure?) throw failure;
          return answers.removeAt(0);
        },
      );
      ImageDiskCache.shared = cache;
    });

    Future<void> drop(WidgetTester tester) => tester.runAsync(() async {
      await cache.settle();
      await folder.delete(recursive: true);
    });

    /// The provider's first frame, or its error.
    Future<Object> resolve(WidgetTester tester, ImageProvider provider) async {
      final result = await tester.runAsync(() async {
        // Made here, not in the test's fake zone, whose microtasks wait for a pump.
        final outcome = Completer<Object>();
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (info, _) {
            if (!outcome.isCompleted) outcome.complete(info);
          },
          onError: (error, _) {
            if (!outcome.isCompleted) outcome.complete(error);
          },
        );
        stream.addListener(listener);
        final result = await outcome.future.timeout(const Duration(seconds: 5));
        stream.removeListener(listener);
        await cache.settle();
        return result;
      });
      if (result is ImageInfo) result.dispose();
      return result!;
    }

    testWidgets('a picture the memory cache let go comes back from storage, not the network', (tester) async {
      await keep(tester);
      answers.add(animatedGif);
      expect(await resolve(tester, const StoredNetworkImage(url)), isA<ImageInfo>());
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      expect(await resolve(tester, const StoredNetworkImage(url)), isA<ImageInfo>());
      expect(downloads, 1);
      await drop(tester);
    });

    testWidgets('a stored picture that does not decode is deleted, and the next ask downloads it again', (
      tester,
    ) async {
      await keep(tester);
      answers.add(Uint8List.fromList(List.filled(64, 7)));
      expect(await resolve(tester, const StoredNetworkImage(url)), isNot(isA<ImageInfo>()));
      await tester.runAsync(() async {
        for (var i = 0; i < 50 && cache.fileOf(url).existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(cache.fileOf(url).existsSync(), isFalse);
      await tester.pump();

      answers.add(animatedGif);
      expect(await resolve(tester, const StoredNetworkImage(url)), isA<ImageInfo>());
      expect(downloads, 2);
      await drop(tester);
    });

    testWidgets('a picture got ready ahead that fails answers false, logged once by host and status', (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      await keep(tester);
      const refused = 'https://i3.hdslb.com/bfs/archive/refused.jpg';
      failure = NetworkImageLoadException(statusCode: 403, uri: Uri.parse(refused));
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      for (var ask = 0; ask < 2; ask++) {
        final ready = await tester.runAsync(() => RemoteImage.precache(context, refused, size: const Size(160, 100)));
        expect(ready, isFalse);
      }
      expect(downloads, 2);
      final warning = logs.events.where((event) => event.msg == 'image failed').single;
      expect(warning.f['host']?.toJson(), 'i3.hdslb.com');
      expect(warning.f['status']?.toJson(), 403);
      expect('${warning.f['path']?.toJson()}', startsWith('/bfs/archive/refused.jpg@'));
      await drop(tester);
    });

    testWidgets("a picture lost on URLSession's way logs its error code", (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      await keep(tester);
      failure = const PictureDownloadException('URLSession -1009');
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      const offline = 'https://i4.hdslb.com/bfs/archive/offline.jpg';
      expect(await tester.runAsync(() => RemoteImage.precache(context, offline, size: const Size(160, 100))), isFalse);
      final warning = logs.events.where((event) => event.msg == 'image failed').single;
      expect(warning.f['error']?.toJson(), 'URLSession -1009');
      await drop(tester);
    });

    testWidgets('only covers time their downloads', (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      await keep(tester);
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      for (var i = 0; i < 10; i++) {
        answers.add(animatedGif);
        final face = 'https://i0.hdslb.com/bfs/face/$i.jpg';
        expect(await tester.runAsync(() => RemoteImage.precache(context, face, size: const Size(40, 40))), isTrue);
      }
      expect(downloads, 10);
      expect(logs.events.where((event) => event.msg == 'cover downloads'), isEmpty);
      await drop(tester);
    });

    testWidgets('a picture got ready ahead with a CDN suffix is the one a box of any size with that suffix draws', (
      tester,
    ) async {
      await keep(tester);
      answers.add(animatedGif);
      const cover = 'https://i1.hdslb.com/bfs/archive/ahead.jpg';
      const suffix = '@672w_378h_1c.webp';
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      expect(await tester.runAsync(() => RemoteImage.precache(context, cover, cdnSuffix: suffix)), isTrue);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 50, height: 30, child: RemoteImage(cover, cdnSuffix: suffix)),
          ),
        ),
      );
      expect((tester.widget<Image>(find.byType(Image)).image as StoredNetworkImage).url, '$cover$suffix');
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull, reason: 'drawn the frame it shows');
      expect(downloads, 1);
      await drop(tester);
    });

    testWidgets("an i0 cover got ready ahead is asked from i1, and the same path on i2 draws it without asking again", (
      tester,
    ) async {
      await keep(tester);
      answers.add(animatedGif);
      const suffix = '@672w_378h_1c.webp';
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      expect(
        await tester.runAsync(
          () => RemoteImage.precache(context, 'http://i0.hdslb.com/bfs/archive/m.jpg', cdnSuffix: suffix),
        ),
        isTrue,
      );
      expect(asked, ['https://i1.hdslb.com/bfs/archive/m.jpg$suffix']);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 50,
              height: 30,
              child: RemoteImage('//i2.hdslb.com/bfs/archive/m.jpg', cdnSuffix: suffix),
            ),
          ),
        ),
      );
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull, reason: 'drawn the frame it shows');
      expect(downloads, 1);
      await drop(tester);
    });

    testWidgets('a long picture answered whole is kept at its box from the top, and got ready ahead is the one drawn', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      await keep(tester);
      answers.add(await _halves(tester, 40, 400));
      const long = 'https://i1.hdslb.com/bfs/new_dyn/kept-long.jpg';
      const size = Size(20, 30);
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      expect(
        await tester.runAsync(() => RemoteImage.precache(context, long, size: size, alignment: Alignment.topCenter)),
        isTrue,
      );
      expect(asked, [widthImageUrl(long, width: 60)]);
      expect(PaintingBinding.instance.imageCache.currentSizeBytes, 20 * 30 * 4, reason: 'only the box is kept');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.fromSize(
              size: size,
              child: const RemoteImage(long, size: size, alignment: Alignment.topCenter),
            ),
          ),
        ),
      );
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect([image.width, image.height], [20, 30], reason: 'the 40×400 answer decoded 20 wide, its top 30 kept');
      expect(await _pixel(tester, image, 10, 29), _red, reason: 'the centre would be blue here');
      expect(downloads, 1);
      await drop(tester);
    });

    testWidgets('a long picture whose whole address is refused or does not decode is drawn from the centre crop', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      await keep(tester);
      final png = await _halves(tester, 40, 400);
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      Future<bool?> ready(String url) => tester.runAsync(
        () => RemoteImage.precache(context, url, size: const Size(20, 30), alignment: Alignment.topCenter),
      );
      List<String> both(String url) => [widthImageUrl(url, width: 60), sizedImageUrl(url, width: 60, height: 60)];

      const refused = 'https://i1.hdslb.com/bfs/new_dyn/refused-long.jpg';
      refusing[widthImageUrl(refused, width: 60)] = NetworkImageLoadException(statusCode: 400, uri: Uri.parse(refused));
      answers.add(png);
      expect(await ready(refused), isTrue);
      expect(asked, both(refused));

      const broken = 'https://i1.hdslb.com/bfs/new_dyn/broken-long.jpg';
      answers.addAll([Uint8List.fromList(List.filled(64, 7)), png]);
      expect(await ready(broken), isTrue);
      expect(asked.skip(2), both(broken));

      PaintingBinding.instance.imageCache.clear();
      asked.clear();
      expect(await ready(refused), isTrue);
      expect(await ready(broken), isTrue);
      expect(asked, isEmpty, reason: 'the centre crops come back from storage, the whole ones are not asked again');

      const offline = 'https://i1.hdslb.com/bfs/new_dyn/offline-long.jpg';
      failure = const PictureDownloadException('URLSession -1009');
      expect(await ready(offline), isFalse);
      expect(asked, [widthImageUrl(offline, width: 60)], reason: 'a lost connection would lose the centre crop too');
      await drop(tester);
    });
  });

  testWidgets('a CDN suffix is asked for whatever the box and the pixel ratio; without one the box is rounded up', (
    tester,
  ) async {
    const cover = 'https://i1.hdslb.com/bfs/archive/fixed.jpg';
    const suffix = '@672w_378h_1c.webp';
    for (final ratio in [1.0, 2.0, 3.0]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(devicePixelRatio: ratio),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 211, height: 158.25, child: RemoteImage(cover, cdnSuffix: suffix)),
                SizedBox(width: 100, height: 100, child: RemoteImage(cover, cdnSuffix: suffix)),
                SizedBox(width: 40, height: 40, child: RemoteImage(cover)),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: RemoteImage('https://i1.hdslb.com/bfs/archive/signed.jpg?sign=x', cdnSuffix: suffix),
                ),
              ],
            ),
          ),
        ),
      );
      final addresses = [
        for (final image in tester.widgetList<Image>(find.byType(Image))) (image.image as StoredNetworkImage).url,
      ];
      final bucket = (40 * ratio / 60).ceil() * 60;
      expect(addresses, [
        '$cover$suffix',
        '$cover$suffix',
        sizedImageUrl(cover, width: bucket, height: bucket),
        'https://i1.hdslb.com/bfs/archive/signed.jpg?sign=x',
      ], reason: 'at ${ratio}x');
    }
    const schemeless = '//i1.hdslb.com/bfs/archive/a.jpg';
    expect(suffixedImageUrl(schemeless, suffix), 'https:$schemeless$suffix');
    expect(suffixedImageUrl('https://example.com/a.jpg', suffix), 'https://example.com/a.jpg');
    const sized = 'https://i1.hdslb.com/bfs/archive/a.jpg@100w.webp';
    expect(suffixedImageUrl(sized, suffix), sized);
  });

  testWidgets('a picture aligned off the centre is asked whole by its width and drawn there; the centre keeps the crop', (
    tester,
  ) async {
    const long = 'https://i1.hdslb.com/bfs/new_dyn/long.jpg';
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(devicePixelRatio: 3),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 240, height: 319, child: RemoteImage(long, alignment: Alignment.topCenter)),
              SizedBox(width: 240, height: 319, child: RemoteImage(long)),
            ],
          ),
        ),
      ),
    );
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect([for (final image in images) (image.image as StoredNetworkImage).url], [
      widthImageUrl(long, width: 720),
      sizedImageUrl(long, width: 720, height: 960),
    ]);
    expect(widthImageUrl(long, width: 720), '$long@720w.webp');
    expect([for (final image in images) image.alignment], [Alignment.topCenter, Alignment.center]);
    final whole = images.first.image as StoredNetworkImage;
    expect(whole.box, const Size(720, 957), reason: 'kept at the box in device pixels');
    expect(whole.alignment, Alignment.topCenter);
    expect(whole.centreFallback, sizedImageUrl(long, width: 720, height: 960));
    expect((images.last.image as StoredNetworkImage).box, isNull);
  });

  test('a picture kept in part keeps what covering its box shows there, and is keyed by its box', () {
    const box = Size(720, 957);
    expect(StoredNetworkImage.shownPart(720, 16000, box, Alignment.topCenter), const Rect.fromLTWH(0, 0, 720, 957));
    expect(
      StoredNetworkImage.shownPart(720, 16000, box, Alignment.bottomCenter),
      const Rect.fromLTWH(0, 16000 - 957, 720, 957),
    );
    expect(
      StoredNetworkImage.shownPart(500, 10000, box, Alignment.topCenter),
      const Rect.fromLTWH(0, 0, 500, 665),
      reason: 'an answer narrower than the box is kept at its own scale',
    );
    expect(StoredNetworkImage.shownPart(720, 960, box, Alignment.topCenter), const Rect.fromLTWH(0, 0, 720, 957));
    expect(StoredNetworkImage.shownPart(1, 1, box, Alignment.topCenter), const Rect.fromLTWH(0, 0, 1, 1));

    const url = 'https://i1.hdslb.com/bfs/new_dyn/long.jpg@720w.webp';
    const kept = StoredNetworkImage(url, box: box, alignment: Alignment.topCenter);
    expect(kept, const StoredNetworkImage(url, box: box, alignment: Alignment.topCenter));
    expect(kept, isNot(const StoredNetworkImage(url, box: Size(720, 960), alignment: Alignment.topCenter)));
    expect(kept, isNot(const StoredNetworkImage(url, box: box)));
    expect(kept, isNot(const StoredNetworkImage(url, box: box, alignment: Alignment.bottomCenter)));
  });

  test("i0's and i2's pictures are asked from i1, so one connection carries them all; other hosts stay", () {
    expect(PictureSession.host, 'i1.hdslb.com');
    for (final (given, asked) in [
      ('https://i0.hdslb.com/bfs/archive/a.jpg', 'https://i1.hdslb.com/bfs/archive/a.jpg'),
      ('http://i2.hdslb.com/bfs/face/b.jpg', 'https://i1.hdslb.com/bfs/face/b.jpg'),
      ('//i0.hdslb.com/bfs/garb/item/c.png', 'https://i1.hdslb.com/bfs/garb/item/c.png'),
      (
        'https://i2.hdslb.com/bfs/archive/d.jpg@672w_378h_1c.webp',
        'https://i1.hdslb.com/bfs/archive/d.jpg@672w_378h_1c.webp',
      ),
      ('https://i0.hdslb.com/bfs/archive/e.jpg?sign=x', 'https://i1.hdslb.com/bfs/archive/e.jpg?sign=x'),
      ('https://i1.hdslb.com/bfs/archive/f.jpg', 'https://i1.hdslb.com/bfs/archive/f.jpg'),
      ('//i1.hdslb.com/bfs/face/f.jpg', 'https://i1.hdslb.com/bfs/face/f.jpg'),
      ('https://i3.hdslb.com/bfs/archive/g.jpg', 'https://i3.hdslb.com/bfs/archive/g.jpg'),
      ('https://s1.hdslb.com/bfs/static/h.png', 'https://s1.hdslb.com/bfs/static/h.png'),
      ('https://archive.biliimg.com/bfs/archive/i.jpg', 'https://archive.biliimg.com/bfs/archive/i.jpg'),
      ('https://i0.hdslb.com.example.com/j.jpg', 'https://i0.hdslb.com.example.com/j.jpg'),
      ('https://example.com/i0.hdslb.com/k.jpg', 'https://example.com/i0.hdslb.com/k.jpg'),
    ]) {
      expect(secureImageUrl(given), asked, reason: given);
    }
    const suffix = '@120w_120h_1c.webp';
    expect(suffixedImageUrl('//i0.hdslb.com/bfs/face/a.jpg', suffix), 'https://i1.hdslb.com/bfs/face/a.jpg$suffix');
    expect(
      sizedImageUrl('http://i2.hdslb.com/bfs/archive/a.jpg', width: 660, height: 480),
      'https://i1.hdslb.com/bfs/archive/a.jpg@660w_480h_1c.webp',
    );
    const suffixed = 'https://i2.hdslb.com/bfs/archive/a.jpg@100w.webp';
    expect(suffixedImageUrl(suffixed, suffix), 'https://i1.hdslb.com/bfs/archive/a.jpg@100w.webp');
  });

  group('a picture shown once', () {
    late _GifClient client;

    /// The test's downloads answered by [client]; the provider is put back before the test ends, as the binding checks.
    void testPicture(String description, Future<void> Function(WidgetTester tester) body) =>
        testWidgets(description, (tester) async {
          client = _GifClient();
          debugNetworkImageHttpClientProvider = () => client;
          try {
            await body(tester);
          } finally {
            debugNetworkImageHttpClientProvider = null;
          }
        });

    Future<void> show(WidgetTester tester, Widget image, {bool ticking = true}) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: ticking,
          child: Center(child: SizedBox.square(dimension: 40, child: image)),
        ),
      ),
    );

    final picture = find.descendant(of: find.byType(AnimatedOpacity), matching: find.byType(RawImage));

    double opacity(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find.descendant(of: find.byType(AnimatedOpacity), matching: find.byType(FadeTransition)),
        )
        .opacity
        .value;

    /// Lets the download and decode run, then the fade.
    Future<void> arrive(WidgetTester tester) async {
      for (var i = 0; i < 15; i++) {
        // Decoding runs on the engine's real clock.
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    ui.Image? painted(WidgetTester tester) => tester.widget<RawImage>(picture).image;

    /// Its page covered (TickerMode off) while the memory cache lets it go, then shown again, the download held.
    Future<Completer<void>> comeBack(WidgetTester tester, Widget image) async {
      await show(tester, image, ticking: false);
      PaintingBinding.instance.imageCache.clear();
      final release = Completer<void>();
      client.hold = release.future;
      await show(tester, image);
      expect(client.asked, hasLength(2), reason: 'the Image asked for it again');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return release;
    }

    testPicture('stays painted at full opacity while it reloads', (tester) async {
      const image = RemoteImage('https://i0.hdslb.com/bfs/archive/back.jpg');
      await show(tester, image);
      await arrive(tester);
      expect(opacity(tester), 1);
      final first = painted(tester)!;

      final release = await comeBack(tester, image);
      expect(opacity(tester), 1);
      expect(painted(tester)?.isCloneOf(first), isTrue, reason: 'gapless playback paints the old frame');

      release.complete();
      await arrive(tester);
      expect(opacity(tester), 1);
      expect(painted(tester)?.isCloneOf(first), isFalse, reason: 'the new download is in');
      expect(client.asked, hasLength(2));
    });

    testPicture('an avatar keeps its face through a reload, with no default face coming back', (tester) async {
      const image = RemoteImage.avatar('https://i0.hdslb.com/bfs/face/back.jpg');
      final defaultFace = find.byKey(const ValueKey('default-avatar'));
      await show(tester, image);
      expect(defaultFace, findsOneWidget);
      await arrive(tester);
      expect(defaultFace, findsNothing);
      expect(opacity(tester), 1);
      final first = painted(tester)!;

      final release = await comeBack(tester, image);
      expect(defaultFace, findsNothing);
      expect(opacity(tester), 1);
      expect(painted(tester)?.isCloneOf(first), isTrue);

      release.complete();
      await arrive(tester);
      expect(defaultFace, findsNothing);
      expect(opacity(tester), 1);
      expect(painted(tester)?.isCloneOf(first), isFalse);
    });

    testPicture('an avatar first shown at once from the memory cache brings no default face back on a reload', (
      tester,
    ) async {
      const image = RemoteImage.avatar('https://i0.hdslb.com/bfs/face/again.jpg');
      final defaultFace = find.byKey(const ValueKey('default-avatar'));
      await show(tester, image);
      await arrive(tester);
      await show(tester, const SizedBox());
      await show(tester, image);
      expect(client.asked, hasLength(1), reason: 'shown again from memory, not downloaded');
      expect(defaultFace, findsNothing);

      final release = await comeBack(tester, image);
      expect(defaultFace, findsNothing);
      expect(opacity(tester), 1);
      release.complete();
      await arrive(tester);
      expect(defaultFace, findsNothing);
    });

    testPicture('an avatar given a new address shows the default face until the new face is in', (tester) async {
      final defaultFace = find.byKey(const ValueKey('default-avatar'));
      await show(tester, const RemoteImage.avatar('https://i0.hdslb.com/bfs/face/before.jpg'));
      await arrive(tester);
      expect(defaultFace, findsNothing);

      final release = Completer<void>();
      client.hold = release.future;
      await show(tester, const RemoteImage.avatar('https://i0.hdslb.com/bfs/face/after.jpg'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(defaultFace, findsOneWidget);
      expect(opacity(tester), 0);

      release.complete();
      await arrive(tester);
      expect(defaultFace, findsNothing);
      expect(opacity(tester), 1);
      expect(client.asked, hasLength(2));
    });

    testPicture('a new address still fades in', (tester) async {
      await show(tester, const RemoteImage('https://i0.hdslb.com/bfs/archive/first.jpg'));
      await arrive(tester);
      expect(opacity(tester), 1);

      final release = Completer<void>();
      client.hold = release.future;
      await show(tester, const RemoteImage('https://i0.hdslb.com/bfs/archive/second.jpg'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity(tester), 0);

      release.complete();
      await arrive(tester);
      expect(opacity(tester), 1);
    });
  });
}
