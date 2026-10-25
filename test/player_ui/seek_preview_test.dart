import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart' show VideoPage, VideoShot;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/player_ui/seek_preview.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

const _sheet = 'https://i0.hdslb.com/bfs/videoshot/a.jpg';
const _broken = 'https://i0.hdslb.com/bfs/videoshot/broken-1.jpg';

/// A widget test whose sheets never answer, so a frame stays up while its sheet loads (flutter_test's own client fails
/// every request, which drops the frame); a sheet whose name starts with `broken` fails at once.
void testSheets(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    debugNetworkImageHttpClientProvider = _SheetClient.new;
    // Put back inside the test: flutter_test checks it before the tear-downs run.
    try {
      await body(tester);
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });
}

final class _SheetClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) => url.pathSegments.last.startsWith('broken')
      ? Future.error(const SocketException('no network in tests'))
      : Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Logs implements LogSink {
  final events = <LogEvent>[];

  @override
  void receive(LogEvent event) => events.add(event);
}

/// [frames] a second apart, 100 to a sheet.
VideoShot _shot({
  double cellWidth = 160,
  double cellHeight = 90,
  List<String> sheets = const [_sheet],
  int frames = 100,
}) => VideoShot(
  sheets: sheets,
  columns: 10,
  rows: 10,
  times: [for (var i = 0; i <= frames; i++) i],
  cellWidth: cellWidth,
  cellHeight: cellHeight,
);

