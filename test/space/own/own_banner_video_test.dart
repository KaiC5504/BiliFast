import 'dart:io';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/skin/skin_video.dart';
import 'package:bilifast/space/own/own_banner_video.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = 'https://i0.hdslb.com/bfs/garb/made-up/banner.mp4?made=up';
const _other = 'https://i0.hdslb.com/bfs/garb/made-up/other.mp4';

void main() {
  late Directory folder;
  late List<Uri> fetched;
  Object? failure;

  /// A fresh folder; file work runs on the real clock, as the app's does.
  Future<void> prepare(WidgetTester tester) async {
    final made = folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('own_banner_video')))!;
    addTearDown(() => made.deleteSync(recursive: true));
    fetched = [];
    failure = null;
  }

  OwnBannerVideos store() => OwnBannerVideos(
    folder: '${folder.path}${Platform.pathSeparator}space_banner',
    fetch: (url) async {
      fetched.add(url);
      if (failure case final error?) throw error;
      return Uint8List.fromList([0, 0, 0, 24, ...'ftypmp42'.codeUnits]);
    },
  );

  group('the video file', () {
    testWidgets('is downloaded once and kept by its address\'s hash', (tester) async {
      await prepare(tester);
      await tester.runAsync(() async {
        final videos = store();
        final file = (await videos.file(_video))!;
        expect(await file.length(), 12);
        expect(file.path, isNot(contains('banner.mp4')), reason: 'the address never names the file');
        expect(await videos.file(_video), isNotNull);
        expect(await store().file(_video), isNotNull, reason: 'a later page finds it on disk');
      });
      expect(fetched, [Uri.parse(_video.replaceFirst('i0.', 'i1.'))], reason: 'asked from i1, as pictures are');
    });

    testWidgets('a new one replaces the old', (tester) async {
      await prepare(tester);
      await tester.runAsync(() async {
        final videos = store();
        final first = (await videos.file(_video))!;
        final second = (await videos.file(_other))!;
        expect(await first.exists(), isFalse);
        expect(await second.exists(), isTrue);
        expect(Directory(videos.folder).listSync(), hasLength(1));
      });
    });

    testWidgets('a failed download is null and logged without the address', (tester) async {
      await prepare(tester);
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      failure = const SocketException('made up');
      expect(await tester.runAsync(() => store().file(_video)), isNull);
      final lines = logs.events.where((event) => event.msg == 'own space banner video failed').toList();
      expect(lines, hasLength(1));
      expect(lines.single.encode(), isNot(contains('made-up')));
    });
  });

  group('the video', () {
    Future<void> show(
      WidgetTester tester,
      double alignY, {
      ({int width, int height})? size = (width: 1080, height: 1620),
    }) async {
      await prepare(tester);
      final videos = store();
      await tester.runAsync(() => videos.file(_video));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 440,
              height: 295,
              child: OwnBannerVideo(
                url: _video,
                size: size,
                alignY: alignY,
                still: const ColoredBox(key: ValueKey('still'), color: Color(0xFF000000)),
                videos: videos,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    testWidgets('loops over the still, covering the box, cut about the crop', (tester) async {
      await show(tester, -1);
      expect(find.byKey(const ValueKey('still')), findsOneWidget);
      final video = tester.widget<SkinVideo>(find.byType(SkinVideo));
      expect(video.loop, isTrue);
      // 1080 × 1620 across 440 is 660 tall.
      expect(tester.getRect(find.byType(SkinVideo)), const Rect.fromLTWH(0, 0, 440, 660));
      await show(tester, 0);
      expect(tester.getRect(find.byType(SkinVideo)), const Rect.fromLTWH(0, (295 - 660) / 2, 440, 660));
      await show(tester, 1);
      expect(tester.getRect(find.byType(SkinVideo)), const Rect.fromLTWH(0, 295 - 660, 440, 660));
    });

    testWidgets('without its size it fills the box', (tester) async {
      await show(tester, -1, size: null);
      expect(tester.getRect(find.byType(SkinVideo)), const Rect.fromLTWH(0, 0, 440, 295));
    });
  });
}
