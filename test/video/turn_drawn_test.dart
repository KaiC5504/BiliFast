import 'dart:math' show pi;

import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/turn_style.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderClipRect;
import 'package:flutter_test/flutter_test.dart';

import 'turn_page_harness.dart';

/// The styles of 开发者 → 旋转动画 on the page, and the first frame of a drawn turn on the glass.
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

  group('等截图', () {
    const style = TurnStyle(spinStart: TurnSpinStart.afterPicture);

    testWidgets('holds the first pose until the picture goes, then turns over the whole duration', (tester) async {
      final page = TurnPage();
      await page.open(tester, style: style);
      final id = await page.turnToLandscape(tester);
      final start = tester.getRect(TurnPage.box);
      for (var i = 0; i < 6; i++) {
        await frame(tester);
        expect(TurnPage.angle(tester), closeTo(-pi / 2, 1e-9), reason: 'frame $i holds');
        expect(tester.getRect(TurnPage.box), start, reason: 'frame $i holds');
      }
      expect(page.host.drawnTurns, [id], reason: 'reported drawn, so the host lets its picture go');

      page.host.pictureGone(id + 1);
      await frame(tester);
      expect(TurnPage.angle(tester), closeTo(-pi / 2, 1e-9), reason: "another turn's picture");

      page.host.pictureGone(id);
      await frame(tester);
      await tester.pump(const Duration(milliseconds: 150));
      expect(TurnPage.angle(tester), closeTo(-pi / 4, 0.1), reason: 'halfway through 300 ms');
      await tester.pump(const Duration(milliseconds: 160));
      await frame(tester);
      expect(TurnPage.angle(tester), 0);
      expect(tester.getRect(TurnPage.area), fullBox);
      await page.leave(tester);
    });

    testWidgets('moves anyway once the wait runs out', (tester) async {
      final page = TurnPage();
      await page.open(tester, style: style);
      await page.turnToLandscape(tester);
      await tester.pump(RotationTheme.pictureWait);
      await tester.pump(const Duration(milliseconds: 400));
      expect(TurnPage.angle(tester), 0);

      await page.turnBack(tester);
      await tester.pump(RotationTheme.pictureWait - const Duration(milliseconds: 10));
      expect(TurnPage.angle(tester), closeTo(pi / 2, 1e-9), reason: 'still waiting');
      bool canPop() => tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).last).canPop;
      expect(canPop(), isFalse, reason: 'held, the page is still turning');
      await tester.pump(const Duration(milliseconds: 20));
      await frame(tester);
      await frame(tester);
      final moving = TurnPage.angle(tester);
      expect(moving, allOf(lessThan(pi / 2), greaterThan(pi / 2 - 0.1)), reason: 'from the start of the curve');
      await tester.pump(const Duration(milliseconds: 300));
      await frame(tester);
      expect(TurnPage.angle(tester), 0);
      expect(tester.getRect(TurnPage.area), Rect.fromLTWH(0, 62, 440, 440 / BiliMetrics.videoAspect));
      expect(canPop(), isTrue);
      await page.leave(tester);
    });

    testWidgets('turned back while held, the next turn starts from the held pose, upright on glass', (tester) async {
      final page = TurnPage();
      await page.open(tester, style: style);
      final box0 = tester.getRect(TurnPage.box);
      await page.turnToLandscape(tester);
      await frame(tester);
      final id = await page.turnBack(tester);
      expect(TurnPage.angle(tester), closeTo(0, 1e-9), reason: 'the page never moved on the glass');
      expect(tester.getRect(TurnPage.box), box0);
      await frame(tester);
      page.host.pictureGone(id);
      await frame(tester);
      await tester.pump(const Duration(milliseconds: 320));
      await frame(tester);
      expect(TurnPage.angle(tester), 0);
      expect(tester.getRect(TurnPage.box), box0);
      expect(tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).last).canPop, isTrue);
      await page.leave(tester);
    });

    testWidgets('a picture already gone starts the turn at once', (tester) async {
      final page = TurnPage();
      await page.open(tester, style: style);
      page.orientation.enterLandscape();
      await tester.pump();
      final id = page.host.startTurn(pi / 2, duration: const Duration(milliseconds: 300));
      page.host.pictureGone(id);
      await tester.pump();
      page.screen(tester, landscape);
      await tester.pump();
      expect(TurnPage.angle(tester), closeTo(-pi / 2, 1e-9));
      await frame(tester);
      await frame(tester);
      expect(TurnPage.angle(tester), greaterThan(-pi / 2 + 0.001));
      await tester.pump(const Duration(milliseconds: 400));
      await page.leave(tester);
    });
  });

  testWidgets('不转 draws no rotation and grows the box over the turn from the turned size, the body placed and cut as '
      "in a drawn turn: iOS turns the window as it does the official app's", (tester) async {
    final page = TurnPage();
    await page.open(tester, style: const TurnStyle(method: TurnMethod.noSpin, picture: TurnPicture.none));
    await page.turnToLandscape(tester);
    expect(TurnPage.angle(tester), 0);
    final centre = landscape.center(Offset.zero);
    expect(tester.getRect(TurnPage.box), smallBox.shift(centre - portrait.center(Offset.zero)),
        reason: 'the small player about the centre of the turned screen');
    var width = tester.getRect(TurnPage.box).width;
    for (var i = 0; i < 12; i++) {
      await frame(tester);
      expect(TurnPage.angle(tester), 0, reason: 'frame $i');
      final now = tester.getRect(TurnPage.box);
      expect(now.width, greaterThan(width), reason: 'frame $i grows');
      expect(now.center.dx, closeTo(centre.dx, 1e-6));
      expect(shown(tester, 'page-tab-row').left, now.left, reason: "frame $i: hangs from the box's left");
      width = now.width;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await frame(tester);
    expect(tester.getRect(TurnPage.area), fullBox);
    expect(page.host.drawnTurns, hasLength(1));

    await page.turnBack(tester);
    expect(TurnPage.angle(tester), 0);
    expect(tester.getRect(TurnPage.box), fullBox.shift(portrait.center(Offset.zero) - centre));
    final player = tester.widget<Positioned>(TurnPage.box);
    for (final key in ['page-tab-row', 'page-tabs-area']) {
      expect(shown(tester, key).bottom, lessThanOrEqualTo(player.top! + player.height!),
          reason: '$key: cut off by the window, below the full-screen player');
    }
    await frame(tester);
    await frame(tester);
    expect(TurnPage.angle(tester), 0);
    expect(tester.getRect(TurnPage.box).width, lessThan(fullBox.width));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getRect(TurnPage.area), Rect.fromLTWH(0, 62, 440, 440 / BiliMetrics.videoAspect));
    await page.leave(tester);
  });

  testWidgets('不转 never waits for a picture, whatever drawn start it kept from another method', (tester) async {
    final page = TurnPage();
    await page.open(
      tester,
      style: const TurnStyle(
        method: TurnMethod.noSpin,
        picture: TurnPicture.none,
        spinStart: TurnSpinStart.afterPicture,
      ),
    );
    await page.turnToLandscape(tester);
    final start = tester.getRect(TurnPage.box);
    await frame(tester);
    await frame(tester);
    expect(tester.getRect(TurnPage.box).width, greaterThan(start.width), reason: 'grows from the first frame');
    expect(tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).last).canPop, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    await frame(tester);
    expect(tester.getRect(TurnPage.area), fullBox);
    await page.leave(tester);
  });

  testWidgets('a covered page neither logs the pictures of turns it will not draw nor keeps them for its own',
      (tester) async {
    final logs = MemorySink();
    Logger.shared.add(logs);
    addTearDown(() => Logger.shared.remove(logs));
    Iterable<LogEvent> gone() => logs.events.where((line) => line.msg == 'turn picture gone');
    final page = TurnPage();
    await page.open(tester, style: const TurnStyle(spinStart: TurnSpinStart.afterPicture));
    await page.cover(tester);
    page.host
      ..pictureGone(1)
      ..pictureGone(2);
    await tester.pump();
    expect(gone(), isEmpty);

    await page.uncover(tester);
    final id = await page.turnToLandscape(tester);
    expect(id, 1);
    for (var i = 0; i < 3; i++) {
      await frame(tester);
      expect(TurnPage.angle(tester), closeTo(-pi / 2, 1e-9), reason: 'frame $i: held for its own picture');
    }
    page.host.pictureGone(id);
    await frame(tester);
    expect(gone().map((line) => line.f['turn']), const [LogInt(1)]);
    await tester.pump(const Duration(milliseconds: 400));
    await page.leave(tester);
  });

  testWidgets('the picture styles draw the same turn', (tester) async {
    final angles = <TurnPicture, List<double>>{};
    for (final picture in TurnPicture.values) {
      final page = TurnPage();
      await page.open(tester, style: TurnStyle(picture: picture));
      await page.turnToLandscape(tester);
      angles[picture] = [TurnPage.angle(tester)];
      for (var i = 0; i < 20; i++) {
        await frame(tester);
        angles[picture]!.add(TurnPage.angle(tester));
      }
      await page.leave(tester);
    }
    expect(angles[TurnPicture.fade], angles[TurnPicture.cut]);
    expect(angles[TurnPicture.none], angles[TurnPicture.cut]);
  });
}
