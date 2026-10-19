import 'dart:async';

import 'package:bili_core/api.dart' show QualityOption, UgcSeason, VideoCodec, VideoDetail, VideoOwner, VideoStat;
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/more_panel.dart';
import 'package:bilifast/player_ui/panels/panel_glyphs.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/panels/panel_parts.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/action_glyphs.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_player_session.dart';
import '../../support/fake_video_actions.dart';

const landscapeSize = Size(956, 440);
const portraitSize = Size(440, 956);

const _qualities = [
  QualityOption(id: 80, name: '高清 1080P'),
  QualityOption(id: 125, name: '真彩 HDR'),
  QualityOption(id: 120, name: '超清 4K'),
  QualityOption(id: 64, name: '高清 720P'),
];

class Rig {
  Rig(this.session, this.ui, this.below);

  final FakePlayerSession session;
  final PlayerUi ui;

  /// Taps that went through the layer to the page under it.
  final List<int> below;

  PanelController get panels => ui.panels;
}

enum Shape { landscape, portrait, vertical }

Future<Rig> pumpLayer(WidgetTester tester, Shape shape, {FakePlayerSession? session, PageDetails? details}) async {
  final size = shape == Shape.landscape ? landscapeSize : portraitSize;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = session ?? FakePlayerSession();
  final orientation = OrientationController();
  switch (shape) {
    case Shape.landscape:
      orientation.enterLandscape();
    case Shape.vertical:
      orientation.enterVertical();
    case Shape.portrait:
      break;
  }
  final chrome = ChromeState();
  final panels = PanelController();
  final ui = PlayerUi(
    session: fake,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: NoDeviceControls(),
    onBack: () {},
    details: details,
  );
  final below = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => below.add(below.length),
              child: const ColoredBox(color: BiliColors.videoBackground),
            ),
          ),
          Positioned.fill(child: PanelLayer(ui: ui)),
        ],
      ),
    ),
  );
  addTearDown(() {
    chrome.dispose();
    panels.dispose();
    orientation.dispose();
    fake.dispose();
  });
  return Rig(fake, ui, below);
}

Future<void> open(WidgetTester tester, Rig rig, PlayerPanel panel) async {
  rig.panels.open(panel);
  await tester.pumpAndSettle();
}

Color? textColor(WidgetTester tester, String text) {
  final rich = tester.widget<RichText>(find.descendant(of: find.text(text), matching: find.byType(RichText)).first);
  return rich.text.style?.color;
}

