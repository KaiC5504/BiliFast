import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/skin/svga/svga_loader.dart';
import 'package:bilifast/skin/svga/svga_painter.dart';
import 'package:bilifast/skin/svga_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'svga_fixtures.dart';

const fallbackText = 'still';

late Directory folder;
var _names = 0;

/// A movie file at 10 fps, [frames] long, one sprite drawn on every frame.
File movieFile({int frames = 5, int fps = 10}) {
  final file = File('${folder.path}/movie_${_names++}.svga');
  file.writeAsBytesSync(
    movie2(
      width: 20,
      height: 10,
      fps: fps,
      frames: frames,
      images: {'pic': png(2, 2, 0xFFFF0000)},
      sprites: [
        sprite2('pic', [
          for (var i = 0; i < frames; i++) frame2(alpha: 1, layout: [i.toDouble(), 0, 2, 2]),
        ]),
      ],
    ),
  );
  return file;
}

Future<void> decoded(WidgetTester tester, File file) => tester.runAsync(() async {
  await SvgaLoader.shared.load(file);
});

Widget host(SvgaView view, {bool ticking = true}) => Directionality(
  textDirection: TextDirection.ltr,
  child: TickerMode(
    enabled: ticking,
    child: Center(child: SizedBox(width: 40, height: 20, child: view)),
  ),
);

SvgaView view(File file, {bool play = true, bool loop = false, BoxFit fit = BoxFit.contain}) =>
    SvgaView(file: file, play: play, loop: loop, fit: fit, fallback: const Text(fallbackText));

SvgaPainter? painter(WidgetTester tester) {
  final paints = find.descendant(of: find.byType(SvgaView), matching: find.byType(CustomPaint));
  if (paints.evaluate().isEmpty) return null;
  return tester.widget<CustomPaint>(paints).painter as SvgaPainter?;
}

int frameOf(WidgetTester tester) => painter(tester)!.frame.value;

