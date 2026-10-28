import 'dart:io';

import 'package:bili_core/api.dart' show BiliClient, CookieJar, QualityOption;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../playback/fakes.dart';
import '../../support/fake_player_session.dart';
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';

/// 10's qualities, best first after 自动, 1080P 高码率 playing.
const _qualities = [
  QualityOption(id: 120, name: '超清 4K'),
  QualityOption(id: 112, name: '高清 1080P+'),
  QualityOption(id: 80, name: '高清 1080P'),
  QualityOption(id: 64, name: '高清 720P'),
  QualityOption(id: 32, name: '清晰 480P'),
  QualityOption(id: 16, name: '流畅 360P'),
];

class PadRig {
  PadRig(this.session, this.ui, this.size);

  final FakePlayerSession session;
  final PlayerUi ui;
  final Size size;

  PanelController get panels => ui.panels;
}

enum Held { sideways, upright }

/// The iPad's page under the panel layer, in full screen (held either way) or on the page with the player's bottom
/// at [playerBottom] and the page's [padFrame].
Future<PadRig> pumpPad(
  WidgetTester tester, {
  Held held = Held.sideways,
  bool fullScreen = true,
  double? playerBottom,
  PadSheetFrame? padFrame,
  bool phone = false,
}) async {
  final Size size;
  if (phone) {
    showAsPhone(tester, landscape: true);
    size = const Size(956, 440);
  } else {
    showAsPad(tester, landscape: held == Held.sideways);
    size = held == Held.sideways
        ? const Size(1194, 834)
        : const Size(834, 1194);
  }
  final orientation = OrientationController();
  if (fullScreen) orientation.enterLandscape();
  final chrome = ChromeState();
  final panels = PanelController();
  final session = FakePlayerSession()
    ..qualities = _qualities
    ..quality = 112;
  final store = DanmakuSettingsStore.memory(const DanmakuSettings());
  final api = FakePageApi();
  final logger = Logger(session: 'test');
  final feed = DanmakuFeed(
    client: BiliClient(
      transport: Canned.http(),
      cookies: CookieJar(Canned.cookies),
      logger: logger,
    ),
    logger: logger,
  );
  final rules = BlockRuleStore(api: api, isLoggedIn: () => true);
  final danmaku = DanmakuSession(
    feed: feed,
    settings: store,
    rules: rules,
    api: api,
    target: () => null,
    position: () => 0,
    isLoggedIn: () => true,
    isVip: () => false,
    accountMid: () => 0,
    requestLogin: () {},
  );
  final ui = PlayerUi(
    session: session,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: NoDeviceControls(),
    onBack: () {},
    danmaku: danmaku,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: const ValueKey('screen'),
        child: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: BiliColors.videoBackground),
            ),
            Positioned.fill(
              child: PanelLayer(
                ui: ui,
                playerBottom: playerBottom,
                padFrame: padFrame,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  addTearDown(() {
    danmaku.dispose();
    rules.dispose();
    feed.dispose();
    store.dispose();
    chrome.dispose();
    panels.dispose();
    orientation.dispose();
    session.dispose();
  });
  return PadRig(session, ui, size);
}

Future<void> openPanel(
  WidgetTester tester,
  PadRig rig,
  PlayerPanel panel,
) async {
  rig.panels.open(panel);
  await tester.pumpAndSettle();
}

Finder get frame => find.byKey(const ValueKey('panel-frame'));

Color? textColor(WidgetTester tester, String text) => tester
    .widget<RichText>(
      find
          .descendant(of: find.text(text), matching: find.byType(RichText))
          .first,
    )
    .text
    .style
    ?.color;

double? fontSize(WidgetTester tester, String text) => tester
    .widget<RichText>(
      find
          .descendant(of: find.text(text), matching: find.byType(RichText))
          .first,
    )
    .text
    .style
    ?.fontSize;

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  group('full screen on the iPad', () {
    final widths = {
      PlayerPanel.quality: PadPanelTheme.narrowWidth,
      PlayerPanel.codec: PadPanelTheme.narrowWidth,
      PlayerPanel.speed: PadPanelTheme.narrowWidth,
      PlayerPanel.more: PadPanelTheme.wideWidth,
      PlayerPanel.danmakuSettings: PadPanelTheme.wideWidth,
      PlayerPanel.danmakuList: PadPanelTheme.wideWidth,
      PlayerPanel.episodes: PadPanelTheme.wideWidth,
    };
    for (final held in Held.values) {
      for (final MapEntry(key: panel, value: width) in widths.entries) {
        testWidgets(
          '${panel.name} is $width pt wide at the right, full height, held ${held.name}',
          (tester) async {
            final rig = await pumpPad(tester, held: held);
            await openPanel(tester, rig, panel);
            expect(tester.getSize(frame), Size(width, rig.size.height));
            expect(tester.getTopRight(frame), Offset(rig.size.width, 0));
          },
        );
      }
    }

    testWidgets('添加屏蔽词 still covers the whole screen', (tester) async {
      final rig = await pumpPad(tester);
      await openPanel(tester, rig, PlayerPanel.blockWords);
      expect(tester.getSize(frame), rig.size);
    });

    testWidgets(
      'every strip has a hard edge in its measured shade, with no ramp into the video',
      (tester) async {
        final shades = {
          PlayerPanel.quality: PadPanelTheme.shade,
          PlayerPanel.more: PadPanelTheme.shade,
          PlayerPanel.speed: PadPanelTheme.darkShade,
          PlayerPanel.danmakuSettings: PadPanelTheme.darkShade,
        };
        final rig = await pumpPad(tester);
        for (final MapEntry(key: panel, value: shade) in shades.entries) {
          await openPanel(tester, rig, panel);
          final fill = find.byWidgetPredicate(
            (widget) => widget is ColoredBox && widget.color == shade,
          );
          expect(fill, findsOneWidget, reason: panel.name);
          expect(
            tester.getRect(fill),
            tester.getRect(frame),
            reason: panel.name,
          );
          rig.panels.close();
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets(
      "清晰度: the phone's rows in its order as 10's plain rows, the playing one pink, 大会员 tagged",
      (tester) async {
        final rig = await pumpPad(tester);
        await openPanel(tester, rig, PlayerPanel.quality);
        final titles = [
          '自动',
          '4K 超高清',
          '1080P 高码率',
          '1080P 高清',
          '720P 准高清',
          '480P 标清',
          '360P 流畅',
        ];
        final tops = [
          for (final title in titles) tester.getCenter(find.text(title)).dy,
        ];
        for (var i = 1; i < tops.length; i++) {
          expect(
            tops[i] - tops[i - 1],
            closeTo(PadPanelTheme.qualityRow, 0.01),
          );
        }
        final middle = (tops.first + tops.last) / 2;
        expect(
          middle,
          closeTo(rig.size.height / 2 - PadPanelTheme.qualityLift, 0.5),
        );
        expect(
          tester.getTopLeft(find.text('4K 超高清')).dx,
          rig.size.width -
              PadPanelTheme.narrowWidth +
              PadPanelTheme.qualityLead,
        );
        expect(fontSize(tester, '4K 超高清'), PadPanelTheme.qualityText);
        expect(textColor(tester, '1080P 高码率'), PadPanelTheme.qualitySelected);
        expect(textColor(tester, '1080P 高清'), BiliColors.panelText);
        expect(find.text('大会员'), findsNWidgets(2));
        final badge = find
            .ancestor(
              of: find.text('大会员').first,
              matching: find.byType(Container),
            )
            .first;
        expect(tester.getSize(badge).height, PadPanelTheme.badgeHeight);
        expect(
          tester.getTopRight(badge).dx,
          rig.size.width - PadPanelTheme.qualityTrailing,
        );
        // The phone's header stays, so 高级设置 is still reachable.
        expect(find.text('清晰度'), findsOneWidget);
        expect(find.byKey(const ValueKey('quality-advanced')), findsOneWidget);
      },
    );

    testWidgets(
      '清晰度: a pick sets it and closes; 大会员 without the membership toasts and stays',
      (tester) async {
        final rig = await pumpPad(tester);
        await openPanel(tester, rig, PlayerPanel.quality);
        await tapText(tester, '4K 超高清');
        expect(rig.session.calls, isEmpty);
        expect(rig.panels.value, PlayerPanel.quality);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        await tapText(tester, '720P 准高清');
        expect(rig.session.calls, ['setQuality 64']);
        expect(rig.panels.value, isNull);

        await openPanel(tester, rig, PlayerPanel.quality);
        await tapText(tester, '自动');
        expect(rig.session.calls.last, startsWith('setQuality'));
        expect(rig.panels.value, isNull);
      },
    );

    testWidgets(
      '高级设置 opens 编码 in the same strip, a pick sets it and closes, the arrow goes back',
      (tester) async {
        final rig = await pumpPad(tester);
        await openPanel(tester, rig, PlayerPanel.quality);
        final before = tester.getRect(frame);
        await tester.tap(find.byKey(const ValueKey('quality-advanced')));
        await tester.pumpAndSettle();
        expect(rig.panels.value, PlayerPanel.codec);
        expect(tester.getRect(frame), before);
        expect(textColor(tester, 'HEVC'), PadPanelTheme.qualitySelected);
        await tester.tap(find.byKey(const ValueKey('panel-back')));
        await tester.pumpAndSettle();
        expect(rig.panels.value, PlayerPanel.quality);
        rig.panels.open(PlayerPanel.codec);
        await tester.pumpAndSettle();
        await tapText(tester, 'AV1');
        expect(rig.session.calls, ['setCodec av1']);
        expect(rig.panels.value, isNull);
      },
    );

    testWidgets(
      "倍速: the phone's seven values 58 pt apart, centred in the strip and on the screen",
      (tester) async {
        final rig = await pumpPad(tester);
        await openPanel(tester, rig, PlayerPanel.speed);
        final labels = [
          '3.0X',
          '2.0X',
          '1.5X',
          '1.25X',
          '1.0X',
          '0.75X',
          '0.5X',
        ];
        final centres = [
          for (final label in labels) tester.getCenter(find.text(label)),
        ];
        for (var i = 1; i < centres.length; i++) {
          expect(
            centres[i].dy - centres[i - 1].dy,
            closeTo(PadPanelTheme.speedRow, 0.01),
          );
        }
        expect(centres[3].dy, closeTo(rig.size.height / 2, 0.5));
        expect(
          centres[3].dx,
          closeTo(rig.size.width - PadPanelTheme.narrowWidth / 2, 0.5),
        );
        expect(fontSize(tester, '1.0X'), PadPanelTheme.speedText);
        expect(textColor(tester, '1.0X'), PadPanelTheme.speedSelected);
        await tapText(tester, '1.5X');
        expect(rig.session.calls, ['setRate 1.5']);
        expect(rig.panels.value, isNull);
      },
    );

    testWidgets("⋮: the phone's rows fit the strip, and still act", (
      tester,
    ) async {
      final rig = await pumpPad(tester);
      await openPanel(tester, rig, PlayerPanel.more);
      expect(tester.takeException(), isNull);
      final left =
          rig.size.width - PadPanelTheme.wideWidth + PadPanelTheme.moreInset;
      expect(tester.getTopLeft(find.text('定时关闭')).dx, left);
      final pip = find.bySemanticsLabel('小窗播放');
      expect(
        tester.getRect(pip).right,
        lessThanOrEqualTo(rig.size.width - PadPanelTheme.moreInset),
      );
      await tapText(tester, '自动连播');
      await tapText(tester, '30:00');
      await tapText(tester, '镜像翻转');
      expect(rig.session.calls, [
        'setAutoplayNext false',
        'setSleepTimer 30',
        'setMirrored true',
      ]);
      await tester.tap(find.byKey(const ValueKey('more-fit')));
      await tester.pumpAndSettle();
      await tapText(tester, '填充');
      expect(rig.session.calls.last, 'setFit fill');
    });

    testWidgets(
      '弹幕设置: its cards 288 pt wide, 16 from either edge, the first 80 pt down as in 12',
      (tester) async {
        final rig = await pumpPad(tester);
        await openPanel(tester, rig, PlayerPanel.danmakuSettings);
        final card = find
            .ancestor(
              of: find.text('显示区域'),
              matching: find.byType(DecoratedBox),
            )
            .first;
        final rect = tester.getRect(card);
        expect(
          rect.width,
          PadPanelTheme.wideWidth - 2 * DanmakuPanelTheme.inset,
        );
        expect(rect.right, rig.size.width - PadPanelTheme.trailing);
        expect(
          rect.top,
          24 + PadPanelTheme.danmakuTop + DanmakuPanelTheme.headerHeight,
        );
        final before = rig.ui.danmaku!.settings.value.filter.blockFixed;
        await tester.tap(find.byKey(const ValueKey('danmaku-type-fixed')));
        await tester.pumpAndSettle();
        expect(rig.ui.danmaku!.settings.value.filter.blockFixed, !before);
        await tester.tap(find.byKey(const ValueKey('danmaku-toggle-重复弹幕隐藏')));
        await tester.pumpAndSettle();
        expect(rig.ui.danmaku!.settings.value.filter.dedupe, isTrue);
      },
    );

    testWidgets('a tap outside closes every strip; a tap inside does not', (
      tester,
    ) async {
      final rig = await pumpPad(tester);
      for (final panel in [
        PlayerPanel.quality,
        PlayerPanel.speed,
        PlayerPanel.more,
        PlayerPanel.danmakuSettings,
      ]) {
        await openPanel(tester, rig, panel);
        await tester.tapAt(Offset(rig.size.width - 4, 4));
        await tester.pumpAndSettle();
        expect(rig.panels.value, panel, reason: panel.name);
        await tester.tapAt(Offset(rig.size.width / 3, rig.size.height / 2));
        await tester.pumpAndSettle();
        expect(rig.panels.value, isNull, reason: panel.name);
        expect(frame, findsNothing);
      }
    });

    testWidgets('closing from outside (the system back) slides the strip out', (
      tester,
    ) async {
      final rig = await pumpPad(tester);
      await openPanel(tester, rig, PlayerPanel.more);
      rig.panels.close();
      await tester.pumpAndSettle();
      expect(frame, findsNothing);
    });
  });

  testWidgets(
    "the iPhone's landscape keeps its shares of the width, the ramps and the cards",
    (tester) async {
      final rig = await pumpPad(tester, phone: true);
      final shares = {
        PlayerPanel.quality: BiliMetrics.panelQualityWidth,
        PlayerPanel.speed: BiliMetrics.panelSpeedWidth,
        PlayerPanel.more: BiliMetrics.panelMoreWidth,
        PlayerPanel.danmakuSettings: DanmakuPanelTheme.width,
      };
      for (final MapEntry(key: panel, value: share) in shares.entries) {
        await openPanel(tester, rig, panel);
        expect(
          tester.getSize(frame),
          Size(rig.size.width * share, rig.size.height),
          reason: panel.name,
        );
        rig.panels.close();
        await tester.pumpAndSettle();
      }
      await openPanel(tester, rig, PlayerPanel.quality);
      expect(fontSize(tester, '自动'), BiliMetrics.panelTitleText);
      expect(textColor(tester, '1080P 高码率'), BiliColors.pink);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == PadPanelTheme.shade,
        ),
        findsNothing,
      );
      await openPanel(tester, rig, PlayerPanel.speed);
      expect(
        tester.getCenter(find.text('1.5X')).dy -
            tester.getCenter(find.text('2.0X')).dy,
        closeTo(BiliMetrics.panelSpeedRow, 0.01),
      );
    },
  );

  group('on the iPad page', () {
    const band = PadPageTheme.statusBand;
    PadSheetFrame frameOf(double column, double playerBottom) => PadSheetFrame(
      player: Rect.fromLTRB(0, band, column, playerBottom),
      column: column,
    );
    Finder dim() => find.byType(PadSheetDim);
    bool dims(WidgetTester tester, Offset at) {
      final clip = tester.widget<ClipPath>(
        find.descendant(of: dim(), matching: find.byType(ClipPath)),
      );
      return clip.clipper!.getClip(tester.getSize(dim())).contains(at);
    }

    testWidgets(
      'sideways, the dark sheet keeps the phone height under the player in its column; all but the player dims',
      (tester) async {
        const column = 1194 - PadPageTheme.relatedWidth - PadPageTheme.rule;
        const playerBottom = 449.0;
        final rig = await pumpPad(
          tester,
          fullScreen: false,
          playerBottom: playerBottom,
          padFrame: frameOf(column, playerBottom),
        );
        await openPanel(tester, rig, PlayerPanel.speed);
        final rect = tester.getRect(frame);
        expect(rect.left, 0);
        expect(rect.width, column);
        expect(rect.bottom, rig.size.height);
        expect(
          rect.height,
          closeTo(
            BiliMetrics.panelSpeedSheetHeight * PadPanelTheme.phoneHeight,
            0.01,
          ),
        );
        expect(dims(tester, const Offset(column + 100, 200)), isTrue, reason: 'the related column beside the player');
        expect(dims(tester, const Offset(400, band / 2)), isTrue, reason: 'the band');
        expect(dims(tester, const Offset(400, 200)), isFalse, reason: 'the player');
        expect(
          tester.widget<ColoredBox>(find.descendant(of: dim(), matching: find.byType(ColoredBox))).color,
          BiliColors.sheetDim,
        );

        await openPanel(tester, rig, PlayerPanel.quality);
        expect(tester.getRect(frame).top, playerBottom);
        expect(find.text('自动'), findsOneWidget);
        await tapText(tester, '1080P 高清');
        expect(rig.session.calls, ['setQuality 80']);
      },
    );

    testWidgets(
      "upright, the light sheets hang from the player the screen's width; a tap on the band closes them",
      (tester) async {
        const playerBottom = 493.0;
        final rig = await pumpPad(
          tester,
          held: Held.upright,
          fullScreen: false,
          playerBottom: playerBottom,
          padFrame: frameOf(834, playerBottom),
        );
        await openPanel(tester, rig, PlayerPanel.danmakuSettings);
        expect(
          tester.getRect(frame),
          Rect.fromLTRB(0, playerBottom, 834, rig.size.height),
        );
        expect(dims(tester, const Offset(400, band / 2)), isTrue);
        expect(dims(tester, const Offset(400, 200)), isFalse);
        await tester.tapAt(const Offset(400, band / 2));
        await tester.pumpAndSettle();
        expect(rig.panels.value, isNull);
      },
    );

    testWidgets('in full screen the strips stay at the right with no page dim', (
      tester,
    ) async {
      final rig = await pumpPad(tester);
      await openPanel(tester, rig, PlayerPanel.more);
      expect(tester.getRect(frame).right, rig.size.width);
      expect(dim(), findsNothing);
    });
  });

  group('look-alike', () {
    // With BILIFAST_SHOTS naming a folder outside the repo, each panel's 2× shot is saved there for
    // tools/screen_diff.py against ipad/10-13.
    final shots = {
      PlayerPanel.quality: 'pad-10-quality',
      PlayerPanel.speed: 'pad-11-speed',
      PlayerPanel.danmakuSettings: 'pad-12-danmaku',
      PlayerPanel.more: 'pad-13-more',
    };
    for (final MapEntry(key: panel, value: name) in shots.entries) {
      testWidgets('$name renders under the system font without overflowing', (
        tester,
      ) async {
        final saved = BiliFonts.family;
        addTearDown(() => BiliFonts.family = saved);
        await tester.runAsync(loadSystemFontStandIns);
        BiliFonts.family = BiliFonts.system;
        final rig = await pumpPad(tester);
        await openPanel(tester, rig, panel);
        expect(tester.takeException(), isNull);
        final folder = Platform.environment['BILIFAST_SHOTS'];
        if (folder != null) {
          await saveShot(
            tester,
            find.byKey(const ValueKey('screen')),
            '$folder/$name.png',
            pixelRatio: 2,
          );
        }
      });
    }
  });
}
