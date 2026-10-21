import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

/// Answers every image request with [_animatedGif]; nothing reaches the network.
final class _GifClient implements HttpClient {
  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _GifRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GifRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => _GifResponse();

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
    return frames;
  }

  testWidgets('an animated picture shows its first frame and asks for no more', (tester) async {
    const url = 'https://i0.hdslb.com/bfs/face/moving.gif@120w_120h_1c.webp';
    debugNetworkImageHttpClientProvider = _GifClient.new;
    try {
      expect(await framesShown(tester, const NetworkImage(url)), greaterThan(1), reason: 'the GIF does move');
      expect(await framesShown(tester, StillNetworkImage(url)), 1);
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  testWidgets('a still picture is not the moving one in the cache', (tester) async {
    const url = 'https://i0.hdslb.com/bfs/archive/a.jpg';
    expect(StillNetworkImage(url), StillNetworkImage(url));
    expect(StillNetworkImage(url), isNot(const NetworkImage(url)));
    expect(const NetworkImage(url), isNot(StillNetworkImage(url)));
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
    expect(providers.map((provider) => provider is StillNetworkImage), [true, true, true, false, false]);
    expect(providers.whereType<NetworkImage>(), hasLength(5), reason: 'all of them are network pictures');
  });
}
