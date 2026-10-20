import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderClipRect;
import 'package:flutter_test/flutter_test.dart';

import 'turn_page_harness.dart';

/// The first frame of a drawn turn on the glass, and the turning window that cuts the page's body.
void main() {
  Future<void> frame(WidgetTester tester) => tester.pump(const Duration(milliseconds: 16));

  /// [finder]'s corners on the glass, its surface turned into the upright screen by [interface] radians.
  List<Offset> onGlass(WidgetTester tester, Finder finder, double interface) {
    final surface = tester.view.physicalSize / tester.view.devicePixelRatio;
    final turn = Matrix4.translationValues(portrait.width / 2, portrait.height / 2, 0)
      ..multiply(Matrix4.rotationZ(interface))
      ..multiply(Matrix4.translationValues(-surface.width / 2, -surface.height / 2, 0));
    return [for (final corner in TurnPage.corners(tester, finder)) MatrixUtils.transformPoint(turn, corner)];
  }

  void expectCorners(List<Offset> actual, List<Offset> expected, {required String reason}) {
    for (var i = 0; i < 4; i++) {
      expect(actual[i], offsetMoreOrLessEquals(expected[i], epsilon: 0.01), reason: '$reason, corner $i');
    }
  }

  /// What of a body piece the turning window leaves showing, in the page's coordinates before it is turned; the whole
  /// piece at rest.
  Rect shown(WidgetTester tester, String key) {
    final piece = find.byKey(ValueKey(key));
    final positioned = tester.widget<Positioned>(piece);
    final bounds = Rect.fromLTWH(positioned.left!, positioned.top!, positioned.width!, positioned.height!);
    final clip = tester.renderObject<RenderClipRect>(
      find.descendant(of: piece, matching: find.byType(ClipRect)).first,
    );
    final window = clip.clipper?.getClip(bounds.size).shift(bounds.topLeft);
    return window == null ? bounds : bounds.intersect(window);
  }

  group('the first frame of a drawn turn, turned by the window onto the glass, is the page as it was', () {
    testWidgets('to landscape: the upright page, every piece in place and none cut', (tester) async {
      final page = TurnPage();
      await page.open(tester);
      final pieces = {
        'box': TurnPage.box,
        'area': TurnPage.area,
        'tab row': TurnPage.tabRow,
        'tabs': TurnPage.tabsArea,
      };
      final before = {for (final MapEntry(:key, :value) in pieces.entries) key: onGlass(tester, value, 0)};
      final rowBefore = shown(tester, 'page-tab-row');
      final tabsBefore = shown(tester, 'page-tabs-area');

      await page.turnToLandscape(tester);
      expect(TurnPage.angle(tester), closeTo(-pi / 2, 1e-9));
      for (final MapEntry(:key, :value) in pieces.entries) {
        expectCorners(onGlass(tester, value, pi / 2), before[key]!, reason: key);
      }
      expect(shown(tester, 'page-tab-row').size, rowBefore.size, reason: 'the window cuts nothing yet');
      expect(shown(tester, 'page-tabs-area').size, tabsBefore.size, reason: 'the window cuts nothing yet');
      final backdrop = onGlass(tester, TurnPage.backdrop, pi / 2);
      final cover = Rect.fromPoints(backdrop[0], backdrop[2]);
      expect(cover.contains(Offset.zero) && cover.contains(portrait.bottomRight(Offset.zero)), isTrue);
      await page.leave(tester);
    });

    testWidgets('back: the full-screen player, the body cut off by the window', (tester) async {
      final page = TurnPage();
      await page.open(tester);
      await page.turnToLandscape(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      final box = onGlass(tester, TurnPage.box, pi / 2);
      final area = onGlass(tester, TurnPage.area, pi / 2);

      await page.turnBack(tester);
      expect(TurnPage.angle(tester), closeTo(pi / 2, 1e-9));
      expectCorners(onGlass(tester, TurnPage.box, 0), box, reason: 'box');
      expectCorners(onGlass(tester, TurnPage.area, 0), area, reason: 'area');
      final player = tester.widget<Positioned>(TurnPage.box);
      for (final key in ['page-tab-row', 'page-tabs-area']) {
        expect(shown(tester, key).bottom, lessThanOrEqualTo(player.top! + player.height!),
            reason: '$key: nothing shows below the player, the bottom of the window');
      }
      await page.leave(tester);
    });
  });

  testWidgets('mid-turn the window goes from the upright screen to the landscape one: the box spans it from its top '
      'and the body shows down to its bottom', (tester) async {
    final page = TurnPage();
    await page.open(tester);
    await page.turnToLandscape(tester);
    for (var i = 0; i < 8; i++) {
      await frame(tester);
    }
    final box = tester.widget<Positioned>(TurnPage.box);
    final tabs = shown(tester, 'page-tabs-area');
    expect(tabs.left, box.left);
    expect(tabs.right, box.left! + portrait.width);
    expect(tabs.bottom, closeTo(box.top! + portrait.width + portrait.height - box.width!, 1e-6),
        reason: "the window's height and width add up to the screen's sides");
    expect(tabs.bottom, lessThan(box.top! + portrait.height), reason: 'cut short of the upright page');
    await page.leave(tester);
  });
}
