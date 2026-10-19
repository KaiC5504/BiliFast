import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/danmaku_panel_glyphs.dart';
import 'package:bilifast/player_ui/panels/danmaku_settings_panel.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../playback/fakes.dart';
import '../../support/fake_player_session.dart';

/// Everything the panel reaches, and what it asked for.
class SettingsRig {
  SettingsRig(this.ui, this.store, this.toasts);

  final PlayerUi ui;
  final DanmakuSettingsStore store;
  final List<String> toasts;

  PanelController get panels => ui.panels;

  DanmakuSettings get settings => store.value;
}

/// The page under the panel layer, with 弹幕设置 open: landscape (07) or the small player's light sheet (40).
Future<SettingsRig> pumpSettings(
  WidgetTester tester, {
  required bool landscape,
  DanmakuSettings settings = const DanmakuSettings(),
  bool loggedIn = true,
  double pixelRatio = 1,
  EdgeInsets padding = EdgeInsets.zero,
  double? playerBottom,
  Color background = BiliColors.videoBackground,
  Key? boundary,
}) async {
  final size = landscape ? const Size(956, 440) : const Size(440, 956);
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.padding = FakeViewPadding(
    left: padding.left * pixelRatio,
    top: padding.top * pixelRatio,
    right: padding.right * pixelRatio,
    bottom: padding.bottom * pixelRatio,
  );
  addTearDown(tester.view.reset);
  final orientation = OrientationController();
  if (landscape) orientation.enterLandscape();
  final chrome = ChromeState();
  final panels = PanelController();
  final session = FakePlayerSession();
  final store = DanmakuSettingsStore.memory(settings);
  final api = FakePageApi();
  final logger = Logger(session: 'test');
  final feed = DanmakuFeed(
    client: BiliClient(transport: Canned.http(), cookies: CookieJar(Canned.cookies), logger: logger),
    logger: logger,
  );
  final rules = BlockRuleStore(api: api, isLoggedIn: () => loggedIn);
  final danmaku = DanmakuSession(
    feed: feed,
    settings: store,
    rules: rules,
    api: api,
    target: () => null,
    position: () => 0,
    isLoggedIn: () => loggedIn,
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
  final toasts = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: boundary,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: background)),
            Positioned.fill(
              child: PanelLayer(ui: ui, playerBottom: playerBottom),
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
  panels.open(PlayerPanel.danmakuSettings);
  await tester.pumpAndSettle();
  return SettingsRig(ui, store, toasts);
}

Finder get panelFrame => find.byKey(const ValueKey('panel-frame'));

Future<void> tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder slider(String title) => find.byKey(ValueKey('danmaku-slider-$title'));

/// Taps the slider [share] of the way along its thumb's travel.
Future<void> tapSlider(WidgetTester tester, String title, double share) async {
  await tester.ensureVisible(slider(title));
  await tester.pumpAndSettle();
  final box = tester.getRect(slider(title));
  const inset = DanmakuPanelTheme.sliderThumbInset;
  await tester.tapAt(Offset(box.left + inset + share * (box.width - 2 * inset), box.center.dy));
  await tester.pumpAndSettle();
}

