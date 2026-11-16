import 'package:bili_core/api.dart';
import 'package:bilifast/live/danmaku/live_send_input.dart';
import 'package:bilifast/live/player/live_player_panels.dart';
import 'package:bilifast/live/player/live_player_view.dart';
import 'package:bilifast/live/rank/live_rank_sheet.dart';
import 'package:bilifast/live/room/live_overlays.dart';
import 'package:bilifast/live/room/live_room_page.dart';
import 'package:bilifast/live/room/room_header.dart';
import 'package:bilifast/live/room/room_more_sheet.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home/fake_login_gate.dart';
import 'room_support.dart';

void main() {
  late FakeLoginGate gate;

  setUp(() => gate = FakeLoginGate());

  Finder key(String name) => find.byKey(ValueKey(name));

  testWidgets('opening starts the model shown and the player; leaving disposes the player', (tester) async {
    final harness = await pumpRoom(tester, await roomServices(gate: gate));
    final model = harness.model!;
    expect(model.shown, [true]);
    expect(model.starts, 1);
    expect(harness.controller!.starts, 1);

    await tester.tap(key('live-room-back'));
    await settle(tester);
    expect(find.byType(LiveRoomPage), findsNothing);
    expect(harness.controller!.disposed, isTrue);
  });

  testWidgets('with the real model on FakeLiveApi the room draws the entry at once', (tester) async {
    await pumpRoom(tester, await roomServices(gate: gate), realModel: true);
    expect(find.text('入口主播'), findsOneWidget);
    expect(key('live-room-page'), findsOneWidget);
  });

  testWidgets("207's places: the capsule 7 under the safe area, the chips 52, the 16:9 box 138, the bar on the inset", (
    tester,
  ) async {
    await pumpRoom(tester, await roomServices(gate: gate));
    final capsule = tester.getRect(key('live-anchor'));
    expect(capsule.top, 69);
    expect(capsule.height, 36);
    expect(capsule.left, moreOrLessEquals(LiveRoomTheme.capsuleLeft));
    expect(tester.getRect(key('live-chip-0')).top, moreOrLessEquals(114));
    final box = tester.getRect(find.byType(LivePlayerView));
    expect((box.left, box.width), (0, 440));
    expect(box.height, moreOrLessEquals(247.5));
    expect(box.top, moreOrLessEquals(599.5 / 3), reason: '207: the box ends 1342 px down');
    expect(tester.widget<LivePlayerView>(find.byType(LivePlayerView)).fullScreen, isFalse);
    final more = tester.getRect(key('live-bar-more'));
    expect(more, const Rect.fromLTWH(12, 886, 36, 36));
    final chat = tester.getRect(key('live-chat'));
    expect(chat.top, moreOrLessEquals(1342 / 3));
    expect(chat.bottom, 886 - LiveRoomTheme.chatBottomGap);
  });

  testWidgets('the header: name, 点赞, 关注, the faces and the count; the faces open 高能榜', (tester) async {
    final harness = await pumpRoom(tester, await roomServices(gate: gate));
    expect(find.text('测试主播'), findsOneWidget);
    expect(find.text('12.4万点赞'), findsOneWidget);
    expect(key('live-follow'), findsOneWidget);
    expect(key('live-anchor-verified'), findsOneWidget);
    expect(find.text('9349'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(key('live-top-face-$i'), findsOneWidget);
    }
    expect(
      tester.getRect(key('live-top-face-1')).left - tester.getRect(key('live-top-face-0')).left,
      moreOrLessEquals(LiveRoomTheme.topFaceStep),
    );

    harness.model!.online = 12345;
    harness.model!.info = roomInfo();
    await settle(tester);
    expect(find.text('1万+'), findsOneWidget);

    await tester.tap(key('live-top-faces'));
    await settle(tester);
    expect(find.byType(LiveRankSheet), findsOneWidget);
    expect(tester.widget<LiveRankSheet>(find.byType(LiveRankSheet)).landscape, isFalse);
  });

  testWidgets('关注 follows and goes; followed rooms show none', (tester) async {
    final harness = await pumpRoom(tester, await roomServices(gate: gate));
    await tester.tap(key('live-follow'));
    await settle(tester);
    expect(harness.model!.follows, [true]);
    expect(key('live-follow'), findsNothing);
    expect(gate.requests, 0);
  });

  testWidgets('logged out, 关注 opens the login page and follows nothing', (tester) async {
    final harness = await pumpRoom(tester, await roomServices(loggedIn: false, gate: gate));
    await tester.tap(key('live-follow'));
    await settle(tester);
    expect(gate.requests, 1);
    expect(harness.model!.follows, isEmpty);
  });

  testWidgets('a 关注 Bilibili answers with a login request opens the login page; another failure toasts', (
    tester,
  ) async {
    final model = TestRoomModel(info: roomInfo())..followError = const BiliAPIError(code: -101, message: '账号未登录');
    await pumpRoom(tester, await roomServices(gate: gate), model: model);
    await tester.tap(key('live-follow'));
    await settle(tester);
    expect(gate.requests, 1);

    model.followError = const BiliAPIError(code: 22001, message: '不能关注自己');
    await tester.tap(key('live-follow'));
    await settle(tester);
    expect(find.text('不能关注自己'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('the rank chips and 更多直播 toast 暂未开放', (tester) async {
    await pumpRoom(tester, await roomServices(gate: gate));
    expect(find.text('热门榜'), findsOneWidget);
    expect(find.text('网游人气第 28'), findsOneWidget);
    await tester.tap(key('live-chip-0'));
    await settle(tester);
    expect(find.text('暂未开放'), findsOneWidget);
    await toastGone(tester);
    await tester.tap(key('live-more-rooms'));
    await settle(tester);
    expect(find.text('暂未开放'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('the bar: the input and its emote open the 弹幕 input; the gift and + toast', (tester) async {
    await pumpRoom(tester, await roomServices(gate: gate));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.tap(key('live-bar-input'));
    await settle(tester);
    expect(find.byType(LiveSendInput), findsOneWidget);
    expect(tester.widget<LiveSendInput>(find.byType(LiveSendInput)).landscape, isFalse);
    expect(tester.getRect(find.byType(LiveSendInput)), const Rect.fromLTWH(0, 0, 440, 956), reason: 'the whole screen');
    expect(MediaQuery.viewInsetsOf(tester.element(find.byType(LiveSendInput))).bottom, 300, reason: 'the keyboard');
    tester.view.resetViewInsets();
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(LiveSendInput), findsNothing);

    await tester.tap(key('live-bar-emote'));
    await settle(tester);
    expect(find.byType(LiveSendInput), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);

    for (final button in ['live-bar-gift', 'live-bar-plus']) {
      await tester.tap(key(button));
      await settle(tester);
      expect(find.text('暂未开放'), findsOneWidget, reason: button);
      await toastGone(tester);
    }
    expect(gate.requests, 0);
  });

  testWidgets('logged out, the input opens the login page, not the 弹幕 input', (tester) async {
    await pumpRoom(tester, await roomServices(loggedIn: false, gate: gate));
    await tester.tap(key('live-bar-input'));
    await settle(tester);
    expect(gate.requests, 1);
    expect(find.byType(LiveSendInput), findsNothing);
    expect(find.text('请先登录'), findsNothing);
  });

  group('221', () {
    Future<RoomHarness> openMore(WidgetTester tester) async {
      final harness = await pumpRoom(tester, await roomServices(gate: gate));
      await tester.tap(key('live-bar-more'));
      await settle(tester);
      expect(key('live-more-sheet'), findsOneWidget);
      return harness;
    }

    testWidgets('the sheet from 662 down; the targets and settings in 64 slots from 12', (tester) async {
      await openMore(tester);
      expect(tester.getRect(key('live-more-sheet')).top, 662);
      expect(find.text('分享'), findsOneWidget);
      expect(tester.getRect(key('live-share-facebook')).left, 12);
      expect(tester.getRect(key('live-share-x')).left, 76);
      expect(tester.getRect(key('live-more-pictureInPicture')).left, 12);
      for (final label in ['Facebook', 'X', 'WhatsApp', '微信', '朋友圈', '小窗播放', '播放设置', '助TA必火', '弹幕设置', '画质']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('a share target closes the sheet and shares the room', (tester) async {
      final harness = await openMore(tester);
      await tester.tap(key('live-share-weChat'));
      await settle(tester);
      expect(harness.controller!.shares, 1);
      expect(key('live-more-sheet'), findsNothing);
    });

    testWidgets('小窗播放 closes the sheet and starts the small window', (tester) async {
      final harness = await openMore(tester);
      await tester.tap(key('live-more-pictureInPicture'));
      await settle(tester);
      expect(harness.controller!.pips, 1);
      expect(key('live-more-sheet'), findsNothing);
    });

    testWidgets("弹幕设置 and 画质 open the player's portrait panels", (tester) async {
      await openMore(tester);
      await tester.tap(key('live-more-danmakuSettings'));
      await settle(tester);
      expect(key('live-more-sheet'), findsNothing);
      expect(tester.widget<LiveDanmakuSettingsPanel>(find.byType(LiveDanmakuSettingsPanel)).landscape, isFalse);
      await tester.binding.handlePopRoute();
      await settle(tester);

      await tester.tap(key('live-bar-more'));
      await settle(tester);
      await tester.tap(key('live-more-quality'));
      await settle(tester);
      expect(tester.widget<LiveQualityPicker>(find.byType(LiveQualityPicker)).landscape, isFalse);
    });

    testWidgets('every other item toasts 暂未开放 and keeps the sheet', (tester) async {
      await openMore(tester);
      for (final item in [RoomMoreItem.playSettings, RoomMoreItem.boost]) {
        await tester.tap(key('live-more-${item.name}'));
        await settle(tester);
        expect(find.text('暂未开放'), findsOneWidget, reason: item.label);
        expect(key('live-more-sheet'), findsOneWidget);
        await toastGone(tester);
      }
      await tester.drag(key('live-more-danmakuSettings'), const Offset(-400, 0));
      await settle(tester);
      await tester.tap(key('live-more-desktop'));
      await settle(tester);
      expect(find.text('暂未开放'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('a tap above the sheet closes it', (tester) async {
      await openMore(tester);
      await tester.tapAt(const Offset(220, 300));
      await settle(tester);
      expect(key('live-more-sheet'), findsNothing);
    });
  });

  testWidgets('back closes an open overlay first, then leaves the room', (tester) async {
    await pumpRoom(tester, await roomServices(gate: gate));
    await tester.tap(key('live-bar-more'));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(key('live-more-sheet'), findsNothing);
    expect(find.byType(LiveRoomPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(LiveRoomPage), findsNothing);
  });

  testWidgets('covered by a page: the socket and the player stand down, and come back when it leaves', (tester) async {
    final harness = await pumpRoom(tester, await roomServices(gate: gate));
    harness.navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SizedBox.expand()));
    await settle(tester);
    expect(harness.model!.shown, [true, false]);
    expect(harness.controller!.covered, [true]);

    harness.navigator.currentState!.pop();
    await settle(tester);
    expect(harness.model!.shown, [true, false, true]);
    expect(harness.controller!.covered, [true, false]);
  });

  testWidgets("the app away closes the socket and its return reopens it; the player's own rules stay", (tester) async {
    final harness = await pumpRoom(tester, await roomServices(gate: gate));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    expect(harness.model!.shown, [true, false]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(harness.model!.shown, [true, false, true]);
    expect(harness.controller!.covered, isEmpty);
  });

  group('a wide screen', () {
    testWidgets('lays the room out as the full-screen player with the landscape overlays', (tester) async {
      await pumpRoom(tester, await roomServices(gate: gate), landscape: true);
      expect(key('live-room-full-screen'), findsOneWidget);
      expect(find.byType(RoomHeader), findsNothing, reason: 'the full-screen player draws its own anchor');
      final view = tester.widget<LivePlayerView>(find.byType(LivePlayerView));
      expect(view.fullScreen, isTrue);
      expect(tester.getRect(find.byType(LivePlayerView)), const Rect.fromLTWH(0, 0, 956, 440));

      view.overlays.open(LiveOverlay.more);
      await settle(tester);
      expect(find.byType(LiveMorePanel), findsOneWidget);
      for (final (overlay, type) in [
        (LiveOverlay.quality, LiveQualityPicker),
        (LiveOverlay.danmakuSettings, LiveDanmakuSettingsPanel),
        (LiveOverlay.rank, LiveRankSheet),
        (LiveOverlay.send, LiveSendInput),
      ]) {
        view.overlays.open(overlay);
        await settle(tester);
        expect(find.byType(type), findsOneWidget, reason: '$overlay');
      }
      expect(tester.widget<LiveSendInput>(find.byType(LiveSendInput)).landscape, isTrue);
      expect(
        tester.getRect(find.byType(LiveSendInput)),
        const Rect.fromLTWH(0, 0, 956, 440),
        reason: 'the whole screen',
      );
    });

    testWidgets('a 关注 that wants a login turns the room upright before the login page', (tester) async {
      final model = TestRoomModel(info: roomInfo())..followError = const BiliAPIError(code: -101, message: '账号未登录');
      final harness = await pumpRoom(tester, await roomServices(gate: gate), model: model, landscape: true);
      harness.controller!.full = true;
      await tester.tap(key('live-follow'));
      await tester.pump();
      await tester.pump();
      expect(model.follows, [true]);
      expect(harness.controller!.fullScreenAsks, [false], reason: 'upright first');
      expect(gate.requests, 0, reason: 'not while the screen is still wide');

      tester.view
        ..physicalSize = const Size(440, 956)
        ..padding = const FakeViewPadding(top: 62, bottom: 34);
      await settle(tester, 20);
      expect(gate.requests, 1);
    });

    testWidgets('back closes an overlay, then leaves full screen, never the page', (tester) async {
      final harness = await pumpRoom(tester, await roomServices(gate: gate), landscape: true);
      final view = tester.widget<LivePlayerView>(find.byType(LivePlayerView));
      view.overlays.open(LiveOverlay.more);
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(LiveMorePanel), findsNothing);
      expect(harness.controller!.fullScreenAsks, isEmpty);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(harness.controller!.fullScreenAsks, [false]);
      expect(find.byType(LiveRoomPage), findsOneWidget);
    });
  });
}