/// 竖屏's preview over the whole screen of an upright iPhone 17 Pro Max (440 × 956 pt, 34 below), as 19 and 20.
Future<FakePlayerSession> _mount(WidgetTester tester, {required bool upright, VideoShot? shot}) async {
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
  final session = FakePlayerSession()
    ..duration.value = 31
    ..isVertical = upright
    ..seekFrames.value = shot;
  session.scrubbing.value = 6.4;
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [Positioned.fill(child: SeekPreview(session: session, shown: true, upright: true))],
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

void _expectRect(Rect actual, Rect expected) {
  for (final (got, want) in [
    (actual.left, expected.left),
    (actual.top, expected.top),
    (actual.right, expected.right),
    (actual.bottom, expected.bottom),
  ]) {
    expect(got, closeTo(want, 1e-9), reason: '$actual against $expected');
  }
}

Finder get _frame => find.byKey(const ValueKey('seek-preview-frame'));
Finder get _time => find.byKey(const ValueKey('seek-preview-time'));

void main() {
  testSheets('an upright video\'s frame is 81 × 144 with its border, centred, its bottom at 788 (19)', (tester) async {
    await _mount(tester, upright: true, shot: _shot(cellWidth: 120, cellHeight: 160));
    _expectRect(tester.getRect(_frame), const Rect.fromLTWH(179.5, 644, 81, 144));
    final border = (tester.widget<Container>(_frame).decoration! as BoxDecoration).border! as Border;
    expect(border.top.width, SeekPreviewTheme.border);
    expect(border.top.color, SeekPreviewTheme.borderColor);
  });

  testSheets('a wide video\'s frame is 144 × 81, on the same bottom (20)', (tester) async {
    await _mount(tester, upright: false, shot: _shot());
    _expectRect(tester.getRect(_frame), const Rect.fromLTWH(148, 707, 144, 81));
  });

  testSheets('a 3:4 frame fills the 9:16 box, its sides cut evenly', (tester) async {
    await _mount(tester, upright: true, shot: _shot(cellWidth: 120, cellHeight: 160));
    // 6.4 s is frame 5 of the sheet (times[6] is 6 s): column 5, row 0. The 79 × 142 inside takes the cell at 106.5 × 142.
    const cell = Size(106.5, 142);
    final shift = tester
        .widget<Transform>(find.descendant(of: _frame, matching: find.byType(Transform)))
        .transform
        .getTranslation();
    expect(shift.x, closeTo((79 - cell.width) / 2 - 5 * cell.width, 1e-9));
    expect(shift.y, closeTo(0, 1e-9));
    final image = tester.widget<Image>(find.descendant(of: _frame, matching: find.byType(Image)));
    expect((image.width, image.height), (cell.width * 10, cell.height * 10));
    expect(image.image, isA<NetworkImage>().having((image) => image.url, 'url', _sheet));
  });

  testSheets('the time reads 00:06 in white and / 00:31 in grey, 16 pt, its digits from 802 pt', (tester) async {
    await _mount(tester, upright: true, shot: _shot(cellWidth: 120, cellHeight: 160));
    final text = tester.widget<Text>(_time);
    expect(text.textSpan!.toPlainText(), '00:06 / 00:31');
    expect(text.style!.color, SeekPreviewTheme.time);
    expect(text.style!.fontSize, SeekPreviewTheme.uprightTimeFont);
    expect(text.style!.fontWeight, FontWeight.w600);
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((span) => span.text), ['00:06', ' / 00:31']);
    expect(spans.first.style?.color, isNull, reason: 'the line\'s white');
    expect(spans.last.style!.color, SeekPreviewTheme.duration);

    final line = tester.getRect(_time);
    expect(line.center.dx, closeTo(220, 1e-9));
    expect(line.top, closeTo(788 + SeekPreviewTheme.uprightTimeGap, 1e-9));
    expect(line.height, SeekPreviewTheme.uprightTimeFont);
  });

  testSheets('without frames the time shows alone in its place', (tester) async {
    final session = await _mount(tester, upright: true, shot: _shot(cellWidth: 120, cellHeight: 160));
    final withFrame = tester.getRect(_time);

    session.seekFrames.value = null;
    await tester.pump();
    expect(_frame, findsNothing);
    expect(tester.getRect(_time), withFrame);

    // Frames that cannot be cut (no sheets) are as none.
    session.seekFrames.value = const VideoShot(sheets: [], columns: 10, rows: 10, times: [0, 0, 1]);
    await tester.pump();
    expect(_frame, findsNothing);
    expect(tester.getRect(_time), withFrame);
  });

  testSheets('landscape\'s preview is left as it was: the frame over the middle, the time run together', (
    tester,
  ) async {
    await _mountLandscape(tester, _shot());
    final frame = tester.getRect(_frame);
    expect(frame.size, const Size(170, 95));
    expect(frame.top, 184);
    expect(tester.widget<Text>(_time).textSpan!.toPlainText(), '00:12/01:40');
    expect(tester.widget<Text>(_time).style!.fontSize, SeekPreviewTheme.timeFont);
  });

  group('a sheet that fails to load', () {
    late _Logs logs;
    setUp(() {
      logs = _Logs();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
    });

    List<LogEvent> failures() => [
      for (final event in logs.events)
        if (event.msg == 'seek sheet failed') event,
    ];

    testSheets('drops 竖屏\'s frame and keeps the time in its place, and a working part brings it back', (tester) async {
      final session = await _mount(tester, upright: true, shot: _shot(cellWidth: 120, cellHeight: 160));
      final withFrame = tester.getRect(_time);

      session.seekFrames.value = _shot(cellWidth: 120, cellHeight: 160, sheets: const [_broken]);
      await tester.pumpAndSettle();
      expect(_frame, findsNothing);
      expect(tester.getRect(_time), withFrame);

      session.seekFrames.value = _shot(cellWidth: 120, cellHeight: 160);
      await tester.pumpAndSettle();
      expect(_frame, findsOneWidget);
      expect(tester.getRect(_time), withFrame);
    });

    testSheets('drops only the frames on that sheet', (tester) async {
      final session = await _mount(
        tester,
        upright: false,
        shot: _shot(sheets: const ['https://i0.hdslb.com/bfs/videoshot/broken-2.jpg', _sheet], frames: 200),
      );
      expect(_frame, findsNothing, reason: '6.4 s is on the first sheet');
      session.scrubbing.value = 150;
      await tester.pumpAndSettle();
      expect(_frame, findsOneWidget, reason: 'frame 100 is on the second');
    });

    testSheets('drops landscape\'s frame too, the time where it was', (tester) async {
      await _mountLandscape(tester, _shot());
      final withFrame = tester.getRect(_time);
      await tester.pumpWidget(const SizedBox());
      await _mountLandscape(tester, _shot(sheets: const ['https://i0.hdslb.com/bfs/videoshot/broken-3.jpg']));
      expect(_frame, findsNothing);
      expect(tester.getRect(_time), withFrame);
    });

    testSheets('is logged once for the part, by its cid alone, whichever preview finds it', (tester) async {
      const sheets = [
        'https://i0.hdslb.com/bfs/videoshot/broken-4.jpg',
        'https://i0.hdslb.com/bfs/videoshot/broken-5.jpg',
      ];
      final session = await _mount(tester, upright: false, shot: _shot());
      session
        ..part = const VideoPage(cid: 4242, page: 1, part: 'P1', duration: 31)
        ..seekFrames.value = _shot(sheets: sheets, frames: 200);
      session.scrubbing.value = 150;
      await tester.pumpAndSettle();
      expect(_frame, findsNothing);

      // Turned to landscape: another preview over the same part.
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [Positioned.fill(child: SeekPreview(session: session, shown: true))],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_frame, findsNothing);

      final logged = failures();
      expect(logged, hasLength(1));
      expect(logged.single.level, LogLevel.warn);
      expect(logged.single.f, {'cid': const LogInt(4242)});
      expect(logs.events.map((event) => '${event.f}'), everyElement(isNot(contains('hdslb'))));

      session.seekFrames.value = _shot(sheets: const ['https://i0.hdslb.com/bfs/videoshot/broken-6.jpg']);
      await tester.pumpAndSettle();
      expect(failures(), hasLength(2), reason: 'the next part logs its own');
    });
  });
}

/// Landscape's preview at 12 s of 100 on KaiC's iPhone turned (956 × 440 pt).
Future<FakePlayerSession> _mountLandscape(WidgetTester tester, VideoShot shot) async {
  tester.view
    ..physicalSize = const Size(956, 440)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = FakePlayerSession()
    ..duration.value = 100
    ..seekFrames.value = shot;
  session.scrubbing.value = 12;
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [Positioned.fill(child: SeekPreview(session: session, shown: true))],
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}