Finder get frame => find.byKey(const ValueKey('panel-frame'));

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// Lets a toast run out, so no timer is left when the test ends.
Future<void> clearToast(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// 稍后再看 answers only when the test says.
class SlowWatchLater extends FakePlayerSession {
  final answer = Completer<ActionResult>();

  @override
  Future<ActionResult> watchLater() {
    calls.add('watchLater');
    return answer.future;
  }
}

void main() {
  group('the layer', () {
    testWidgets('closed, it shows nothing and every touch reaches the page', (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape);
      expect(frame, findsNothing);
      await tester.tapAt(const Offset(900, 220));
      expect(rig.below, [0]);

      await open(tester, rig, PlayerPanel.quality);
      rig.panels.close();
      await tester.pump();
      // Sliding out, it already lets touches through.
      await tester.tapAt(const Offset(900, 220));
      expect(rig.below, [0, 1]);
      await tester.pumpAndSettle();
      expect(frame, findsNothing);
      expect(find.byKey(const ValueKey('panel-dismiss')), findsNothing);
    });

    testWidgets('slides in from the right in landscape and back out', (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape);
      rig.panels.open(PlayerPanel.quality);
      await tester.pump();
      expect(tester.getTopLeft(frame).dx, greaterThanOrEqualTo(landscapeSize.width));
      await tester.pump(const Duration(milliseconds: 150));
      final midway = tester.getTopLeft(frame).dx;
      expect(midway, lessThan(landscapeSize.width));
      await tester.pumpAndSettle();
      expect(tester.getTopRight(frame).dx, landscapeSize.width);
      expect(tester.getTopLeft(frame).dx, lessThan(midway));
    });

    testWidgets('rises from the bottom in portrait', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait);
      rig.panels.open(PlayerPanel.quality);
      await tester.pump();
      expect(tester.getTopLeft(frame).dy, greaterThanOrEqualTo(portraitSize.height));
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(frame).dy, portraitSize.height);
    });

    testWidgets('a tap outside closes it in landscape, a tap on it does not', (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape);
      await open(tester, rig, PlayerPanel.more);
      await tester.tapAt(tester.getBottomLeft(frame) + const Offset(20, -4));
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.more);
      await tester.tapAt(const Offset(100, 220));
      await tester.pumpAndSettle();
      expect(rig.panels.value, isNull);
      expect(rig.below, isEmpty);
    });

    testWidgets('a tap outside closes it in portrait', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait);
      await open(tester, rig, PlayerPanel.speed);
      await tester.tapAt(const Offset(220, 100));
      await tester.pumpAndSettle();
      expect(rig.panels.value, isNull);
      expect(rig.below, isEmpty);
    });

    testWidgets('pulling the grabber down closes the sheet; a short pull springs back', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait);
      await open(tester, rig, PlayerPanel.quality);
      final grabber = find.byKey(const ValueKey('panel-grabber'));
      await tester.timedDrag(grabber, const Offset(0, 20), const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.quality);
      expect(tester.getBottomLeft(frame).dy, portraitSize.height);
      await tester.drag(grabber, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(rig.panels.value, isNull);
    });

    testWidgets('a quick flick of the grabber closes the sheet short of the distance', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait);
      await open(tester, rig, PlayerPanel.quality);
      // The sheet follows from the end of the touch slop, so this moves it about 31, short of the 40.
      await tester.fling(
        find.byKey(const ValueKey('panel-grabber')),
        const Offset(0, BiliMetrics.panelDismissDrag + 10),
        BiliMetrics.panelDismissVelocity * 2,
        frameInterval: const Duration(milliseconds: 1),
      );
      await tester.pumpAndSettle();
      expect(rig.panels.value, isNull);
    });

    testWidgets("the back arrow, 高级设置 and the sheet's cross are 44 pt touches", (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape, session: FakePlayerSession()..qualities = _qualities);
      await open(tester, rig, PlayerPanel.quality);
      expect(tester.getSize(find.byKey(const ValueKey('quality-advanced'))).height, BiliMetrics.panelHitBox);
      rig.panels.open(PlayerPanel.codec);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('panel-back'))), const Size.square(BiliMetrics.panelHitBox));

      final sheet = await pumpLayer(tester, Shape.portrait);
      await open(tester, sheet, PlayerPanel.episodes);
      expect(tester.getSize(find.byKey(const ValueKey('sheet-close'))), const Size.square(BiliMetrics.panelHitBox));
      // The grey circle keeps its size and sits 12 from the edge as in 19.
      final circle = find.descendant(of: find.byKey(const ValueKey('sheet-close')), matching: find.byType(Container));
      expect(tester.getSize(circle), const Size.square(BiliMetrics.sheetClose));
      expect(tester.getTopRight(circle).dx, portraitSize.width - BiliMetrics.gutter);
    });

    testWidgets('the titles stay where they were under the taller header', (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape, session: FakePlayerSession()..qualities = _qualities);
      await open(tester, rig, PlayerPanel.quality);
      expect(tester.getCenter(find.text('清晰度')).dy, BiliMetrics.panelTop + BiliMetrics.panelHeaderHeight / 2);
      final card = find.ancestor(of: find.text('自动'), matching: find.byType(Container)).first;
      expect(tester.getTopLeft(card).dy, BiliMetrics.panelTop + BiliMetrics.panelHeaderHeight + BiliMetrics.panelGap);
    });

    final landscapeWidths = {
      PlayerPanel.quality: BiliMetrics.panelQualityWidth,
      PlayerPanel.codec: BiliMetrics.panelQualityWidth,
      PlayerPanel.speed: BiliMetrics.panelSpeedWidth,
      PlayerPanel.more: BiliMetrics.panelMoreWidth,
      PlayerPanel.episodes: BiliMetrics.panelWidth,
    };
    for (final MapEntry(key: panel, value: fraction) in landscapeWidths.entries) {
      testWidgets('${panel.name} is ${fraction * 100}% of the width in landscape, full height', (tester) async {
        final rig = await pumpLayer(tester, Shape.landscape);
        await open(tester, rig, panel);
        expect(tester.getSize(frame), Size(landscapeSize.width * fraction, landscapeSize.height));
        expect(tester.getTopRight(frame), Offset(landscapeSize.width, 0));
      });
    }

    final sheetHeights = {
      PlayerPanel.quality: BiliMetrics.panelSheetHeight,
      PlayerPanel.codec: BiliMetrics.panelSheetHeight,
      PlayerPanel.speed: BiliMetrics.panelSpeedSheetHeight,
      PlayerPanel.more: BiliMetrics.panelMoreSheetHeight,
    };
    for (final MapEntry(key: panel, value: fraction) in sheetHeights.entries) {
      testWidgets('${panel.name} is a sheet ${fraction * 100}% of the height in portrait', (tester) async {
        final rig = await pumpLayer(tester, Shape.portrait);
        await open(tester, rig, panel);
        expect(tester.getSize(frame), Size(portraitSize.width, portraitSize.height * fraction));
        expect(tester.getBottomLeft(frame), Offset(0, portraitSize.height));
      });
    }

    testWidgets('竖屏 gets the portrait sheet too', (tester) async {
      final rig = await pumpLayer(tester, Shape.vertical);
      await open(tester, rig, PlayerPanel.quality);
      expect(tester.getSize(frame), Size(portraitSize.width, portraitSize.height * BiliMetrics.panelSheetHeight));
    });

    testWidgets('选集 in portrait is the light sheet from the player down, in 竖屏 0.62 of the screen', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait);
      await open(tester, rig, PlayerPanel.episodes);
      final player = portraitSize.width / BiliMetrics.videoAspect;
      expect(tester.getTopLeft(frame), Offset(0, player));
      expect(tester.getBottomLeft(frame).dy, portraitSize.height);

      final vertical = await pumpLayer(tester, Shape.vertical);
      await open(tester, vertical, PlayerPanel.episodes);
      expect(tester.getSize(frame).height, portraitSize.height * BiliMetrics.panelSheetHeight);
    });

    testWidgets('the light sheet dims the page below the player and fades the dim with its slide', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait);
      final dim = find.byKey(const ValueKey('panel-sheet-dim'));
      double opacity() => tester.widget<Opacity>(find.descendant(of: dim, matching: find.byType(Opacity))).opacity;

      rig.panels.open(PlayerPanel.episodes);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(tester.getTopLeft(dim), Offset(0, portraitSize.width / BiliMetrics.videoAspect));
      expect(tester.getBottomRight(dim), Offset(portraitSize.width, portraitSize.height));
      final fill = tester.widget<ColoredBox>(find.descendant(of: dim, matching: find.byType(ColoredBox)));
      expect(fill.color, BiliColors.sheetDim);

      rig.panels.close();
      await tester.pumpAndSettle();
      expect(dim, findsNothing);
    });

    testWidgets('the dark sheets have no dim of their own', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait);
      await open(tester, rig, PlayerPanel.more);
      expect(find.byKey(const ValueKey('panel-sheet-dim')), findsNothing);
    });

    testWidgets('the cards end 16 before the safe area at the right, as the official 05', (tester) async {
      tester.view.padding = const FakeViewPadding(left: 62, right: 62);
      final rig = await pumpLayer(tester, Shape.landscape, session: FakePlayerSession()..qualities = _qualities);
      await open(tester, rig, PlayerPanel.quality);
      final card = find.ancestor(of: find.text('自动'), matching: find.byType(Container)).first;
      expect(tester.getTopRight(card).dx, closeTo(878, 0.5));
      expect(tester.getTopLeft(card).dx, closeTo(669, 1));
      expect(tester.getSize(card).height, BiliMetrics.panelCardHeight);
      expect(tester.getTopLeft(card).dy, closeTo(52, 0.5));
    });
  });

  group('清晰度', () {
    Future<Rig> quality(WidgetTester tester, {bool vip = false}) async {
      final session = FakePlayerSession()
        ..qualities = _qualities
        ..quality = 120
        ..isVip = vip;
      final rig = await pumpLayer(tester, Shape.landscape, session: session);
      await open(tester, rig, PlayerPanel.quality);
      return rig;
    }

    testWidgets('lists 自动 then every quality best first, the current one pink, 大会员 badges and the HDR line', (
      tester,
    ) async {
      await quality(tester);
      final titles = ['自动', 'HDR 真彩', '4K 超高清', '1080P 高清', '720P 准高清'];
      final tops = [for (final title in titles) tester.getTopLeft(find.text(title)).dy];
      expect(tops, [...tops]..sort());
      expect(find.text('大会员'), findsNWidgets(2));
      expect(find.text('绚丽色彩，沉浸体验'), findsOneWidget);
      expect(tester.getTopLeft(find.text('绚丽色彩，沉浸体验')).dy, greaterThan(tester.getTopLeft(find.text('HDR 真彩')).dy));
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(textColor(tester, '4K 超高清'), BiliColors.pink);
      expect(textColor(tester, '1080P 高清'), BiliColors.panelText);
      expect(find.text('高级设置'), findsOneWidget);
    });

    testWidgets('the quality playing is the pink one, not the one asked for', (tester) async {
      final session = FakePlayerSession()
        ..qualities = _qualities
        ..quality = 120
        ..playing = 80;
      final rig = await pumpLayer(tester, Shape.landscape, session: session);
      await open(tester, rig, PlayerPanel.quality);
      expect(textColor(tester, '1080P 高清'), BiliColors.pink);
      expect(textColor(tester, '4K 超高清'), BiliColors.panelText);
    });

    testWidgets("the HDR card keeps the cards' height with its second line", (tester) async {
      await quality(tester);
      final card = find.ancestor(of: find.text('绚丽色彩，沉浸体验'), matching: find.byType(Container)).first;
      expect(tester.getSize(card).height, BiliMetrics.panelCardHeight);
    });

    testWidgets('高级设置 is a button', (tester) async {
      final handle = tester.ensureSemantics();
      await quality(tester);
      expect(tester.getSemantics(find.byKey(const ValueKey('quality-advanced'))), isSemantics(isButton: true));
      handle.dispose();
    });

    testWidgets('a quality or codec that fails toasts why after closing', (tester) async {
      final rig = await quality(tester);
      rig.session.failure = '清晰度切换失败';
      await tester.tap(find.text('1080P 高清'));
      await tester.pump();
      expect(rig.panels.value, isNull);
      expect(find.text('清晰度切换失败'), findsOneWidget);
      await clearToast(tester);

      rig.panels.open(PlayerPanel.codec);
      await tester.pumpAndSettle();
      rig.session.failure = '编码切换失败';
      await tester.tap(find.text('AV1'));
      await tester.pump();
      expect(find.text('编码切换失败'), findsOneWidget);
      await clearToast(tester);
    });

    testWidgets('a free quality plays and closes', (tester) async {
      final rig = await quality(tester);
      await tapText(tester, '1080P 高清');
      expect(rig.session.calls, ['setQuality 80']);
      expect(rig.panels.value, isNull);
    });

    testWidgets('without 大会员 a 大会员 quality only toasts, and the panel stays', (tester) async {
      final rig = await quality(tester);
      await tester.tap(find.text('HDR 真彩'));
      await tester.pump();
      expect(find.text('开通大会员后可观看'), findsOneWidget);
      expect(rig.session.calls, isEmpty);
      expect(rig.panels.value, PlayerPanel.quality);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('with 大会员 it plays', (tester) async {
      final rig = await quality(tester, vip: true);
      await tapText(tester, 'HDR 真彩');
      expect(rig.session.calls, ['setQuality 125']);
      expect(rig.panels.value, isNull);
    });

    testWidgets('自动 picks the best one the account may play', (tester) async {
      final rig = await quality(tester);
      await tapText(tester, '自动');
      expect(rig.session.calls, ['setQuality 80']);
    });

    testWidgets('高级设置 opens 编码: the current codec pink, a pick sets it and closes, the arrow goes back', (
      tester,
    ) async {
      final rig = await quality(tester);
      final before = tester.getRect(frame);
      await tester.tap(find.byKey(const ValueKey('quality-advanced')));
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.codec);
      expect(tester.getRect(frame), before);
      expect([for (final codec in VideoCodec.values) codec.label], ['HEVC', 'AV1', 'H.264']);
      for (final label in ['HEVC', 'AV1', 'H.264']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(textColor(tester, 'HEVC'), BiliColors.pink);
      expect(textColor(tester, 'AV1'), BiliColors.panelText);

      await tester.tap(find.byKey(const ValueKey('panel-back')));
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.quality);

      rig.panels.open(PlayerPanel.codec);
      await tester.pumpAndSettle();
      await tapText(tester, 'AV1');
      expect(rig.session.calls, ['setCodec av1']);
      expect(rig.panels.value, isNull);
    });
  });

  group('倍速', () {
    const labels = ['3.0X', '2.0X', '1.5X', '1.25X', '1.0X', '0.75X', '0.5X'];

    testWidgets('a column in landscape, centred on the screen, the current one pink', (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape, session: FakePlayerSession()..rate = 1.25);
      await open(tester, rig, PlayerPanel.speed);
      expect(find.text('倍速'), findsNothing);
      final centres = [for (final label in labels) tester.getCenter(find.text(label))];
      for (final (index, centre) in centres.indexed.skip(1)) {
        expect(centre.dx, closeTo(centres.first.dx, 0.5));
        expect(centre.dy - centres[index - 1].dy, BiliMetrics.panelSpeedRow);
      }
      expect((centres.first.dy + centres.last.dy) / 2, landscapeSize.height / 2);
      expect(textColor(tester, '1.25X'), BiliColors.pink);
      expect(textColor(tester, '1.0X'), BiliColors.panelText);
    });

    testWidgets('a four-column grid in portrait', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait);
      await open(tester, rig, PlayerPanel.speed);
      expect(find.text('倍速'), findsOneWidget);
      final centres = [for (final label in labels) tester.getCenter(find.text(label))];
      expect(centres.take(4).map((c) => c.dy).toSet(), hasLength(1));
      expect(centres.skip(4).map((c) => c.dy).toSet(), hasLength(1));
      expect(centres[4].dy, greaterThan(centres[0].dy));
      expect(centres[4].dx, closeTo(centres[0].dx, 0.5));
      expect(textColor(tester, '1.0X'), BiliColors.pink);
    });

    testWidgets("the strip is 270 wide and its column stays centred at 06's x 790", (tester) async {
      tester.view.padding = const FakeViewPadding(left: 62, right: 62);
      final rig = await pumpLayer(tester, Shape.landscape);
      await open(tester, rig, PlayerPanel.speed);
      expect(tester.getTopLeft(frame).dx, closeTo(686, 0.01));
      expect(tester.getCenter(find.text('1.0X')).dx, closeTo(790, 0.5));
    });

    testWidgets('a rate that fails toasts why', (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape, session: FakePlayerSession()..failure = '倍速设置失败');
      await open(tester, rig, PlayerPanel.speed);
      await tester.tap(find.text('2.0X'));
      await tester.pump();
      expect(rig.panels.value, isNull);
      expect(find.text('倍速设置失败'), findsOneWidget);
      await clearToast(tester);
    });

    testWidgets('a pick sets the rate and closes', (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape);
      await open(tester, rig, PlayerPanel.speed);
      await tapText(tester, '1.5X');
      expect(rig.session.calls, ['setRate 1.5']);
      expect(rig.panels.value, isNull);
    });
  });

  group('⋮', () {
    Future<Rig> more(WidgetTester tester, {FakePlayerSession? session}) async {
      final rig = await pumpLayer(tester, Shape.landscape, session: session);
      await open(tester, rig, PlayerPanel.more);
      return rig;
    }

    testWidgets('has the official rows in order', (tester) async {
      await more(tester);
      final rows = ['稍后再看', '定时关闭', '不开启', '自动连播', '循环播放', '镜像翻转', '画面尺寸', 'BTR 加速', '显示统计'];
      final tops = [for (final row in rows) tester.getTopLeft(find.text(row)).dy];
      expect(tops, [...tops]..sort());
      for (final text in ['小窗播放', '15:00', '30:00', '60:00', '自定义', '单集循环', '列表循环', '不循环', '适应']) {
        expect(find.text(text), findsOneWidget);
      }
    });

    testWidgets('keeps the official places: empty slots round the squares, 画面尺寸 a row down', (tester) async {
      await more(tester);
      final panelLeft = landscapeSize.width * (1 - BiliMetrics.panelMoreWidth);
      const pitch = BiliMetrics.panelActionSize + BiliMetrics.panelActionGap;
      final later = tester.getRect(find.bySemanticsLabel('稍后再看'));
      final pip = tester.getRect(find.bySemanticsLabel('小窗播放'));
      expect(later.left, closeTo(panelLeft + BiliMetrics.panelActionLead + pitch, 0.01));
      expect(later.width, BiliMetrics.panelActionSize);
      expect(pip.left - later.left, pitch);
      final mirror = tester.getCenter(find.text('镜像翻转')).dy;
      expect(tester.getCenter(find.text('画面尺寸')).dy - mirror, BiliMetrics.panelRowHeight * 2);
      for (final kind in [
        PanelGlyphKind.watchLater,
        PanelGlyphKind.autoplay,
        PanelGlyphKind.loop,
        PanelGlyphKind.fit,
      ]) {
        expect(find.byWidgetPredicate((widget) => widget is PanelGlyph && widget.kind == kind), findsOneWidget);
      }
    });

    testWidgets('画面尺寸 is a button', (tester) async {
      final handle = tester.ensureSemantics();
      await more(tester);
      expect(tester.getSemantics(find.byKey(const ValueKey('more-fit'))), isSemantics(isButton: true));
      handle.dispose();
    });

    testWidgets("scrolled to the end, the last card ends 28.3 above the bottom over 21's inset", (tester) async {
      tester.view.padding = const FakeViewPadding(left: 62, right: 62, bottom: 21);
      final rig = await pumpLayer(tester, Shape.landscape);
      await open(tester, rig, PlayerPanel.more);
      final scroll = tester.state<ScrollableState>(find.descendant(of: frame, matching: find.byType(Scrollable)));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final card = find.ancestor(of: find.text('显示统计'), matching: find.byType(DecoratedBox)).first;
      expect(tester.getBottomLeft(card).dy, closeTo(landscapeSize.height - 28.3, 0.01));
    });

    testWidgets('the 测试 card is for dev builds; release shows a blank card of two rows in its place', (tester) async {
      final session = FakePlayerSession();
      addTearDown(session.dispose);
      Future<double> height({required bool devTools}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: MorePanel(session: session, toast: (_) {}, close: () {}, devTools: devTools),
                ),
              ),
            ),
          ),
        );
        return tester.getSize(find.byType(MorePanel)).height;
      }

      final dev = await height(devTools: true);
      expect(find.text('BTR 加速'), findsOneWidget);
      final release = await height(devTools: false);
      expect(find.text('BTR 加速'), findsNothing);
      expect(find.text('显示统计'), findsNothing);
      expect(release, dev);
      // As on 21: a hairline between two blank rows where the official 播放反馈 and 编辑播放器 are.
      final last = tester.widgetList<PanelGroup>(find.byType(PanelGroup)).last;
      expect(last.children, hasLength(2));
      expect([for (final row in last.children) (row as PanelBlankRow).divider], [true, false]);
    });

    testWidgets('稍后再看 that fails toasts and stays open', (tester) async {
      final rig = await more(
        tester,
        session: FakePlayerSession()..watchLaterResult = const ActionResult('添加失败', ok: false),
      );
      await tester.tap(find.text('稍后再看'));
      await tester.pump();
      await tester.pump();
      expect(find.text('添加失败'), findsOneWidget);
      expect(rig.panels.value, PlayerPanel.more);
      await clearToast(tester);
    });

    testWidgets('稍后再看 answering after another panel opened leaves that one open', (tester) async {
      final session = SlowWatchLater();
      final rig = await more(tester, session: session);
      await tester.tap(find.text('稍后再看'));
      await tester.pump();
      rig.panels.open(PlayerPanel.speed);
      await tester.pumpAndSettle();
      session.answer.complete(const ActionResult('已添加至稍后再看', ok: true));
      await tester.pump();
      await tester.pump();
      expect(find.text('已添加至稍后再看'), findsOneWidget);
      expect(rig.panels.value, PlayerPanel.speed);
      await clearToast(tester);
    });

    testWidgets('a switch, 画面尺寸 or 小窗播放 that fails toasts why', (tester) async {
      final rig = await more(tester, session: FakePlayerSession()..failure = '设置失败');
      for (final row in ['镜像翻转', 'BTR 加速']) {
        await tester.ensureVisible(find.text(row));
        await tester.pumpAndSettle();
        await tester.tap(find.text(row));
        await tester.pump();
        expect(find.text('设置失败'), findsOneWidget, reason: row);
        expect(rig.panels.value, PlayerPanel.more);
        await clearToast(tester);
      }
      await tapText(tester, '画面尺寸');
      await tester.tap(find.text('16:9'));
      await tester.pump();
      expect(find.text('设置失败'), findsOneWidget);
      await clearToast(tester);
      await tester.tap(find.text('小窗播放'));
      await tester.pump();
      expect(find.text('设置失败'), findsOneWidget);
      expect(rig.panels.value, isNull);
      await clearToast(tester);
    });

    testWidgets('稍后再看 toasts what the session says and closes', (tester) async {
      final rig = await more(tester);
      await tester.tap(find.text('稍后再看'));
      await tester.pump();
      await tester.pump();
      expect(rig.session.calls, ['watchLater']);
      expect(find.text('已添加至稍后再看'), findsOneWidget);
      expect(rig.panels.value, isNull);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('小窗播放 starts picture in picture and closes; greyed out where unsupported', (tester) async {
      final rig = await more(tester);
      await tapText(tester, '小窗播放');
      expect(rig.session.calls, ['startPictureInPicture']);
      expect(rig.panels.value, isNull);

      final unsupported = await more(tester, session: FakePlayerSession()..pictureInPictureSupported = false);
      await tapText(tester, '小窗播放');
      expect(unsupported.session.calls, isEmpty);
      expect(unsupported.panels.value, PlayerPanel.more);
    });

    testWidgets('定时关闭 presets set the timer and stay open, showing the time left', (tester) async {
      final rig = await more(tester);
      expect(textColor(tester, '不开启'), BiliColors.pink);
      await tapText(tester, '15:00');
      expect(rig.session.calls, ['setSleepTimer 15']);
      expect(rig.panels.value, PlayerPanel.more);
      expect(textColor(tester, '15:00'), BiliColors.pink);
      expect(find.text('15:00 后暂停'), findsOneWidget);
      rig.session.sleepRemaining.value = const Duration(minutes: 14, seconds: 3);
      await tester.pump();
      expect(find.text('14:03 后暂停'), findsOneWidget);
      await tapText(tester, '不开启');
      expect(rig.session.calls.last, 'setSleepTimer null');
      expect(find.byKey(const ValueKey('sleep-remaining')), findsNothing);
    });

    testWidgets('自定义 turns a wheel of 1 to 180 minutes; 确定 sets it and shows it in the row', (tester) async {
      final rig = await more(tester);
      await tapText(tester, '自定义');
      expect(find.byType(CupertinoPicker), findsOneWidget);
      expect(find.text('自定义定时关闭'), findsOneWidget);
      expect(find.text('30 分钟'), findsOneWidget);
      await tester.drag(find.byType(CupertinoPicker), const Offset(0, -BiliMetrics.panelWheelItem * 15));
      await tester.pumpAndSettle();
      await tapText(tester, '确定');
      final call = rig.session.calls.single;
      final minutes = int.parse(call.split(' ').last);
      expect(minutes, greaterThan(30));
      expect(minutes, lessThanOrEqualTo(180));
      expect(find.text('$minutes分钟'), findsOneWidget);
      expect(textColor(tester, '$minutes分钟'), BiliColors.pink);
      expect(rig.panels.value, PlayerPanel.more);
    });

    testWidgets('the wheel opens on the minutes set before, each time', (tester) async {
      final rig = await more(tester);
      await tapText(tester, '自定义');
      await tester.drag(find.byType(CupertinoPicker), const Offset(0, -BiliMetrics.panelWheelItem * 15));
      await tester.pumpAndSettle();
      await tapText(tester, '确定');
      final minutes = int.parse(rig.session.calls.single.split(' ').last);
      await tapText(tester, '$minutes分钟');
      final picker = tester.widget<CupertinoPicker>(find.byType(CupertinoPicker));
      expect(picker.scrollController?.selectedItem, minutes - 1);
      await tester.tap(find.byKey(const ValueKey('panel-back')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsNothing);
    });

    testWidgets('the wheel ends at 180 and starts at 1', (tester) async {
      final rig = await more(tester);
      await tapText(tester, '自定义');
      await tester.drag(find.byType(CupertinoPicker), const Offset(0, -BiliMetrics.panelWheelItem * 400));
      await tester.pumpAndSettle();
      await tapText(tester, '确定');
      await tapText(tester, '180分钟');
      await tester.drag(find.byType(CupertinoPicker), const Offset(0, BiliMetrics.panelWheelItem * 400));
      await tester.pumpAndSettle();
      await tapText(tester, '确定');
      expect(rig.session.calls, ['setSleepTimer 180', 'setSleepTimer 1']);
    });

    testWidgets('the switches and the loop segments call the session and stay open', (tester) async {
      final rig = await more(tester);
      await tapText(tester, '自动连播');
      await tapText(tester, '单集循环');
      await tapText(tester, '镜像翻转');
      await tapText(tester, 'BTR 加速');
      await tapText(tester, '显示统计');
      expect(rig.session.calls, [
        'setAutoplayNext false',
        'setLoop single',
        'setMirrored true',
        'setBtr false',
        'setShowStats true',
      ]);
      expect(textColor(tester, '单集循环'), BiliColors.pink);
      expect(rig.panels.value, PlayerPanel.more);
    });

    testWidgets('画面尺寸 opens its page; a pick sets it and comes back', (tester) async {
      final rig = await more(tester);
      await tapText(tester, '画面尺寸');
      for (final mode in FitMode.values) {
        expect(find.text(mode.label), findsOneWidget);
      }
      expect(textColor(tester, '适应'), BiliColors.pink);
      await tapText(tester, '16:9');
      expect(rig.session.calls, ['setFit ratio16x9']);
      expect(find.text('定时关闭'), findsOneWidget);
      expect(find.text('16:9'), findsOneWidget);
      expect(rig.panels.value, PlayerPanel.more);
    });
  });

  group('选集', () {
    const episodes = [
      Episode(bvid: 'BV1', cid: 1, title: 'P1 开头', current: false),
      Episode(bvid: 'BV1', cid: 2, title: 'P2 中间', current: true),
      Episode(bvid: 'BV1', cid: 3, title: 'P3 结尾', current: false),
    ];

    for (final shape in [Shape.landscape, Shape.portrait]) {
      testWidgets('${shape.name}: lists the episodes, the current pink; a tap plays it and closes', (tester) async {
        final rig = await pumpLayer(tester, shape, session: FakePlayerSession()..episodes = episodes);
        await open(tester, rig, PlayerPanel.episodes);
        expect(find.text('选集'), findsOneWidget);
        final tops = [for (final episode in episodes) tester.getTopLeft(find.text(episode.title)).dy];
        expect(tops, [...tops]..sort());
        // The light sheet's pink is 19's, a little softer than the dark cards'.
        expect(
          textColor(tester, 'P2 中间'),
          shape == Shape.landscape ? BiliColors.pink : VerticalActionTheme.sheetPlaying,
        );
        expect(textColor(tester, 'P1 开头'), shape == Shape.landscape ? BiliColors.panelText : BiliColors.text);
        await tapText(tester, 'P3 结尾');
        expect(rig.session.calls, ['playEpisode BV1 3']);
        expect(rig.panels.value, isNull);
      });
    }

    testWidgets('the current one only closes', (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape, session: FakePlayerSession()..episodes = episodes);
      await open(tester, rig, PlayerPanel.episodes);
      await tapText(tester, 'P2 中间');
      expect(rig.session.calls, isEmpty);
      expect(rig.panels.value, isNull);
    });

    testWidgets('landscape cards show the duration when known', (tester) async {
      final rig = await pumpLayer(
        tester,
        Shape.landscape,
        session: FakePlayerSession()
          ..episodes = const [
            Episode(bvid: 'BV1', cid: 1, title: 'P1', current: true, duration: 95),
            Episode(bvid: 'BV1', cid: 2, title: 'P2', current: false),
          ],
      );
      await open(tester, rig, PlayerPanel.episodes);
      expect(find.text('01:35'), findsOneWidget);
    });

    testWidgets('portrait parts are compact rows with their duration', (tester) async {
      final rig = await pumpLayer(
        tester,
        Shape.portrait,
        session: FakePlayerSession()
          ..episodes = const [
            Episode(bvid: 'BV1', cid: 1, title: 'P1', current: true, duration: 95),
            Episode(bvid: 'BV1', cid: 2, title: 'P2', current: false, duration: 3725),
          ],
      );
      await open(tester, rig, PlayerPanel.episodes);
      expect(find.text('01:35'), findsOneWidget);
      expect(find.text('1:02:05'), findsOneWidget);
      expect(find.text('正序'), findsNothing);
      expect(find.text('内容到底啦'), findsNothing);
    });

    testWidgets('the light sheet closes from its cross', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait, session: FakePlayerSession()..episodes = episodes);
      await open(tester, rig, PlayerPanel.episodes);
      await tester.tap(find.byKey(const ValueKey('sheet-close')));
      await tester.pumpAndSettle();
      expect(rig.panels.value, isNull);
    });
  });

  group('选集 sheet for a 合集 (19)', () {
    final year = DateTime.now().year;
    int day(int month, int d) => DateTime(year, month, d).millisecondsSinceEpoch ~/ 1000;
    final episodes = [
      Episode(
        bvid: 'BV1',
        cid: 1,
        title: '第一集',
        current: false,
        cover: '',
        duration: 32,
        pubdate: day(8, 28),
        views: 209000,
        danmaku: 237,
      ),
      Episode(
        bvid: 'BV2',
        cid: 2,
        title: '第二集',
        current: false,
        cover: '',
        duration: 61,
        pubdate: day(9, 3),
        views: 113000,
        danmaku: 217,
      ),
      Episode(
        bvid: 'BV3',
        cid: 3,
        title: '第三集',
        current: true,
        cover: '',
        duration: 66,
        pubdate: DateTime(year - 1, 10, 11).millisecondsSinceEpoch ~/ 1000,
        views: 4300,
        danmaku: 344,
      ),
    ];

    FakePlayerSession season({String intro = '求订阅！谢谢大家一直以来的支持！'}) => FakePlayerSession()
      ..episodesAreParts = false
      ..episodes = episodes
      ..detail = VideoDetail(
        bvid: 'BV3',
        aid: 3,
        title: '',
        cover: '',
        pubdate: 0,
        duration: 66,
        desc: '',
        descParts: const [],
        copyright: 1,
        owner: VideoOwner.empty,
        stat: VideoStat.zero,
        pages: const [],
        season: UgcSeason(id: 1, title: 'MAD系列', intro: intro, sections: const []),
        staff: const [],
        width: 1920,
        height: 1080,
        honor: null,
        redirectURL: null,
      );

    testWidgets('the 合集 name heads it, then the intro with 展开 and 选集 with 正序', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait, session: season());
      await open(tester, rig, PlayerPanel.episodes);
      expect(find.text('MAD系列'), findsOneWidget);
      expect(find.text('求订阅！谢谢大家一直以来的支持！'), findsOneWidget);
      expect(find.text('展开'), findsOneWidget);
      expect(find.text('选集'), findsOneWidget);
      expect(find.text('正序'), findsOneWidget);
      final title = tester.getCenter(find.text('MAD系列')).dy;
      final intro = tester.getCenter(find.text('展开')).dy;
      final section = tester.getCenter(find.text('选集')).dy;
      expect(title, lessThan(intro));
      expect(intro, lessThan(section));
      // The share circle and 收藏 come with the page's actions; without them their room stays empty.
      expect(find.byKey(const ValueKey('sheet-share')), findsNothing);
      expect(
        tester.getTopRight(find.text('展开')).dx,
        lessThanOrEqualTo(portraitSize.width - BiliMetrics.sheetIntroTrailing),
      );

      await tester.tap(find.byKey(const ValueKey('sheet-intro')));
      await tester.pumpAndSettle();
      expect(find.textContaining('收起', findRichText: true), findsOneWidget);
    });

    testWidgets('rows 100.3 apart with cover, duration, date, counts and the pink playing bars', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait, session: season());
      await open(tester, rig, PlayerPanel.episodes);
      final tops = [
        for (final title in ['第一集', '第二集']) tester.getTopLeft(find.text(title, findRichText: true)).dy,
      ];
      expect(tops[1] - tops[0], closeTo(BiliMetrics.sheetRowPad * 2 + BiliMetrics.sheetCoverHeight + 1 / 3, 0.01));
      expect(tester.getTopLeft(find.text('第一集', findRichText: true)).dx, closeTo(155, 0.5));
      for (final text in ['00:32', '01:01', '01:06', '8月28日', '9月3日', '${year - 1}年10月11日', '20.9万', '237', '4300']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      final bars = find.byWidgetPredicate((widget) => widget is PanelGlyph && widget.kind == PanelGlyphKind.playing);
      expect(bars, findsOneWidget);
      // 19's #ED7098, 收藏's pink, for the bars and the playing title alike.
      expect(VerticalActionTheme.sheetPlaying, const Color(0xFFED7098));
      expect(tester.widget<PanelGlyph>(bars).color, VerticalActionTheme.sheetPlaying);
      Color? titleColour(String title) => tester
          .widget<RichText>(find.descendant(of: find.textContaining(title), matching: find.byType(RichText)).first)
          .text
          .style
          ?.color;
      expect(titleColour('第三集'), VerticalActionTheme.sheetPlaying);
      expect(titleColour('第一集'), BiliColors.text);
      expect(tester.getTopLeft(bars).dx, greaterThan(BiliMetrics.gutter + BiliMetrics.sheetCoverWidth));
      expect(find.text('内容到底啦'), findsOneWidget);
      expect(find.text('仅展示本App中可查看的稿件'), findsOneWidget);
    });

    testWidgets('正序 turns the list round, and back', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait, session: season());
      await open(tester, rig, PlayerPanel.episodes);
      double top(String title) => tester.getTopLeft(find.textContaining(title, findRichText: true)).dy;
      expect(top('第一集'), lessThan(top('第三集')));
      await tester.tap(find.byKey(const ValueKey('sheet-order')));
      await tester.pumpAndSettle();
      expect(find.text('倒序'), findsOneWidget);
      expect(top('第三集'), lessThan(top('第一集')));
      await tester.tap(find.byKey(const ValueKey('sheet-order')));
      await tester.pumpAndSettle();
      expect(top('第一集'), lessThan(top('第三集')));
    });

    testWidgets('a long 合集 opens on the playing episode, and keeps it in view when the order turns round', (
      tester,
    ) async {
      final long = [
        for (var i = 1; i <= 7; i++)
          Episode(bvid: 'BV$i', cid: i, title: '长篇第$i集', current: i == 7, cover: '', duration: 60),
      ];
      final rig = await pumpLayer(tester, Shape.portrait, session: season()..episodes = long);
      await open(tester, rig, PlayerPanel.episodes);
      final button = find.byKey(const ValueKey('sheet-order'));
      final list = find.ancestor(of: button, matching: find.byType(Scrollable)).first;
      final viewport = tester.getRect(list);
      final playing = find.textContaining('长篇第7集', findRichText: true);
      bool inView() => viewport.contains(tester.getRect(playing).center);
      expect(inView(), isTrue, reason: 'it opens on the playing episode');
      expect(viewport.contains(tester.getCenter(button)), isFalse);

      // VoiceOver and the Windows driver press 正序 where it lies, scrolled out of view.
      for (final (label, next) in [('正序', '倒序'), ('倒序', '正序')]) {
        tester.semantics.tap(find.semantics.byLabel(label));
        await tester.pumpAndSettle();
        expect(find.text(next, skipOffstage: false), findsOneWidget);
        expect(inView(), isTrue, reason: next);
      }

      await tester.scrollUntilVisible(button, -100, scrollable: list);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('倒序'), findsOneWidget);
      expect(inView(), isTrue);
    });

    testWidgets('a tap plays the episode and closes', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait, session: season(intro: ''));
      await open(tester, rig, PlayerPanel.episodes);
      expect(find.text('展开'), findsNothing);
      await tester.tap(find.text('第二集', findRichText: true));
      await tester.pumpAndSettle();
      expect(rig.session.calls, ['playEpisode BV2 2']);
      expect(rig.panels.value, isNull);
    });

    FakePageDetails withActions({bool? subscribed = false}) =>
        FakePageDetails(actions: FakeVideoActions(seasonFavourited: subscribed));

    final share = find.byKey(const ValueKey('sheet-share'));
    final favourite = find.byKey(const ValueKey('sheet-favourite'));

    ActionIcon iconIn(WidgetTester tester, Finder button) =>
        tester.widget<ActionIcon>(find.descendant(of: button, matching: find.byType(ActionIcon)));

    Color? fillOf(WidgetTester tester, Finder button) {
      final pill = find.descendant(of: button, matching: find.byType(AnimatedContainer));
      return (tester.widget<AnimatedContainer>(pill).decoration! as ShapeDecoration).color;
    }

    testWidgets('the share circle and 收藏 sit at the right of the intro\'s line, as on 19', (tester) async {
      final details = withActions();
      addTearDown(details.dispose);
      final rig = await pumpLayer(tester, Shape.portrait, session: season(), details: details);
      await open(tester, rig, PlayerPanel.episodes);

      expect(find.text('收藏'), findsOneWidget);
      expect(tester.getSize(share), const Size.square(VerticalActionTheme.sheetShare));
      expect(tester.getSize(favourite).height, VerticalActionTheme.sheetPillHeight);
      expect(tester.getTopRight(favourite).dx, closeTo(portraitSize.width - BiliMetrics.gutter, 0.01));
      expect(
        tester.getTopLeft(favourite).dx - tester.getTopRight(share).dx,
        closeTo(VerticalActionTheme.sheetGap, 0.01),
      );
      // Both centred 5 above the description's line, which ends before them.
      final line = tester.getCenter(find.byKey(const ValueKey('sheet-intro'))).dy;
      expect(tester.getCenter(share).dy, closeTo(line - 5, 0.5));
      expect(tester.getCenter(favourite).dy, closeTo(line - 5, 0.5));
      expect(tester.getTopRight(find.text('展开')).dx, lessThan(tester.getTopLeft(share).dx));
      // A grey circle round an outlined arrow; a pink pill with an outlined star.
      final circle = tester.widget<Container>(find.descendant(of: share, matching: find.byType(Container)).first);
      expect((circle.decoration! as BoxDecoration).color, BiliColors.pageGrey);
      expect(iconIn(tester, share).glyph, ActionGlyph.share);
      expect(iconIn(tester, share).solid, isFalse);
      expect(iconIn(tester, favourite).glyph, ActionGlyph.favourite);
      expect(iconIn(tester, favourite).solid, isFalse);
      expect(fillOf(tester, favourite), VerticalActionTheme.sheetPill);
    });

    testWidgets('the header, the intro and 选集 stay where they are with or without the actions', (tester) async {
      Future<Map<String, Offset>> places(PageDetails? details) async {
        final rig = await pumpLayer(tester, Shape.portrait, session: season(), details: details);
        await open(tester, rig, PlayerPanel.episodes);
        return {
          for (final text in ['MAD系列', '展开', '选集', '正序']) text: tester.getCenter(find.text(text)),
          'close': tester.getCenter(find.byKey(const ValueKey('sheet-close'))),
        };
      }

      final bare = await places(null);
      final details = withActions();
      addTearDown(details.dispose);
      expect(await places(details), bare);
    });

    testWidgets('share asks the page for the share sheet; 收藏 subscribes the 合集', (tester) async {
      final details = withActions();
      addTearDown(details.dispose);
      final rig = await pumpLayer(tester, Shape.portrait, session: season(), details: details);
      await open(tester, rig, PlayerPanel.episodes);
      final actions = details.actions! as FakeVideoActions;

      await tester.tap(share);
      await tester.tap(favourite);
      await tester.pumpAndSettle();
      expect(actions.calls, ['ask share', 'toggleSeasonFavourite']);
      expect(rig.panels.value, PlayerPanel.episodes);

      tester.semantics.tap(find.semantics.byLabel('分享'));
      tester.semantics.tap(find.semantics.byLabel('收藏'));
      expect(actions.calls, ['ask share', 'toggleSeasonFavourite', 'ask share', 'toggleSeasonFavourite']);
    });

    testWidgets('subscribed, it reads ★ 已收藏 in grey, and a tap unsubscribes', (tester) async {
      final details = withActions(subscribed: true);
      addTearDown(details.dispose);
      final rig = await pumpLayer(tester, Shape.portrait, session: season(), details: details);
      await open(tester, rig, PlayerPanel.episodes);

      expect(find.text('已收藏'), findsOneWidget);
      expect(find.text('收藏'), findsNothing);
      expect(iconIn(tester, favourite).solid, isTrue);
      expect(iconIn(tester, favourite).color, VerticalActionTheme.sheetSubscribedLabel);
      expect(fillOf(tester, favourite), VerticalActionTheme.sheetSubscribedFill);
      await tester.tap(favourite);
      expect((details.actions! as FakeVideoActions).calls, ['toggleSeasonFavourite']);

      (details.actions! as FakeVideoActions)
        ..seasonFavourited = false
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('收藏'), findsOneWidget);
      expect(fillOf(tester, favourite), VerticalActionTheme.sheetPill);
    });

    testWidgets('unknown (logged out, or no answer from the relation), 收藏 reads 收藏 and still taps through', (
      tester,
    ) async {
      final details = withActions(subscribed: null);
      addTearDown(details.dispose);
      final rig = await pumpLayer(tester, Shape.portrait, session: season(), details: details);
      await open(tester, rig, PlayerPanel.episodes);
      final actions = details.actions! as FakeVideoActions;

      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('已收藏'), findsNothing);
      expect(fillOf(tester, favourite), VerticalActionTheme.sheetPill);
      expect(iconIn(tester, favourite).solid, isFalse);
      expect(find.descendant(of: favourite, matching: find.byType(AnimatedOpacity)), findsNothing, reason: 'undimmed');
      expect(
        tester.getSemantics(favourite),
        isSemantics(label: '收藏', isButton: true, hasTapAction: true),
      );
      // The actions decide: logged out they ask for a login, otherwise they subscribe.
      await tester.tap(favourite);
      await tester.pumpAndSettle();
      expect(actions.calls, ['toggleSeasonFavourite']);
      tester.semantics.tap(find.semantics.byLabel('收藏'));
      expect(actions.calls, ['toggleSeasonFavourite', 'toggleSeasonFavourite']);
      expect(rig.panels.value, PlayerPanel.episodes);
    });

    testWidgets('nothing until the actions exist; they fade in without moving anything', (tester) async {
      final details = FakePageDetails();
      addTearDown(details.dispose);
      final rig = await pumpLayer(tester, Shape.portrait, session: season(), details: details);
      await open(tester, rig, PlayerPanel.episodes);
      expect(share, findsNothing);
      expect(favourite, findsNothing);
      final intro = tester.getRect(find.text('展开'));
      final section = tester.getRect(find.text('选集'));

      details
        ..actions = FakeVideoActions(seasonFavourited: false)
        ..changed();
      await tester.pumpAndSettle();
      expect(share, findsOneWidget);
      expect(find.text('收藏'), findsOneWidget);
      expect(tester.getRect(find.text('展开')), intro);
      expect(tester.getRect(find.text('选集')), section);
    });

    testWidgets('a 合集 with no description still has them, above 选集', (tester) async {
      final details = withActions();
      addTearDown(details.dispose);
      final rig = await pumpLayer(tester, Shape.portrait, session: season(intro: ''), details: details);
      await open(tester, rig, PlayerPanel.episodes);
      expect(find.text('展开'), findsNothing);
      expect(share, findsOneWidget);
      expect(tester.getBottomLeft(favourite).dy, lessThan(tester.getTopLeft(find.text('选集')).dy));
    });

    testWidgets('parts get neither, nor does a player outside a video page', (tester) async {
      final details = withActions();
      addTearDown(details.dispose);
      final rig = await pumpLayer(
        tester,
        Shape.portrait,
        session: FakePlayerSession()
          ..episodes = const [
            Episode(bvid: 'BV1', cid: 1, title: 'P1', current: true, duration: 95),
            Episode(bvid: 'BV1', cid: 2, title: 'P2', current: false, duration: 3725),
          ],
        details: details,
      );
      await open(tester, rig, PlayerPanel.episodes);
      expect(share, findsNothing);
      expect(favourite, findsNothing);

      final bare = await pumpLayer(tester, Shape.portrait, session: season());
      await open(tester, bare, PlayerPanel.episodes);
      expect(share, findsNothing);
      expect(favourite, findsNothing);
    });

    testWidgets('landscape 选集 cards carry neither', (tester) async {
      final details = withActions();
      addTearDown(details.dispose);
      final rig = await pumpLayer(tester, Shape.landscape, session: season(), details: details);
      await open(tester, rig, PlayerPanel.episodes);
      expect(find.text('第一集'), findsOneWidget);
      expect(share, findsNothing);
    });
  });

  group('the danmaku frames', () {
    testWidgets("弹幕设置 in landscape is 07's strip: 382 of 956 wide, full height, cut straight with no ramp", (
      tester,
    ) async {
      final rig = await pumpLayer(tester, Shape.landscape);
      await open(tester, rig, PlayerPanel.danmakuSettings);
      expect(tester.getRect(frame), const Rect.fromLTWH(574, 0, 382, 440));
      final shade = find.byWidgetPredicate((widget) => widget is ColoredBox && widget.color == DanmakuPanelTheme.shade);
      expect(shade, findsOneWidget);
      expect(tester.getRect(shade), tester.getRect(frame));
      final ramps = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      expect(ramps.where((box) => (box.decoration as BoxDecoration?)?.gradient != null), isEmpty);
    });

    testWidgets("当前弹幕列表 in landscape is 31's side panel, with the usual ramp into the video", (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape);
      await open(tester, rig, PlayerPanel.danmakuList);
      expect(tester.getSize(frame), Size(landscapeSize.width * BiliMetrics.panelWidth, landscapeSize.height));
      expect(tester.getTopRight(frame), Offset(landscapeSize.width, 0));
      final ramps = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      expect(ramps.where((box) => (box.decoration as BoxDecoration?)?.gradient != null), hasLength(1));
    });

    testWidgets('添加屏蔽词 covers the whole screen', (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape);
      await open(tester, rig, PlayerPanel.blockWords);
      expect(tester.getRect(frame), Offset.zero & landscapeSize);
    });

    testWidgets("弹幕设置 in portrait is 40's light sheet on grey from the player down, in 竖屏 497 of 956 tall", (
      tester,
    ) async {
      final rig = await pumpLayer(tester, Shape.portrait);
      await open(tester, rig, PlayerPanel.danmakuSettings);
      final player = portraitSize.width / BiliMetrics.videoAspect;
      expect(tester.getTopLeft(frame), Offset(0, player));
      expect(tester.getBottomLeft(frame).dy, portraitSize.height);
      final sheet = tester.widget<DecoratedBox>(find.descendant(of: frame, matching: find.byType(DecoratedBox)).first);
      expect((sheet.decoration as BoxDecoration).color, DanmakuPanelTheme.lightBackground);
      expect(find.byKey(const ValueKey('panel-sheet-dim')), findsOneWidget);

      final vertical = await pumpLayer(tester, Shape.vertical);
      await open(tester, vertical, PlayerPanel.danmakuSettings);
      expect(tester.getSize(frame).height, closeTo(portraitSize.height * DanmakuPanelTheme.sheetHeight, 0.01));
      expect(tester.getSize(frame).height, closeTo(497, 0.01));
    });

    for (final panel in [PlayerPanel.blockWords, PlayerPanel.danmakuList]) {
      for (final upright in [Presentation.inline, Presentation.vertical]) {
        testWidgets("${panel.name} turned to ${upright.name} gives way to 弹幕设置's sheet", (tester) async {
          final rig = await pumpLayer(tester, Shape.landscape);
          await open(tester, rig, panel);
          if (upright == Presentation.inline) {
            rig.ui.orientation.exitToInline();
          } else {
            rig.ui.orientation.enterVertical();
          }
          tester.view.physicalSize = portraitSize;
          await tester.pumpAndSettle();
          expect(rig.panels.value, PlayerPanel.danmakuSettings);
          expect(find.byKey(const ValueKey('panel-sheet-dim')), findsOneWidget);
          expect(tester.getBottomLeft(frame), Offset(0, portraitSize.height));
          expect(tester.getSize(frame).width, portraitSize.width);
        });
      }
    }

    testWidgets('turned upright, other panels stay as they are', (tester) async {
      final rig = await pumpLayer(tester, Shape.landscape);
      await open(tester, rig, PlayerPanel.quality);
      rig.ui.orientation.exitToInline();
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.quality);
    });

    testWidgets('选集 keeps its white sheet', (tester) async {
      final rig = await pumpLayer(tester, Shape.portrait);
      await open(tester, rig, PlayerPanel.episodes);
      final sheet = tester.widget<DecoratedBox>(find.descendant(of: frame, matching: find.byType(DecoratedBox)).first);
      expect((sheet.decoration as BoxDecoration).color, BiliColors.card);
    });
  });
}