void main() {
  setUpAll(() => folder = Directory.systemTemp.createTempSync('svga_view'));
  tearDownAll(() => folder.deleteSync(recursive: true));

  testWidgets('shows the fallback while it decodes, then the movie', (tester) async {
    final file = movieFile();
    await tester.runAsync(() async {
      await tester.pumpWidget(host(view(file, play: false)));
      expect(find.text(fallbackText), findsOneWidget);
      expect(painter(tester), isNull);
      await SvgaLoader.shared.load(file);
    });
    await tester.pump();
    expect(find.text(fallbackText), findsNothing);
    expect(frameOf(tester), 0);
    expect(painter(tester)!.fit, BoxFit.contain);
    expect(tester.getSize(find.byType(CustomPaint).last), const Size(40, 20));
  });

  testWidgets('a decoded file draws at once when built again', (tester) async {
    final file = movieFile();
    await decoded(tester, file);
    await tester.pumpWidget(host(view(file, play: false, fit: BoxFit.cover)));
    expect(find.text(fallbackText), findsNothing);
    expect(painter(tester)!.fit, BoxFit.cover);
  });

  group('a file it can\'t read shows the fallback and is logged once', () {
    late MemorySink logs;

    setUp(() {
      logs = MemorySink();
      Logger.shared.add(logs);
    });
    tearDown(() => Logger.shared.remove(logs));

    testWidgets('corrupt', (tester) async {
      final file = File('${folder.path}/corrupt.svga')..writeAsBytesSync(List.generate(200, (i) => i * 31 % 256));
      await decoded(tester, file);
      await tester.pumpWidget(host(view(file)));
      await tester.pumpWidget(host(SvgaView(key: UniqueKey(), file: file, play: true)));
      expect(find.byType(CustomPaint), findsNothing);
      await tester.pumpWidget(host(view(file)));
      expect(find.text(fallbackText), findsOneWidget);
      final logged = logs.events.where((event) => event.msg == 'svga unreadable').toList();
      expect(logged, hasLength(1));
      expect(logged.single.f['file']?.toJson(), 'corrupt.svga');
    });

    testWidgets('missing', (tester) async {
      final file = File('${folder.path}/missing.svga');
      await tester.pumpWidget(host(view(file)));
      await tester.pumpWidget(host(view(file, play: false)));
      expect(find.text(fallbackText), findsOneWidget);
      expect(logs.events.where((event) => event.msg == 'svga unreadable'), hasLength(1));
    });
  });

  testWidgets('stopped, it shows the first frame and asks for no frames', (tester) async {
    final file = movieFile();
    await decoded(tester, file);
    await tester.pumpWidget(host(view(file, play: false)));
    await tester.pump(const Duration(seconds: 1));
    expect(frameOf(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('playing once, it moves a frame every 1/fps and holds the last', (tester) async {
    final file = movieFile();
    await decoded(tester, file);
    await tester.pumpWidget(host(view(file)));
    await tester.pump();
    expect(frameOf(tester), 0);
    await tester.pump(const Duration(milliseconds: 90));
    expect(frameOf(tester), 0);
    await tester.pump(const Duration(milliseconds: 10));
    expect(frameOf(tester), 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(frameOf(tester), 2);
    await tester.pump(const Duration(milliseconds: 250));
    expect(frameOf(tester), 4);
    await tester.pump(const Duration(milliseconds: 500));
    expect(frameOf(tester), 4);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'done, the ticker stops');
  });

  testWidgets('the movie\'s own fps sets the pace', (tester) async {
    final file = movieFile(fps: 30, frames: 60);
    await decoded(tester, file);
    await tester.pumpWidget(host(view(file)));
    await tester.pump();
    // Vsync timestamps: a frame's time a microsecond early still shows it.
    await tester.pump(const Duration(microseconds: 33333));
    expect(frameOf(tester), 1);
    await tester.pump(const Duration(microseconds: 966667));
    expect(frameOf(tester), 30);
  });

  testWidgets('looping, it goes round from the last frame to the first', (tester) async {
    final file = movieFile();
    await decoded(tester, file);
    await tester.pumpWidget(host(view(file, loop: true)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(frameOf(tester), 4);
    await tester.pump(const Duration(milliseconds: 100));
    expect(frameOf(tester), 0);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(frameOf(tester), 2);
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('turning play off shows the first frame; on again starts over', (tester) async {
    final file = movieFile();
    await decoded(tester, file);
    await tester.pumpWidget(host(view(file)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(frameOf(tester), 4);

    await tester.pumpWidget(host(view(file, play: false)));
    expect(frameOf(tester), 0);
    await tester.pumpWidget(host(view(file)));
    await tester.pump();
    expect(frameOf(tester), 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(frameOf(tester), 2);

    await tester.pumpWidget(host(view(file, play: false)));
    await tester.pumpWidget(host(view(file)));
    await tester.pump();
    expect(frameOf(tester), 0, reason: 'mid-run too, it starts from the first frame');
  });

  testWidgets('a muted TickerMode holds the frame; unmuted, it goes on from there', (tester) async {
    final file = movieFile();
    await decoded(tester, file);
    await tester.pumpWidget(host(view(file)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(frameOf(tester), 2);

    await tester.pumpWidget(host(view(file), ticking: false));
    await tester.pump(const Duration(seconds: 2));
    expect(frameOf(tester), 2);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(host(view(file)));
    await tester.pump();
    expect(frameOf(tester), 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(frameOf(tester), 3);
  });

  testWidgets('built under a muted TickerMode it waits on the first frame', (tester) async {
    final file = movieFile();
    await decoded(tester, file);
    await tester.pumpWidget(host(view(file), ticking: false));
    await tester.pump(const Duration(seconds: 1));
    expect(frameOf(tester), 0);
    await tester.pumpWidget(host(view(file)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(frameOf(tester), 1);
  });

  testWidgets('another file shows its movie from the first frame', (tester) async {
    final first = movieFile();
    final second = movieFile(frames: 3);
    await decoded(tester, first);
    await decoded(tester, second);
    await tester.pumpWidget(host(view(first, loop: true)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(frameOf(tester), 3);
    final before = painter(tester)!.composition;

    await tester.pumpWidget(host(view(second, loop: true)));
    expect(painter(tester)!.composition, isNot(same(before)));
    expect(painter(tester)!.composition.movie.frames, 3);
    await tester.pump();
    expect(frameOf(tester), 0);
  });

  testWidgets('the file rewritten is decoded again', (tester) async {
    final file = movieFile();
    await decoded(tester, file);
    await tester.pumpWidget(host(view(file, play: false)));
    final before = painter(tester)!.composition;

    file.writeAsBytesSync(
      movie2(
        width: 20,
        height: 10,
        frames: 2,
        sprites: [
          sprite2('x', [frame2()]),
        ],
      ),
    );
    file.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    await decoded(tester, file);
    await tester.pumpWidget(host(view(File(file.path), play: false)));
    expect(painter(tester)!.composition, isNot(same(before)));
    expect(painter(tester)!.composition.movie.frames, 2);
  });
}
