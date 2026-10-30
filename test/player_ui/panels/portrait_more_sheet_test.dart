import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/more_panel.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/portrait_more_sheet.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_player_session.dart';
import '../../support/fake_video_actions.dart';
import 'sheet_rig.dart';

void main() {
  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).first);
    await tester.pumpAndSettle();
  }

  Future<void> clearToast(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  group('in the small player', () {
    testWidgets('is the light sheet from the player down: the squares with 分享 last, then the rows of 42', (
      tester,
    ) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.more);
      expect(find.byType(PortraitMoreSheet), findsOneWidget);
      expect(find.byType(MorePanel), findsNothing);
      final frame = tester.getRect(find.byKey(const ValueKey('panel-frame')));
      expect(frame.top, closeTo(SheetRig.playerBottom, 0.01));
      expect(frame.bottom, 956);

      final squares = ['不感兴趣', '稍后再看', '缓存', '小窗播放', '投屏', '分享'];
      final lefts = [for (final title in squares) tester.getCenter(find.text(title)).dx];
      expect(lefts, [...lefts]..sort());
      expect(lefts.first, closeTo(DownloadSheetTheme.tileLead + DownloadSheetTheme.tileSize / 2, 0.5));

      final rows = ['倍速', '自动连播', '循环播放', '定时关闭', '后台听视频', '字幕', '弹幕设置', '镜像翻转', '画面尺寸', 'BTR 加速', '显示统计'];
      final tops = [for (final title in rows) tester.getTopLeft(find.text(title)).dy];
      expect(tops, [...tops]..sort());
      expect(tops[1] - tops[0], DownloadSheetTheme.rowHeight);
      for (final hidden in ['自动上滑', '单双击手势', '清晰度']) {
        expect(find.text(hidden), findsNothing);
      }
    });

    testWidgets('倍速, 自动连播, 循环播放, 镜像翻转 and the 测试 rows call the session and stay open', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.more);
      await tapText(tester, '1.5');
      await tapText(tester, '自动连播');
      await tapText(tester, '单集循环');
      await tapText(tester, '镜像翻转');
      await tapText(tester, 'BTR 加速');
      await tapText(tester, '显示统计');
      expect(rig.session.calls, [
        'setRate 1.5',
        'setAutoplayNext false',
        'setLoop single',
        'setMirrored true',
        'setBtr false',
        'setShowStats true',
      ]);
      expect(rig.panels.value, PlayerPanel.more);
    });

    testWidgets('倍速 opens on its fast end, 0.5 scrolled out of sight', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.more);
      final strip = tester.getRect(find.byKey(const ValueKey('more-speeds')));
      expect(tester.getRect(find.text('3.0')).right, lessThanOrEqualTo(strip.right));
      expect(tester.getCenter(find.text('0.5', skipOffstage: false)).dx, lessThan(strip.left));
      await tester.drag(find.byKey(const ValueKey('more-speeds')), const Offset(200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.5'));
      await tester.pumpAndSettle();
      expect(rig.session.calls, ['setRate 0.5']);
    });

    for (final (rate, label) in const [(0.5, '0.5'), (0.75, '0.75')]) {
      testWidgets('倍速 at $label opens with it in view and no value cut at an edge', (tester) async {
        // Under the system font, whose labels are as narrow as the phone's.
        final rig = await pumpSheetRig(tester, look: true, session: singleVideo()..rate = rate);
        await openSheet(tester, rig, PlayerPanel.more);
        final strip = tester.getRect(find.byKey(const ValueKey('more-speeds')));
        final clear = strip.left + DownloadSheetTheme.speedFade;
        final chosen = tester.getRect(find.text(label));
        expect(chosen.left, greaterThanOrEqualTo(clear));
        expect(chosen.right, lessThanOrEqualTo(strip.right));
        final labels = find.descendant(of: find.byKey(const ValueKey('more-speeds')), matching: find.byType(Text));
        for (final element in labels.evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          for (final edge in [clear, strip.right]) {
            expect(rect.left < edge && edge < rect.right, isFalse, reason: '${(element.widget as Text).data} cut');
          }
        }
      });
    }

    testWidgets('定时关闭 › opens its choices; a preset sets it and comes back showing the time left', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.more);
      await tapText(tester, '定时关闭');
      expect(find.text('不开启'), findsOneWidget);
      await tapText(tester, '30:00');
      expect(rig.session.calls, ['setSleepTimer 30']);
      expect(find.text('30:00 后暂停'), findsOneWidget);

      await tapText(tester, '定时关闭');
      await tapText(tester, '自定义');
      expect(find.byType(SleepWheel), findsOneWidget);
      await tapText(tester, '确定');
      expect(rig.session.calls.last, 'setSleepTimer 30');
      expect(find.text('倍速'), findsOneWidget);
    });

    testWidgets('画面尺寸 › opens its choices; a pick sets it and comes back', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.more);
      await tapText(tester, '画面尺寸');
      await tapText(tester, '16:9');
      expect(rig.session.calls, ['setFit ratio16x9']);
      expect(find.text('16:9'), findsOneWidget, reason: 'the row says what is set');
      await tapText(tester, '画面尺寸');
      await tester.tap(find.byKey(const ValueKey('more-page-back')));
      await tester.pumpAndSettle();
      expect(find.text('倍速'), findsOneWidget);
    });

    testWidgets('缓存 opens 缓存 in its place, 弹幕设置 opens its sheet', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.more);
      await tapText(tester, '缓存');
      expect(rig.panels.value, PlayerPanel.download);
      expect(find.text('缓存全部'), findsOneWidget);

      await openSheet(tester, rig, PlayerPanel.more);
      await tester.tap(find.byKey(const ValueKey('more-danmaku-settings')));
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.danmakuSettings);
    });

    testWidgets("a cached video's own page has no 缓存 square; the rest keep their order", (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo()..offline = true);
      await openSheet(tester, rig, PlayerPanel.more);
      expect(find.byKey(const ValueKey('more-download')), findsNothing);
      expect(find.text('缓存'), findsNothing);
      final lefts = [
        for (final title in ['不感兴趣', '稍后再看', '小窗播放', '投屏', '分享']) tester.getCenter(find.text(title)).dx,
      ];
      expect(lefts, [...lefts]..sort());
    });

    testWidgets('稍后再看 and 小窗播放 do what the panel does and close', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.more);
      await tester.tap(find.text('稍后再看'));
      await tester.pump();
      await tester.pump();
      expect(find.text('已添加至稍后再看'), findsOneWidget);
      expect(rig.panels.value, isNull);
      await clearToast(tester);

      await openSheet(tester, rig, PlayerPanel.more);
      await tapText(tester, '小窗播放');
      expect(rig.session.calls, ['watchLater', 'startPictureInPicture']);
      expect(rig.panels.value, isNull);
    });

    testWidgets('what the app can\'t serve toasts and stays open', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.more);
      for (final title in ['不感兴趣', '投屏', '后台听视频', '字幕']) {
        await tapText(tester, title);
        expect(find.text('暂未开放'), findsOneWidget, reason: title);
        expect(rig.panels.value, PlayerPanel.more);
        await clearToast(tester);
      }
      expect(rig.session.calls, isEmpty);
    });

    testWidgets("分享 hands the page's actions the share, which counts it, and closes", (tester) async {
      final actions = FakeVideoActions();
      final rig = await pumpSheetRig(
        tester,
        session: singleVideo(),
        details: FakePageDetails(actions: actions),
      );
      await openSheet(tester, rig, PlayerPanel.more);
      await tapText(tester, '分享');
      expect(actions.calls, ['ask share']);
      expect(rig.panels.value, isNull);
    });

    testWidgets('every square and row answers an accessibility press', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.more);
      tester.semantics.tap(find.semantics.byLabel('镜像翻转'));
      tester.semantics.tap(find.semantics.byLabel('1.25倍速'));
      tester.semantics.tap(find.semantics.byLabel('列表循环'));
      await tester.pumpAndSettle();
      expect(rig.session.calls, ['setMirrored true', 'setRate 1.25', 'setLoop list']);
      tester.semantics.tap(find.semantics.byLabel('缓存'));
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.download);
      handle.dispose();
    });
  });

  group('in 竖屏', () {
    testWidgets("is 573.67 pt tall with 43's rows: 自动上滑, 单双击手势 and 清晰度, no 循环播放 or 字幕", (tester) async {
      final session = singleVideo()..playing = 116;
      final rig = await pumpSheetRig(tester, session: session, presentation: Presentation.vertical);
      await openSheet(tester, rig, PlayerPanel.more);
      final frame = tester.getRect(find.byKey(const ValueKey('panel-frame')));
      expect(frame.height, closeTo(573.67, 0.01));
      final rows = ['倍速', '自动上滑', '定时关闭', '单双击手势', '后台听视频', '清晰度', '弹幕设置', '镜像翻转', '画面尺寸'];
      final tops = [for (final title in rows) tester.getTopLeft(find.text(title)).dy];
      expect(tops, [...tops]..sort());
      expect(find.text('单击暂停'), findsOneWidget);
      expect(find.text('1080P 60帧'), findsOneWidget);
      for (final hidden in ['自动连播', '循环播放', '字幕']) {
        expect(find.text(hidden), findsNothing);
      }

      await tapText(tester, '清晰度');
      expect(rig.panels.value, PlayerPanel.quality);
    });

    testWidgets('自动上滑 and 单双击手势 toast', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo(), presentation: Presentation.vertical);
      await openSheet(tester, rig, PlayerPanel.more);
      for (final title in ['自动上滑', '单双击手势']) {
        await tapText(tester, title);
        expect(find.text('暂未开放'), findsOneWidget, reason: title);
        await clearToast(tester);
      }
      expect(rig.session.calls, isEmpty);
    });
  });

  testWidgets("分享 without the page's actions hands the link to the share sheet", (tester) async {
    final session = FakePlayerSession()..shareLink = Uri.parse('https://www.bilibili.com/video/BV1');
    addTearDown(session.dispose);
    final panels = PanelController();
    final chrome = ChromeState();
    final orientation = OrientationController();
    addTearDown(() {
      panels.dispose();
      chrome.dispose();
      orientation.dispose();
    });
    final shared = <Uri>[];
    var closed = 0;
    final ui = PlayerUi(
      session: session,
      chrome: chrome,
      panels: panels,
      orientation: orientation,
      device: NoDeviceControls(),
      onBack: () {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 600,
          child: PortraitMoreSheet(
            ui: ui,
            toast: (_) {},
            close: () => closed++,
            share: (link) async {
              shared.add(link);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();
    expect(shared, [Uri.parse('https://www.bilibili.com/video/BV1')]);
    expect(closed, 1);
  });

  test('MoreRows sets presets and leaves 自定义 to its wheel', () {
    final session = FakePlayerSession();
    final rows = MoreRows(session: session, toast: (_) {}, close: () {});
    expect(rows.chooseSleep(SleepChoice.minutes60), isTrue);
    expect(rows.chooseSleep(SleepChoice.custom), isFalse);
    expect(session.calls, ['setSleepTimer 60']);
    expect(MoreRows.sleepItems(const Duration(minutes: 42)).last.$2, '42分钟');
    session.dispose();
  });
}
