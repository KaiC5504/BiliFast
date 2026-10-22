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
    Object? failure;

    setUp(() {
      answers = [];
      downloads = 0;
      failure = null;
    });

    tearDown(() => ImageDiskCache.shared = null);

    Future<void> keep(WidgetTester tester) => tester.runAsync(() async {
      folder = await Directory.systemTemp.createTemp('remote_image');
      cache = ImageDiskCache(
        folder: folder.path,
        fetch: (_, _) async {
          downloads++;
          if (failure case final failure?) throw failure;
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
        expect(await tester.runAsync(() => RemoteImage.precache(context, refused, const Size(160, 100))), isFalse);
      }
      expect(downloads, 2);
      final warning = logs.events.where((event) => event.msg == 'image failed').single;
      expect(warning.f['host']?.toJson(), 'i3.hdslb.com');
      expect(warning.f['status']?.toJson(), 403);
      expect('${warning.f['path']?.toJson()}', startsWith('/bfs/archive/refused.jpg@'));
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
