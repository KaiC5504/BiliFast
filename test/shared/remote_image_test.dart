import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1×1 GIF of two frames, 100 ms each, looping forever: a red pixel, then a blue one.
final _animatedGif = Uint8List.fromList([
  ...'GIF89a'.codeUnits,
  0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, // 1×1, a global table of two colours
  0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF,
  0x21, 0xFF, 0x0B, ...'NETSCAPE2.0'.codeUnits, 0x03, 0x01, 0x00, 0x00, 0x00, // loop forever
  for (final pixel in [0x44, 0x4C]) ...[
    0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00, // 100 ms
    0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0x02, 0x02, pixel, 0x01, 0x00, // colour 0, then colour 1
  ],
  0x3B,
]);

/// Answers every image request with [_animatedGif]; nothing reaches the network. While [hold] is pending, answers
/// wait for it.
final class _GifClient implements HttpClient {
  final asked = <Uri>[];
  Future<void>? hold;

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    asked.add(url);
    return _GifRequest(hold);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GifRequest implements HttpClientRequest {
  _GifRequest(this._hold);

  final Future<void>? _hold;

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async {
    await _hold;
    return _GifResponse();
  }

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
  int get contentLength => _animatedGif.length;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(_animatedGif as List<int>)
          .listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

  group('with pictures kept on the phone', () {
    const url = 'https://i0.hdslb.com/bfs/archive/kept.jpg@240w_180h_1c.webp';
    late Directory folder;
    late ImageDiskCache cache;
    late List<Uint8List> answers;
    late int downloads;

    setUp(() {
      answers = [];
      downloads = 0;
    });

    tearDown(() => ImageDiskCache.shared = null);

    Future<void> keep(WidgetTester tester) => tester.runAsync(() async {
      folder = await Directory.systemTemp.createTemp('remote_image');
      cache = ImageDiskCache(
        folder: folder.path,
        fetch: (_, _) async {
          downloads++;
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
      answers.add(_animatedGif);
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

      answers.add(_animatedGif);
      expect(await resolve(tester, const StoredNetworkImage(url)), isA<ImageInfo>());
      expect(downloads, 2);
      await drop(tester);
    });
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
      expect(find.byType(AnimatedOpacity), findsNothing, reason: 'shown at once, with no fade');
      expect(defaultFace, findsNothing);

      final release = await comeBack(tester, image);
      expect(defaultFace, findsNothing);
      expect(opacity(tester), 1);
      release.complete();
      await arrive(tester);
      expect(defaultFace, findsNothing);
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
