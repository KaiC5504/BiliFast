import 'dart:math' show pi;

import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'turn_page_harness.dart';

// local/differences/01-official-rotate.mp4, frames 83-101 and 203-220 at 60 fps, its video tracked against an upright
// frame. Each: ms since the turn's start (fitted with RotationTheme.curve over 300 ms), the page's angle on the upright
// glass in degrees, and how far the box has grown from the small player to full screen (from the video's scale). The
// body hangs from the box's bottom-left corner in every frame, to within 2.2 pt. Frame 202 is a one-frame glitch of
// the recording (the video shrunk and upright), so the turn back starts at 203.
const toLandscape = [
  (1.9, 0.00, 0.000), (18.6, 0.72, 0.007), (35.3, 2.59, 0.027), (51.9, 5.61, 0.060), (68.6, 9.79, 0.105),
  (85.3, 15.25, 0.165), (101.9, 21.93, 0.239), (118.6, 29.59, 0.323), (135.3, 37.82, 0.414), (151.9, 46.22, 0.508),
  (168.6, 54.80, 0.603), (185.3, 62.87, 0.693), (201.9, 70.32, 0.777), (218.6, 76.69, 0.848), (235.3, 81.69, 0.905),
  (251.9, 85.58, 0.949), (270.3, 89.25, 0.991), (293.6, 89.93, 0.999), (310.3, 90.00, 1.000),
];
const backUpright = [
  (27.9, 88.55, 0.984), (44.6, 86.05, 0.956), (61.2, 82.39, 0.916), (77.9, 77.45, 0.861), (94.6, 71.22, 0.792),
  (111.2, 64.09, 0.712), (127.9, 56.55, 0.629), (144.6, 47.78, 0.531), (161.2, 39.45, 0.439), (177.9, 30.93, 0.344),
  (194.6, 23.35, 0.260), (211.2, 16.34, 0.182), (227.9, 10.81, 0.120), (244.6, 6.21, 0.069), (261.2, 2.92, 0.032),
  (277.9, 0.92, 0.010), (294.6, 0.00, 0.000), (311.2, 0.00, 0.000),
];

/// The official turn has a 16:10 video in a 16:10 small player; ours is 16:9, so its box is held to the official's
/// progress between our own small player and full screen, about the screen's centre.
const small = Rect.fromLTWH(-220, -478, 440, 62 + 440 / BiliMetrics.videoAspect);
const full = Rect.fromLTWH(-478, -220, 956, 440);
const turnLength = 300.0;

/// The drawn turn, frame by frame, against the official app's: within 2° and 5 pt of it.
void main() {
  /// Where [key]'s piece of the page is laid out before the page is turned, about the screen's centre.
  Rect placed(WidgetTester tester, String key) {
    final piece = tester.widget<Positioned>(find.byKey(ValueKey(key)));
    final centre = (tester.view.physicalSize / tester.view.devicePixelRatio).center(Offset.zero);
    return Rect.fromLTWH(piece.left!, piece.top!, piece.width!, piece.height!).shift(-centre);
  }

  /// [interface] is the angle the system's window sits at on the glass once turned, in degrees.
  Future<void> follow(WidgetTester tester, List<(double, double, double)> official, {required double interface}) async {
    var at = 0.0;
    for (final (ms, angle, grown) in official) {
      await tester.pump(Duration(microseconds: ((ms - at) * 1000).round()));
      at = ms;
      final reason = '$ms ms';
      expect(interface + TurnPage.angle(tester) * 180 / pi, closeTo(angle, 2), reason: reason);
      final box = placed(tester, 'page-player');
      final expected = Rect.lerp(small, full, grown)!;
      for (final (ours, theirs) in [
        (box.left, expected.left),
        (box.top, expected.top),
        (box.right, expected.right),
        (box.bottom, expected.bottom),
      ]) {
        expect(ours, closeTo(theirs, 5), reason: '$reason: $box, not $expected');
      }
      if (ms < turnLength) {
        expect(placed(tester, 'page-tab-row').topLeft, offsetMoreOrLessEquals(box.bottomLeft), reason: reason);
      }
    }
  }

  testWidgets('to landscape full screen', (tester) async {
    final page = TurnPage();
    await page.open(tester);
    await page.turnToLandscape(tester);
    await follow(tester, toLandscape, interface: 90);
    await page.leave(tester);
  });

  testWidgets('back to the small player', (tester) async {
    final page = TurnPage();
    await page.open(tester);
    await page.turnToLandscape(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await page.turnBack(tester);
    await follow(tester, backUpright, interface: 0);
    await page.leave(tester);
  });
}
