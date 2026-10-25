import 'package:bili_core/api.dart' show VideoShot;
import 'package:bilifast/player_ui/seek_preview.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

const _sheet = 'https://i0.hdslb.com/bfs/videoshot/a.jpg';

VideoShot _shot({double cellWidth = 160, double cellHeight = 90}) => VideoShot(
  sheets: const [_sheet],
  columns: 10,
  rows: 10,
  times: [for (var i = 0; i <= 100; i++) i],
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
  testWidgets('an upright video\'s frame is 81 × 144 with its border, centred, its bottom at 788 (19)', (tester) async {
    await _mount(tester, upright: true, shot: _shot(cellWidth: 120, cellHeight: 160));
    _expectRect(tester.getRect(_frame), const Rect.fromLTWH(179.5, 644, 81, 144));
    final border = (tester.widget<Container>(_frame).decoration! as BoxDecoration).border! as Border;
    expect(border.top.width, SeekPreviewTheme.border);
    expect(border.top.color, SeekPreviewTheme.borderColor);
  });

  testWidgets('a wide video\'s frame is 144 × 81, on the same bottom (20)', (tester) async {
    await _mount(tester, upright: false, shot: _shot());
    _expectRect(tester.getRect(_frame), const Rect.fromLTWH(148, 707, 144, 81));
  });

  testWidgets('a 3:4 frame fills the 9:16 box, its sides cut evenly', (tester) async {
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

  testWidgets('the time reads 00:06 in white and / 00:31 in grey, 16 pt, its digits from 802 pt', (tester) async {
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

  testWidgets('without frames the time shows alone in its place', (tester) async {
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

  testWidgets('landscape\'s preview is left as it was: the frame over the middle, the time run together', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = FakePlayerSession()
      ..duration.value = 100
      ..seekFrames.value = _shot();
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
    final frame = tester.getRect(_frame);
    expect(frame.size, const Size(170, 95));
    expect(frame.top, 184);
    expect(tester.widget<Text>(_time).textSpan!.toPlainText(), '00:12/01:40');
    expect(tester.widget<Text>(_time).style!.fontSize, SeekPreviewTheme.timeFont);
  });
}
