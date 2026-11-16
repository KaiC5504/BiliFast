import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/live/player/live_player_panels.dart';
import 'package:bilifast/live/player/live_player_view.dart';
import 'package:bilifast/live/room/live_overlays.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_player_fakes.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

/// The player's controls hide by fading under an IgnorePointer that ignores while hidden.
bool _hidden(WidgetTester tester, String key) =>
    tester.widget<IgnorePointer>(find.ancestor(of: _key(key), matching: find.byType(IgnorePointer)).first).ignoring;

Future<void> _tapToast(WidgetTester tester, String key, String toast) async {
  await tester.tap(_key(key));
  await tester.pump();
  expect(
    find.descendant(of: _key('toast'), matching: find.text(toast)),
    findsOneWidget,
    reason: key,
  );
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  /// [rig]'s player on the page, playing; a host shows the overlays the player opens, as the room page will.
  Future<LiveOverlays> show(
    WidgetTester tester,
    LiveRig rig, {
    required bool landscape,
    List<String> chips = const ['热门榜', '网游人气第 28'],
    VoidCallback? onBack,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = landscape ? const Size(956, 440) : const Size(440, 956)
      ..padding = landscape
          ? const FakeViewPadding(left: 62, right: 62, bottom: 21)
          : const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = landscape
          ? const FakeViewPadding(left: 62, right: 62, bottom: 21)
          : const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final overlays = LiveOverlays();
    addTearDown(overlays.dispose);
    rig.room.infoValue = LiveRoomInfo(
      roomId: 7734200,
      uid: 50329118,
      title: '全国大赛 AQ vs LGD',
      anchorName: '夜莲 Annbbers',
      rankChips: chips,
    );
    await rig.controller.start();
    rig.room.go(LiveRoomState.live, play: playAt(10000));
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    final view = LivePlayerView(
      controller: rig.controller,
      room: rig.room,
      overlays: overlays,
      fullScreen: landscape,
      onBack: onBack ?? () {},
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: rig.services, child: child!),
        home: Stack(
          children: [
            if (landscape)
              Positioned.fill(child: view)
            else
              Positioned(left: 0, right: 0, top: liveBoxTop, height: liveBoxBottom - liveBoxTop, child: view),
            Positioned.fill(
              child: ValueListenableBuilder(
                valueListenable: overlays,
                builder: (context, overlay, _) => switch (overlay) {
                  LiveOverlay.more => LiveMorePanel(controller: rig.controller, room: rig.room, overlays: overlays),
                  LiveOverlay.quality => LiveQualityPicker(
                    controller: rig.controller,
                    room: rig.room,
                    overlays: overlays,
                    landscape: landscape,
                  ),
                  LiveOverlay.danmakuSettings => LiveDanmakuSettingsPanel(
                    controller: rig.controller,
                    overlays: overlays,
                    landscape: landscape,
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    return overlays;
  }

  Future<void> finish(WidgetTester tester, LiveRig rig) async {
    rig.controller.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  group('portrait (207, 208)', () {
    testWidgets('弹 and the full-screen button sit at the box\'s bottom right; 弹 toasts under the box', (tester) async {
      final rig = await liveRig();
      await show(tester, rig, landscape: false);
      final full = tester.getRect(_key('live-box-full-screen'));
      expect(full.right, closeTo(440 - LivePlayerTheme.boxButtonRight, 0.01));
      expect(full.bottom, closeTo(liveBoxBottom - LivePlayerTheme.boxButtonBottom, 0.01));
      expect(full.width, LivePlayerTheme.boxButton);
      final danmaku = tester.getRect(_key('live-box-danmaku'));
      expect(full.left - danmaku.right, closeTo(LivePlayerTheme.boxButtonGap, 0.01));

      await tester.tap(_key('live-box-danmaku'));
      await tester.pump();
      expect(rig.controller.danmakuOn, isFalse);
      final note = tester.getRect(_key('live-box-note'));
      expect(note.top, closeTo(liveBoxBottom + LivePlayerTheme.boxToastTop, 0.01));
      expect(note.center.dx, closeTo(220, 0.01));
      expect(note.height, closeTo(LivePlayerTheme.boxToastHeight, 0.01));
      expect(find.text('已关闭弹幕'), findsOneWidget);
      await tester.tap(_key('live-box-danmaku'));
      await tester.pump();
      expect(find.text('已开启弹幕'), findsOneWidget);

      await tester.tap(_key('live-box-full-screen'));
      await tester.pump();
      expect(rig.controller.fullScreen, isTrue);
      await finish(tester, rig);
    });

    testWidgets('a double tap is 点赞; logged out it opens the login page', (tester) async {
      final rig = await liveRig();
      await show(tester, rig, landscape: false);
      final box = tester.getCenter(_key('live-box-gestures'));
      await tester.tapAt(box);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(box);
      await tester.pump(const Duration(milliseconds: 400));
      expect(rig.room.asked, ['like']);
      await finish(tester, rig);

      final out = await liveRig(loggedIn: false);
      await show(tester, out, landscape: false);
      await tester.tapAt(box);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(box);
      await tester.pump(const Duration(milliseconds: 400));
      expect(out.room.asked, isEmpty);
      expect(out.gate.requests, 1);
      await finish(tester, out);
    });

    testWidgets('the loading TV while waiting, 重试 after a failure', (tester) async {
      final rig = await liveRig();
      await show(tester, rig, landscape: false);
      rig.room.go(LiveRoomState.live, play: playAt(400));
      await tester.pump();
      expect(_key('live-loading'), findsOneWidget);
      rig.player.emit(const PlayerFailed('x'));
      await tester.pump();
      rig.player.emit(const PlayerFailed('x'));
      await tester.pump();
      expect(_key('live-retry'), findsOneWidget);
      await tester.tap(_key('live-retry'));
      await tester.pump();
      expect(rig.room.asked.last, 'refresh');
      await finish(tester, rig);
    });

    testWidgets('画质 in portrait is a sheet of 210\'s rows, 自动 last', (tester) async {
      final rig = await liveRig();
      final overlays = await show(tester, rig, landscape: false);
      overlays.open(LiveOverlay.quality);
      await tester.pump();
      expect(find.text('画质'), findsOneWidget);
      final names = [for (final quality in qualities) quality.name, '自动'];
      final tops = [for (final name in names) tester.getTopLeft(find.text(name)).dy];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(tester.getRect(_key('live-quality-sheet')).bottom, 956);
      await tester.tap(find.text('自动'));
      await tester.pump();
      expect(overlays.value, LiveOverlay.none);
      expect(rig.room.asked, ['quality 0']);
      await finish(tester, rig);
    });
  });

  group('full screen (209)', () {
    testWidgets('every control does its job, the rest toast 暂未开放', (tester) async {
      final rig = await liveRig();
      var backs = 0;
      final overlays = await show(tester, rig, landscape: true, onBack: () => backs++);

      // Where 209 puts them.
      expect(tester.getCenter(_key('live-back')).dx, closeTo(62 + LivePlayerTheme.backCentre, 0.01));
      expect(tester.getCenter(_key('live-play')), Offset(62 + LivePlayerTheme.playCentre, 440 - 55));
      expect(tester.getCenter(_key('live-more')).dx, closeTo(956 - 62 - LivePlayerTheme.moreCentre, 0.01));
      expect(tester.getTopLeft(_key('live-anchor')).dx, 62 + LivePlayerTheme.anchorLeft);
      expect(find.text('12.4万点赞'), findsOneWidget);
      expect(find.text('9382'), findsOneWidget);
      expect(find.text('1080P'), findsOneWidget);

      await tester.tap(_key('live-back'));
      expect(backs, 1);

      await tester.tap(_key('live-follow'));
      await tester.pump();
      expect(rig.room.asked, ['follow true']);
      expect(_key('live-follow'), findsNothing);

      await tester.tap(_key('live-rank'));
      await tester.pump();
      expect(overlays.value, LiveOverlay.rank);
      overlays.close();
      await tester.pump();
      // The controls went with the layer; a tap brings them back.
      await tester.tap(find.byKey(const ValueKey('live-full-gestures')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(_key('live-share'));
      await tester.pump();
      expect(rig.shared, [Uri.parse('https://live.bilibili.com/7734200')]);

      await tester.tap(_key('live-more'));
      await tester.pump();
      expect(overlays.value, LiveOverlay.more);
      overlays.close();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('live-full-gestures')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(_key('live-quality'));
      await tester.pump();
      expect(overlays.value, LiveOverlay.quality);
      overlays.close();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('live-full-gestures')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(_key('live-play'));
      await tester.pump();
      expect(rig.controller.playing, isFalse);
      expect(rig.player.calls.last, 'pause');
      await tester.tap(_key('live-play'));
      await tester.pump();
      expect(rig.player.calls.last, 'play');

      await tester.tap(_key('live-refresh'));
      await tester.pump();
      expect(rig.room.asked.last, 'refresh');
      rig.player.emit(const StatusChanged(PlayerStatus.playing));

      await tester.tap(_key('live-danmaku'));
      await tester.pump();
      expect(rig.controller.danmakuOn, isFalse);
      expect(find.text('已关闭弹幕'), findsOneWidget);
      final note = tester.getRect(find.ancestor(of: find.text('已关闭弹幕'), matching: find.byType(Container)).first);
      expect(note.left, 62 + LivePlayerTheme.noteLeft);
      expect(note.bottom, closeTo(440 - LivePlayerTheme.noteBottom, 0.01));

      await _tapToast(tester, 'live-rank-chip-0', '暂未开放');
      await _tapToast(tester, 'live-rank-chip-1', '暂未开放');
      await _tapToast(tester, 'live-more-live', '暂未开放');
      await _tapToast(tester, 'live-watch', '暂未开放');
      await _tapToast(tester, 'live-gift', '暂未开放');
      await _tapToast(tester, 'live-plus', '暂未开放');
      await finish(tester, rig);
    });

    testWidgets('the controls hide 5 s after the last touch while it plays, and a tap brings them back', (
      tester,
    ) async {
      final rig = await liveRig();
      await show(tester, rig, landscape: true);
      expect(_hidden(tester, 'live-play'), isFalse);
      await tester.pump(const Duration(seconds: 4));
      expect(_hidden(tester, 'live-play'), isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(_hidden(tester, 'live-play'), isTrue);
      expect(_hidden(tester, 'live-lock'), isTrue);

      await tester.tapAt(const Offset(478, 220));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_hidden(tester, 'live-play'), isFalse);
      // Paused, they stay.
      await tester.tap(_key('live-play'));
      await tester.pump(const Duration(seconds: 6));
      expect(_hidden(tester, 'live-play'), isFalse);
      await tester.tapAt(const Offset(478, 220));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_hidden(tester, 'live-play'), isTrue);
      await finish(tester, rig);
    });

    testWidgets('locked, only the lock shows', (tester) async {
      final rig = await liveRig();
      await show(tester, rig, landscape: true);
      await rig.controller.setFullScreen(true);
      await tester.pump();
      final lock = tester.getRect(_key('live-lock'));
      expect(lock.center, Offset(62 + LivePlayerTheme.lockCentre, 220));
      expect(lock.width, closeTo(LivePlayerTheme.lockBox, 0.01));
      await tester.tap(_key('live-lock'));
      await tester.pump();
      expect(rig.controller.locked, isTrue);
      expect(_hidden(tester, 'live-play'), isTrue);
      expect(_hidden(tester, 'live-back'), isTrue);
      expect(_hidden(tester, 'live-lock'), isFalse);
      await tester.tap(_key('live-lock'));
      await tester.pump();
      expect(rig.controller.locked, isFalse);
      expect(_hidden(tester, 'live-play'), isFalse);
      await finish(tester, rig);
    });

    testWidgets('a side panel shrinks the picture into the room left of it (222)', (tester) async {
      final rig = await liveRig();
      final overlays = await show(tester, rig, landscape: true);
      expect(tester.getRect(_key('live-picture')), const Rect.fromLTWH(0, 0, 956, 440));
      overlays.open(LiveOverlay.more);
      await tester.pumpAndSettle();
      final picture = tester.getRect(_key('live-picture'));
      expect(picture.left, LivePlayerTheme.sidePictureLeft);
      expect(picture.right, closeTo(956 - LivePlayerTheme.sideWidth - LivePlayerTheme.sidePictureGap, 0.01));
      expect(picture.center.dy, closeTo(220, 0.01));
      expect(picture.width / picture.height, closeTo(16 / 9, 0.001));
      await finish(tester, rig);
    });
  });

  group('⋮ (222)', () {
    testWidgets('its thirteen buttons in 222\'s order; 分享, 小窗播放 and 弹幕设置 work, the rest toast', (tester) async {
      final rig = await liveRig();
      final overlays = await show(tester, rig, landscape: true);
      overlays.open(LiveOverlay.more);
      await tester.pumpAndSettle();
      final labels = [for (final item in LiveMoreItem.values) item.label];
      expect(labels, ['分享', '小窗播放', '播放设置', '助TA必火', '弹幕设置', '消费管理', '隐藏特效', '投屏', '举报', '反馈', '仅播声音', '色觉优化', '添至桌面']);
      for (final label in labels) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      final panel = tester.getRect(_key('live-more-panel'));
      expect(panel.left, 956 - LivePlayerTheme.sideWidth);
      final first = tester.getRect(find.descendant(of: _key('live-more-share'), matching: find.byType(Container)));
      expect(first.center, Offset(panel.left + LivePlayerTheme.moreFirstX, LivePlayerTheme.moreFirstY));
      final colour = tester.getCenter(find.descendant(of: _key('live-more-colour'), matching: find.byType(Container)));
      expect(
        colour,
        Offset(first.center.dx + 3 * LivePlayerTheme.moreColumn, first.center.dy + 2 * LivePlayerTheme.moreRow),
      );

      for (final item in LiveMoreItem.values) {
        if (item == LiveMoreItem.share || item == LiveMoreItem.pictureInPicture) continue;
        if (item == LiveMoreItem.danmakuSettings) continue;
        await _tapToast(tester, 'live-more-${item.name}', '暂未开放');
      }

      await tester.tap(_key('live-more-share'));
      await tester.pump();
      expect(overlays.value, LiveOverlay.none);
      expect(rig.shared, hasLength(1));

      overlays.open(LiveOverlay.more);
      await tester.pumpAndSettle();
      await tester.tap(_key('live-more-pictureInPicture'));
      await tester.pump();
      expect(rig.player.calls.last, 'pip start');

      overlays.open(LiveOverlay.more);
      await tester.pumpAndSettle();
      await tester.tap(_key('live-more-danmakuSettings'));
      await tester.pumpAndSettle();
      expect(overlays.value, LiveOverlay.danmakuSettings);
      expect(find.text('不透明度'), findsOneWidget);

      // A tap beside 弹幕设置 closes it, and the room's layer with it.
      await tester.tapAt(const Offset(200, 220));
      await tester.pumpAndSettle();
      expect(overlays.value, LiveOverlay.none);

      overlays.open(LiveOverlay.more);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 220));
      await tester.pump();
      expect(overlays.value, LiveOverlay.none);
      await finish(tester, rig);
    });
  });

  group('画质 (210)', () {
    testWidgets('画质增强 and the room\'s qualities on the right, the current one pink, 自动 last', (tester) async {
      final rig = await liveRig();
      final overlays = await show(tester, rig, landscape: true);
      overlays.open(LiveOverlay.quality);
      await tester.pumpAndSettle();
      expect(find.textContaining('画质增强'), findsOneWidget);
      final panel = tester.getRect(_key('live-quality-panel'));
      final first = tester.getRect(_key('live-quality-10000'));
      expect(first.top, LivePlayerTheme.qualityTop);
      expect(first.height, LivePlayerTheme.qualityRow);
      expect(first.left, panel.left + LivePlayerTheme.qualitySide);
      expect(tester.getTopLeft(_key('live-quality-400')).dy, first.bottom + LivePlayerTheme.qualityRowGap);
      expect(
        tester.getTopLeft(_key('live-quality-auto')).dy,
        greaterThan(tester.getTopLeft(_key('live-quality-250')).dy),
      );
      Color colour(String text) => tester.widget<Text>(find.text(text)).style!.color!;
      expect(colour('1080P 原画 (高帧率)'), BiliColors.pink);
      expect(colour('720P 超清'), BiliColors.panelText);
      expect(colour('自动'), BiliColors.panelText);

      await _tapToast(tester, 'live-quality-enhance', '暂未开放');

      await tester.tap(find.text('720P 超清'));
      await tester.pump();
      expect(overlays.value, LiveOverlay.none);
      expect(rig.room.asked, ['quality 250']);
      expect(find.text('切换中，请稍候'), findsOneWidget);
      rig.player.emit(const StatusChanged(PlayerStatus.playing));
      await tester.pump();
      expect(find.text('已成功切换至720P 超清'), findsOneWidget);
      await finish(tester, rig);
    });
  });

  group('弹幕设置', () {
    testWidgets('the video page\'s panel stands without a video page, as the portrait sheet too', (tester) async {
      final rig = await liveRig();
      final overlays = await show(tester, rig, landscape: false);
      overlays.open(LiveOverlay.danmakuSettings);
      await tester.pumpAndSettle();
      expect(find.text('不透明度'), findsOneWidget);
      // Above the sheet.
      await tester.tapAt(const Offset(220, 100));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(overlays.value, LiveOverlay.none);
      await finish(tester, rig);
    });
  });
}