/// Lets a toast run out, so no timer is left when the test ends.
Future<void> clearToast(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  group('landscape', () {
    testWidgets('a hard-edged strip 382 wide with the rows of 07 in order', (tester) async {
      await pumpSettings(tester, landscape: true);
      expect(tester.getRect(panelFrame), const Rect.fromLTWH(574, 0, 382, 440));
      for (final title in [
        '弹幕设置',
        '查看更多',
        '显示区域',
        '不透明度',
        '画面防挡',
        '按弹幕类型屏蔽',
        '重复弹幕隐藏',
        '底部字幕区域防挡',
        '人像防挡',
        '更多工具',
        '弹幕观看屏蔽词',
        '添加屏蔽词',
        '当前弹幕列表',
        '重置弹幕设置',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('字体大小'), findsNothing);
      expect(find.text('弹幕速度'), findsNothing);
      expect(find.text('互动弹幕列表'), findsNothing);
      final shade = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).map((box) => box.color);
      expect(shade, contains(DanmakuPanelTheme.shade));
    });

    testWidgets('the cards run 16 in from the strip to 16 short of the safe area, the first 48 down', (tester) async {
      await pumpSettings(tester, landscape: true, padding: const EdgeInsets.only(left: 62, right: 62, bottom: 21));
      final card = find.ancestor(of: find.text('显示区域'), matching: find.byType(DecoratedBox)).first;
      expect(tester.getRect(card).left, 590);
      expect(tester.getRect(card).right, 878);
      expect(tester.getRect(card).top, 48);
      expect(tester.getRect(card).height, 2 * DanmakuPanelTheme.sliderRow);
    });

    testWidgets('scrolled to the end, 重置弹幕设置 sits 24 below the last card and the content ends at the bottom', (
      tester,
    ) async {
      await pumpSettings(tester, landscape: true, padding: const EdgeInsets.only(left: 62, right: 62, bottom: 21));
      await tester.drag(panelFrame, const Offset(0, -2000));
      await tester.pumpAndSettle();
      final reset = tester.getRect(find.byKey(const ValueKey('danmaku-reset')));
      expect(reset.bottom, closeTo(440 - DanmakuPanelTheme.endGap, 0.01));
      final card = find.ancestor(of: find.text('当前弹幕列表'), matching: find.byType(DecoratedBox)).last;
      expect(reset.center.dy - tester.getRect(card).bottom, closeTo(DanmakuPanelTheme.resetCentre, 0.01));
    });

    testWidgets('显示区域 snaps to its five stops and shows the share as a percentage', (tester) async {
      final rig = await pumpSettings(tester, landscape: true);
      expect(find.text('50%'), findsOneWidget);
      await tapSlider(tester, '显示区域', 0.1);
      expect(rig.settings.area, 0.1);
      expect(find.text('10%'), findsOneWidget);
      await tapSlider(tester, '显示区域', 0.7);
      expect(rig.settings.area, 0.75);
      await tapSlider(tester, '显示区域', 1);
      expect(rig.settings.area, 1);
      expect(find.text('100%'), findsWidgets);
    });

    testWidgets('不透明度 follows a drag, 20% to 100%', (tester) async {
      final rig = await pumpSettings(tester, landscape: true);
      await tapSlider(tester, '不透明度', 0);
      expect(rig.settings.opacity, 0.2);
      expect(find.text('20%'), findsOneWidget);
      await tapSlider(tester, '不透明度', 0.625);
      expect(rig.settings.opacity, 0.7);
      expect(find.text('70%'), findsOneWidget);
      final box = tester.getRect(slider('不透明度'));
      await tester.dragFrom(Offset(box.left + 10, box.center.dy), Offset(box.width, 0));
      await tester.pumpAndSettle();
      expect(rig.settings.opacity, 1);
    });

    testWidgets('a slider answers the accessibility increase and decrease', (tester) async {
      final rig = await pumpSettings(tester, landscape: true);
      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(find.ancestor(of: slider('显示区域'), matching: find.byType(Semantics)).first);
      expect(node.label, '显示区域');
      expect(node.value, '50%');
      expect(node.increasedValue, '75%');
      expect(node.decreasedValue, '25%');
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(rig.settings.area, 0.75);
      handle.dispose();
    });

    testWidgets('查看更多 adds 字体大小 and 弹幕速度 to the card, then goes', (tester) async {
      await pumpSettings(tester, landscape: true);
      final card = find.ancestor(of: find.text('显示区域'), matching: find.byType(DecoratedBox)).first;
      await tapKey(tester, 'danmaku-more');
      expect(find.text('查看更多'), findsNothing);
      expect(find.text('字体大小'), findsOneWidget);
      expect(find.text('弹幕速度'), findsOneWidget);
      expect(find.text('100%'), findsWidgets);
      expect(find.text('适中'), findsOneWidget);
      expect(tester.getRect(card).height, 4 * DanmakuPanelTheme.sliderRow);
    });

    testWidgets('字体大小 runs 50% to 200%; 弹幕速度 snaps to 极慢 … 极快', (tester) async {
      final rig = await pumpSettings(tester, landscape: true);
      await tapKey(tester, 'danmaku-more');
      await tapSlider(tester, '字体大小', 1);
      expect(rig.settings.scale, 2);
      expect(find.text('200%'), findsOneWidget);
      await tapSlider(tester, '字体大小', 0);
      expect(rig.settings.scale, 0.5);
      for (final (share, speed, name) in [(0.0, 0, '极慢'), (0.3, 1, '较慢'), (0.74, 3, '较快'), (1.0, 4, '极快')]) {
        await tapSlider(tester, '弹幕速度', share);
        expect(rig.settings.speed, speed);
        expect(find.text(name), findsOneWidget);
      }
    });

    for (final (key, read) in <(String, bool Function(DanmakuSettings))>[
      ('fixed', (settings) => settings.filter.blockFixed),
      ('scroll', (settings) => settings.filter.blockScroll),
      ('colored', (settings) => settings.filter.blockColored),
      ('advanced', (settings) => settings.filter.blockAdvanced),
      ('count', (settings) => settings.filter.blockCount),
    ]) {
      testWidgets('the $key square blocks its type, pink with the ⊘, and a second tap lets it back', (tester) async {
        final rig = await pumpSettings(tester, landscape: true);
        DanmakuPanelGlyph glyph() => tester.widget<DanmakuPanelGlyph>(
          find.descendant(of: find.byKey(ValueKey('danmaku-type-$key')), matching: find.byType(DanmakuPanelGlyph)),
        );
        expect(glyph().blocked, isFalse);
        await tapKey(tester, 'danmaku-type-$key');
        expect(read(rig.settings), isTrue);
        expect(glyph().blocked, isTrue);
        expect(glyph().color, BiliColors.pink);
        await tapKey(tester, 'danmaku-type-$key');
        expect(read(rig.settings), isFalse);
        expect(glyph().color, DanmakuPanelTheme.text);
      });
    }

    for (final (title, read) in <(String, bool Function(DanmakuSettings))>[
      ('重复弹幕隐藏', (settings) => settings.filter.dedupe),
      ('底部字幕区域防挡', (settings) => settings.filter.hideBottom),
      ('弹幕观看屏蔽词', (settings) => settings.filter.applyRules),
    ]) {
      testWidgets('$title switches and switches back', (tester) async {
        final rig = await pumpSettings(tester, landscape: true);
        final before = read(rig.settings);
        await tapKey(tester, 'danmaku-toggle-$title');
        expect(read(rig.settings), !before);
        await tapKey(tester, 'danmaku-toggle-$title');
        expect(read(rig.settings), before);
      });
    }

    testWidgets('人像防挡 stays off and says it comes later', (tester) async {
      final rig = await pumpSettings(tester, landscape: true);
      final before = rig.settings;
      await tapKey(tester, 'danmaku-toggle-人像防挡');
      expect(find.text(DanmakuSettingsPanel.portraitSoon), findsOneWidget);
      expect(rig.settings, before);
      await clearToast(tester);
    });

    testWidgets('添加屏蔽词 opens its panel', (tester) async {
      final rig = await pumpSettings(tester, landscape: true);
      await tapKey(tester, 'danmaku-block-words');
      expect(rig.panels.value, PlayerPanel.blockWords);
    });

    testWidgets('logged out, 添加屏蔽词 asks to log in and stays', (tester) async {
      final rig = await pumpSettings(tester, landscape: true, loggedIn: false);
      await tapKey(tester, 'danmaku-block-words');
      expect(find.text(DanmakuSettingsPanel.loginFirst), findsOneWidget);
      expect(rig.panels.value, PlayerPanel.danmakuSettings);
      await clearToast(tester);
    });

    testWidgets('当前弹幕列表 opens its panel', (tester) async {
      final rig = await pumpSettings(tester, landscape: true);
      await tapKey(tester, 'danmaku-list');
      expect(rig.panels.value, PlayerPanel.danmakuList);
    });

    testWidgets('重置弹幕设置 asks first; 我再想想 keeps the settings', (tester) async {
      const changed = DanmakuSettings(area: 0.1, opacity: 0.5, speed: 4);
      final rig = await pumpSettings(tester, landscape: true, settings: changed);
      await tapKey(tester, 'danmaku-reset');
      final dialog = find.byKey(const ValueKey('panel-confirm'));
      expect(dialog, findsOneWidget);
      expect(tester.getRect(dialog).center, const Offset(478, 220));
      expect(tester.getSize(dialog).width, DanmakuPanelTheme.dialogWidth);
      expect(find.text('我再想想'), findsOneWidget);
      expect(find.text('确定'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('panel-confirm-cancel')));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(rig.settings, changed);
      expect(rig.panels.value, PlayerPanel.danmakuSettings);
    });

    testWidgets('重置弹幕设置 then 确定 puts every value back', (tester) async {
      final rig = await pumpSettings(
        tester,
        landscape: true,
        settings: const DanmakuSettings(area: 0.1, opacity: 0.5, scale: 1.5, speed: 4),
      );
      await tapKey(tester, 'danmaku-reset');
      await tester.tap(find.byKey(const ValueKey('panel-confirm-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('panel-confirm')), findsNothing);
      expect(rig.settings, const DanmakuSettings());
      expect(rig.panels.value, PlayerPanel.danmakuSettings);
    });

    testWidgets('closing the panel takes the confirm with it', (tester) async {
      final rig = await pumpSettings(tester, landscape: true);
      await tapKey(tester, 'danmaku-reset');
      rig.panels.close();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('panel-confirm')), findsNothing);
    });

    testWidgets('every control carries a label for accessibility presses', (tester) async {
      await pumpSettings(tester, landscape: true);
      final handle = tester.ensureSemantics();
      for (final label in [
        '查看更多',
        '固定',
        '滚动',
        '彩色',
        '高级',
        '计数',
        '重复弹幕隐藏',
        '底部字幕区域防挡',
        '人像防挡',
        '弹幕观看屏蔽词',
        '添加屏蔽词',
        '当前弹幕列表',
        '重置弹幕设置',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      for (final title in ['显示区域', '不透明度']) {
        final node = tester.getSemantics(find.ancestor(of: slider(title), matching: find.byType(Semantics)).first);
        expect(node.label, title);
        expect(node.flagsCollection.isSlider, isTrue);
      }
      handle.dispose();
    });
  });

  group('portrait', () {
    testWidgets("the light sheet from the player down, on 40's grey, without the landscape-only rows", (tester) async {
      await pumpSettings(tester, landscape: false, playerBottom: 459);
      expect(tester.getRect(panelFrame).top, 459);
      expect(tester.getRect(panelFrame).bottom, 956);
      final sheet = tester.widget<DecoratedBox>(
        find.descendant(of: panelFrame, matching: find.byType(DecoratedBox)).first,
      );
      expect((sheet.decoration as BoxDecoration).color, DanmakuPanelTheme.lightBackground);
      for (final title in ['弹幕设置', '不透明度', '字体大小', '弹幕速度', '按弹幕类型屏蔽', '重复弹幕隐藏', '人像防挡', '弹幕观看屏蔽词', '重置弹幕设置']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      for (final title in ['显示区域', '查看更多', '底部字幕区域防挡', '添加屏蔽词', '当前弹幕列表']) {
        expect(find.text(title), findsNothing, reason: title);
      }
    });

    testWidgets('the sliders, squares and switches write the settings there too', (tester) async {
      final rig = await pumpSettings(tester, landscape: false, playerBottom: 459);
      await tapSlider(tester, '不透明度', 0.625);
      expect(rig.settings.opacity, 0.7);
      await tapSlider(tester, '字体大小', 1);
      expect(rig.settings.scale, 2);
      await tapSlider(tester, '弹幕速度', 0);
      expect(rig.settings.speed, 0);
      await tapKey(tester, 'danmaku-type-colored');
      expect(rig.settings.filter.blockColored, isTrue);
      await tapKey(tester, 'danmaku-toggle-重复弹幕隐藏');
      expect(rig.settings.filter.dedupe, isTrue);
      await tapKey(tester, 'danmaku-toggle-弹幕观看屏蔽词');
      expect(rig.settings.filter.applyRules, isFalse);
    });

    testWidgets('重置弹幕设置 asks over the whole screen there too', (tester) async {
      final rig = await pumpSettings(
        tester,
        landscape: false,
        playerBottom: 459,
        settings: const DanmakuSettings(speed: 0),
      );
      await tapKey(tester, 'danmaku-reset');
      expect(tester.getRect(find.byKey(const ValueKey('panel-confirm'))).center, const Offset(220, 478));
      await tester.tap(find.byKey(const ValueKey('panel-confirm-ok')));
      await tester.pumpAndSettle();
      expect(rig.settings, const DanmakuSettings());
    });
  });
}
