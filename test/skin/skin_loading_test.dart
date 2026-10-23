import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/fake_skin_api.dart';
import 'package:bilifast/skin/skin_loading.dart';
import 'package:bilifast/skin/skin_loading_view.dart';
import 'package:bilifast/skin/skin_package.dart';
import 'package:bilifast/skin/stand_in_gif.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'skin_loading_fixtures.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = const Color(0xFF336699));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Uint8List _zip(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final MapEntry(key: name, value: bytes) in entries.entries) {
    archive.add(ArchiveFile.bytes(name, bytes));
  }
  return ZipEncoder().encodeBytes(archive, modified: DateTime(2026, 10, 23));
}

/// A PNG's signature, its header and one more chunk of [type], enough for the format check.
Uint8List _pngWith(String type) => Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 13, ...'IHDR'.codeUnits, ...List.filled(13, 0), 0, 0, 0, 0,
  0, 0, 0, 8, ...type.codeUnits, ...List.filled(8, 0), 0, 0, 0, 0,
]);

/// The frames' pixels as RGBA, to tell them apart.
Future<Uint8List> _pixels(ui.Image image) async {
  final data = await image.toByteData();
  return data!.buffer.asUint8List();
}

void main() {
  group('the format, by the first bytes', () {
    test('gif, png, apng, webp, jpeg, zip and anything else', () {
      expect(skinLoadingFormat(DemoSkin.loadingGif()), SkinLoadingFormat.gif);
      expect(skinLoadingFormat(Uint8List.fromList('GIF87a'.codeUnits)), SkinLoadingFormat.gif);
      expect(skinLoadingFormat(_pngWith('IDAT')), SkinLoadingFormat.png);
      expect(skinLoadingFormat(_pngWith('acTL')), SkinLoadingFormat.apng);
      expect(
        skinLoadingFormat(Uint8List.fromList([...'RIFF'.codeUnits, 9, 9, 9, 9, ...'WEBP'.codeUnits])),
        SkinLoadingFormat.webp,
      );
      expect(
        skinLoadingFormat(Uint8List.fromList([...'RIFF'.codeUnits, 9, 9, 9, 9, ...'WAVE'.codeUnits])),
        SkinLoadingFormat.unknown,
      );
      expect(skinLoadingFormat(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), SkinLoadingFormat.jpeg);
      expect(skinLoadingFormat(_zip({'a.gif': DemoSkin.loadingGif()})), SkinLoadingFormat.zip);
      expect(skinLoadingFormat(Uint8List.fromList([1, 2, 3])), SkinLoadingFormat.unknown);
      expect(skinLoadingFormat(Uint8List(0)), SkinLoadingFormat.unknown);
    });

    test('a png cut short is a png', () {
      final cut = _pngWith('acTL').sublist(0, 20);
      expect(skinLoadingFormat(cut), SkinLoadingFormat.png);
    });
  });

  group('the check', () {
    test('the stand-in gif decodes: 8 frames of 144 px, the first at its own size', () async {
      final check = await checkSkinLoading(DemoSkin.loadingGif());
      expect(check.refusal, isNull);
      expect(
        (check.format, check.inner, check.frames, check.width, check.height),
        (SkinLoadingFormat.gif, null, 8, 144, 144),
      );
      expect((check.first!.width, check.first!.height), (144, 144));
      final animation = check.animation(id: 2, ver: 3, name: 'n')!;
      expect((animation.key, animation.format, animation.frames), ('2-3', SkinLoadingFormat.gif, 8));
      expect(check.describe(), {'format': 'gif', 'frames': 8, 'width': 144, 'height': 144});
    });

    test('a large picture is decoded at most the box at 3× a side, its shape kept', () async {
      final check = await checkSkinLoading(await _png(1000, 500));
      expect((check.format, check.frames, check.width, check.height), (SkinLoadingFormat.png, 1, 1000, 500));
      expect((check.first!.width, check.first!.height), (SkinLoadingTheme.decodePixels, SkinLoadingTheme.decodePixels ~/ 2));
    });

    test("a zip's first picture is taken out", () async {
      final gif = DemoSkin.loadingGif();
      final check = await checkSkinLoading(_zip({'readme.txt': 'hello'.codeUnits, 'loading.gif': gif}));
      expect((check.format, check.inner, check.frames), (SkinLoadingFormat.zip, SkinLoadingFormat.gif, 8));
      expect(check.picture, gif);
      expect(check.animation(id: 1, ver: 1, name: '')!.format, SkinLoadingFormat.gif);
      expect(check.describe()['inner'], 'gif');
    });

    test('what can not be drawn is refused with the reason', () async {
      Future<String?> refusal(List<int> bytes) async => (await checkSkinLoading(Uint8List.fromList(bytes))).refusal;
      expect(await refusal([1, 2, 3]), 'not a picture that decodes');
      expect(await refusal(_zip({'readme.txt': 'hello'.codeUnits})), 'no picture in the zip');
      expect(await refusal([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]), anyOf('zip unreadable', 'no picture in the zip'));
      expect(await refusal(DemoSkin.loadingGif().sublist(0, 40)), isNotNull);
      expect(await refusal(await _png(SkinLimits.loadingSide + 1, 1)), 'too large a picture');
      final refused = await checkSkinLoading(Uint8List.fromList([1, 2, 3]));
      expect(refused.animation(id: 1, ver: 1, name: ''), isNull);
      expect(refused.describe(), {'format': 'unknown', 'fallback': 'not a picture that decodes'});
    });

    test('the stand-in writer gives each frame its delay and keeps index 0 transparent', () async {
      final gif = encodeStandInGif(
        width: 2,
        height: 2,
        frames: [
          Uint8List.fromList([1, 2, 3, 0]),
          Uint8List.fromList([0, 3, 2, 1]),
        ],
        palette: const [0, 0xFF0000, 0x00FF00, 0x0000FF],
        delay: const Duration(milliseconds: 70),
      );
      final codec = await ui.instantiateImageCodec(gif);
      expect(codec.frameCount, 2);
      final first = await codec.getNextFrame();
      expect(first.duration, const Duration(milliseconds: 70));
      final pixels = await _pixels(first.image);
      expect(pixels.sublist(0, 4), [255, 0, 0, 255]);
      expect(pixels.sublist(12, 16), [0, 0, 0, 0], reason: 'index 0 is transparent');
      first.image.dispose();
      codec.dispose();
    });
  });

  group('the view', () {
    Widget host(Widget child, {bool still = false, bool ticking = true}) => MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: TickerMode(
        enabled: ticking,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: child),
        ),
      ),
    );

    ui.Image shown(WidgetTester tester) => tester.widget<RawImage>(find.byKey(const ValueKey('skin-loading'))).image!;

    /// Lets the codec answer outside the fake clock and builds, a round for each of its steps.
    Future<void> decode(WidgetTester tester) async {
      for (var round = 0; round < 3; round++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    /// The next frame: its time on the fake clock, then its decode.
    Future<void> step(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 100));
      await decode(tester);
    }

    testWidgets('held, it shows its first frame, contained in its box', (tester) async {
      final animation = await standInLoading(tester);
      await tester.pumpWidget(host(SkinLoadingView(animation: animation, playing: false)));
      await decode(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(identical(shown(tester), animation.first), isTrue);
      expect(tester.getSize(find.byType(SkinLoadingView)), const Size.square(SkinLoadingTheme.size));
      expect(tester.widget<RawImage>(find.byType(RawImage)).fit, BoxFit.contain);
      expect(find.bySemanticsLabel('加载中'), findsOneWidget);
    });

    testWidgets('playing, it steps through its frames by their times and loops past the last', (tester) async {
      final animation = await standInLoading(tester);
      await tester.pumpWidget(host(SkinLoadingView(animation: animation)));
      await decode(tester);
      expect(identical(shown(tester), animation.first), isTrue, reason: 'the first frame for its own time');
      final first = (await tester.runAsync(() => _pixels(animation.first)))!;
      final seen = <ui.Image>[];
      final drawn = <Uint8List>[];
      for (var frame = 0; frame < animation.frames + 2; frame++) {
        await step(tester);
        final image = shown(tester);
        expect(identical(image, animation.first), isFalse);
        expect(seen.any((earlier) => identical(earlier, image)), isFalse, reason: 'a new frame each time');
        seen.add(image);
        // Read while shown: the view lets each frame go when the next comes.
        drawn.add((await tester.runAsync(() => _pixels(image)))!);
      }
      for (var frame = 1; frame < drawn.length; frame++) {
        expect(drawn[frame], isNot(drawn[frame - 1]), reason: 'frame $frame moved on');
      }
      expect(drawn[animation.frames - 1], first, reason: 'after the eighth frame the first again');
      expect(drawn[animation.frames], drawn[0], reason: 'and round again');
    });

    testWidgets('held again, it goes back to its first frame and starts from it', (tester) async {
      final animation = await standInLoading(tester);
      await tester.pumpWidget(host(SkinLoadingView(animation: animation)));
      await decode(tester);
      await step(tester);
      await step(tester);
      expect(identical(shown(tester), animation.first), isFalse);
      await tester.pumpWidget(host(SkinLoadingView(animation: animation, playing: false)));
      expect(identical(shown(tester), animation.first), isTrue);
      await tester.pump(const Duration(seconds: 1));
      await decode(tester);
      expect(identical(shown(tester), animation.first), isTrue);
    });

    testWidgets('Reduce Motion and a muted ticker hold the first frame', (tester) async {
      final animation = await standInLoading(tester);
      for (final (still, ticking) in [(true, true), (false, false)]) {
        await tester.pumpWidget(
          host(
            SkinLoadingView(animation: animation),
            still: still,
            ticking: ticking,
          ),
        );
        await decode(tester);
        await step(tester);
        await step(tester);
        expect(identical(shown(tester), animation.first), isTrue, reason: 'still $still, ticking $ticking');
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pumpWidget(host(SkinLoadingView(animation: animation), ticking: false));
      await tester.pumpWidget(host(SkinLoadingView(animation: animation)));
      await decode(tester);
      await step(tester);
      expect(identical(shown(tester), animation.first), isFalse, reason: 'unmuted, it plays');
    });

    testWidgets('a still picture asks for no frames', (tester) async {
      final png = (await tester.runAsync(() => _png(90, 120)))!;
      final check = (await tester.runAsync(() => checkSkinLoading(png)))!;
      final animation = check.animation(id: 1, ver: 1, name: 'still')!;
      await tester.pumpWidget(host(SkinLoadingView(animation: animation)));
      await decode(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(identical(shown(tester), animation.first), isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
