import 'dart:io';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/skin/svga/svga_loader.dart';
import 'package:bilifast/skin/svga_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'svga_fixtures.dart';

/// Passes the decoder's PNG check by its signature, then fails to decode.
final broken = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4]);

void main() {
  late Directory folder;
  late MemorySink logs;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('svga_loader');
    logs = MemorySink();
    Logger.shared.add(logs);
  });
  tearDown(() {
    Logger.shared.remove(logs);
    folder.deleteSync(recursive: true);
  });

  File movieFile(String name, Map<String, List<int>> images) => File('${folder.path}/$name')
    ..writeAsBytesSync(
      movie2(
        width: 20,
        height: 10,
        frames: 2,
        images: images,
        sprites: [
          for (final key in images.keys)
            sprite2(key, [
              frame2(alpha: 1, layout: [0, 0, 2, 2]),
            ]),
        ],
      ),
    );

  Iterable<LogEvent> logged(String message) => logs.events.where((event) => event.msg == message);

  testWidgets('a picture that fails to decode costs only its sprite, logged once by its key', (tester) async {
    final file = movieFile('one_bad.svga', {'good': png(2, 2, 0xFFFF0000), 'bad': broken});
    final loader = SvgaLoader();
    final composition = await tester.runAsync(() async => loader.load(file));
    expect(composition, isNotNull);
    expect(composition!.images.keys, ['good']);
    await tester.runAsync(() async => loader.load(file));

    final event = logged('svga picture unreadable').single;
    expect(event.f['file'], const LogString('one_bad.svga'));
    expect(event.f['sprite'], const LogString('bad'));
    expect((event.f['error']! as LogString).value, isNotEmpty);
    expect(logs.events.map((event) => event.encode()).join('\n'), isNot(contains('svga_loader')), reason: 'no path');
    expect(logged('svga unreadable'), isEmpty);
  });

  testWidgets('a movie none of whose pictures decode loads as nothing, so the fallback shows', (tester) async {
    final file = movieFile('all_bad.svga', {'a': broken, 'b': broken});
    expect(await tester.runAsync(() async => SvgaLoader().load(file)), isNull);
    expect(logged('svga unreadable').single.f['error'], const LogString('no picture decodes'));
    expect(logged('svga picture unreadable'), hasLength(2));

    await tester.runAsync(() async => SvgaLoader.shared.load(file));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SvgaView(file: file, play: false, fallback: const Text('still')),
      ),
    );
    expect(find.text('still'), findsOneWidget);
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('a bug in the decode goes to the crash log with its stack, and the movie loads as nothing', (
    tester,
  ) async {
    final file = movieFile('bug.svga', {'a': png(2, 2, 0xFFFF0000)});
    final loader = SvgaLoader(read: (path) async => throw StateError('a bug'));
    expect(await tester.runAsync(() async => loader.load(file)), isNull);

    final crash = logged('crash').first;
    expect(crash.f['source'], const LogString('svga decode'));
    expect(crash.f['file'], const LogString('bug.svga'));
    expect(crash.f['error'], const LogString('Bad state: a bug'));
    expect((crash.f['stack']! as LogString).value, isNotEmpty);
    expect(logged('svga unreadable'), isEmpty);
  });
}
