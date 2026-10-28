import 'package:bili_core/api.dart' show VideoShot;
import 'package:bilifast/player/bili_player.dart' show PlayerStatus, StatusChanged;
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/player_ui/pad/pad_fullscreen_chrome.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/video/player_session.dart' show Episode;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';
import '../seek_preview_test.dart' show testSheets;
import 'pad_rig.dart';

void main() {
  Future<PadRig> mount(WidgetTester tester, {PadRig? rig, bool landscape = true}) async {
    final padRig = rig ?? rig08();
    await padRig.mount(tester, PadFullScreenChrome(ui: padRig.ui), landscape: landscape);
    await tester.pump();
    return padRig;
  }

  FakeVideoActions actionsOf(PadRig rig) => rig.details!.actions! as FakeVideoActions;

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  testWidgets('the top row: back, 点赞 with its count, 不喜欢, 投币, 收藏, 充电, 分享 and ⋮ each do their thing', (
    tester,
  ) async {
    final rig = await mount(tester);
    final actions = actionsOf(rig);
    expect(find.text('3959'), findsOneWidget);

    await tap(tester, 'pad-back');
    expect(rig.backs, 1);
    await tap(tester, 'pad-like');
    await tap(tester, 'pad-dislike');
    await tap(tester, 'pad-coin');
    await tap(tester, 'pad-favourite');
    await tap(tester, 'pad-share');
    expect(actions.calls, ['toggleLike', 'toggleDislike', 'ask coin', 'ask favourites', 'ask share']);
    expect(rig.chrome.shows, 5);

    await tap(tester, 'pad-charge');
    expect(find.text('暂不支持充电'), findsOneWidget);
    await drainToast(tester);

    await tap(tester, 'pad-more');
    expect(rig.panels.value, PlayerPanel.more);
  });

  testWidgets('N人正在看 and the uploader chip under the title; + 关注 follows and reads 已关注 after', (tester) async {
    final rig = await mount(tester);
    expect(find.text('4000+人正在看'), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);

    await tap(tester, 'pad-follow');
    expect(actionsOf(rig).calls, ['tapFollow']);
    actionsOf(rig)
      ..following = true
      ..notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('已关注'), findsOneWidget);
    expect(find.bySemanticsLabel('已关注'), findsOneWidget);
  });

  testWidgets('截图 saves and toasts; the lock turns the rotation lock on and off; no 截图 where frames cannot be taken', (
    tester,
  ) async {
    final rig = await mount(tester);
    await tap(tester, 'pad-capture');
    expect(rig.session.calls, ['captureFrame']);
    await tester.pump();
    expect(find.text('已保存到相册'), findsOneWidget);
    await drainToast(tester);

    expect(find.bySemanticsLabel('锁定屏幕方向'), findsOneWidget);
    await tap(tester, 'pad-lock');
    expect(rig.orientation.locked, isTrue);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('解锁屏幕方向'), findsOneWidget);

    rig.session
      ..canCaptureFrame = false
      ..changed();
    await tester.pump();
    expect(find.byKey(const ValueKey('pad-capture')), findsNothing);
    expect(find.byKey(const ValueKey('pad-lock')), findsOneWidget);
  });

  testWidgets('the bottom row: ▶, 弹, 弹幕设置, the field, 倍速, 1080P with 高码率, 小窗 and 退出全屏', (tester) async {
    final rig = await mount(tester);
    expect(find.byKey(const ValueKey('pad-quality-tag')), findsOneWidget);
    expect(find.text('高码率'), findsOneWidget);
    expect(find.text('1080P'), findsOneWidget);
    expect(find.text('倍速'), findsOneWidget);

    await tap(tester, 'pad-play');
    expect(rig.session.calls, ['togglePlay']);

    await tap(tester, 'pad-danmaku-settings');
    expect(rig.panels.value, PlayerPanel.danmakuSettings);
    rig.panels.close();
    await tester.pumpAndSettle();

    await tap(tester, 'pad-danmaku-field');
    expect(rig.danmaku!.session.sendOpen.value, isTrue);

    await tap(tester, 'pad-speed');
    expect(rig.panels.value, PlayerPanel.speed);
    rig.panels.close();
    await tester.pumpAndSettle();

    await tap(tester, 'pad-quality');
    expect(rig.panels.value, PlayerPanel.quality);
    rig.panels.close();
    await tester.pumpAndSettle();

    await tap(tester, 'pad-pip');
    expect(rig.session.calls.last, 'startPictureInPicture');

    await tap(tester, 'pad-exit');
    expect(rig.backs, 1);

    await tap(tester, 'pad-danmaku');
    expect(rig.session.calls.last, 'setDanmakuOn false');
    await tester.pump();
    // As on the phone (34), danmaku off closes the row up behind the toggle.
    expect(find.byKey(const ValueKey('pad-danmaku-field')), findsNothing);
    expect(find.byKey(const ValueKey('pad-danmaku-settings')), findsNothing);
  });

  testWidgets('a failed 小窗 toasts why; without 小窗 support it stays, faded, and only keeps the controls up', (
    tester,
  ) async {
    final rig = rig08()..session.failure = '小窗播放启动失败';
    await mount(tester, rig: rig);
    await tap(tester, 'pad-pip');
    await tester.pump();
    expect(find.text('小窗播放启动失败'), findsOneWidget);
    await drainToast(tester);

    rig.session
      ..pictureInPictureSupported = false
      ..changed();
    await tester.pump();
    final shows = rig.chrome.shows;
    final calls = rig.session.calls.length;
    await tap(tester, 'pad-pip');
    expect(rig.session.calls.length, calls);
    expect(rig.chrome.shows, shows + 1);
    expect(find.descendant(of: find.byKey(const ValueKey('pad-pip')), matching: find.byType(Opacity)), findsOneWidget);
  });

  testWidgets('⏮ plays the part before; at the first part or a single video it stays, half white, doing nothing', (
    tester,
  ) async {
    final rig = await mount(tester);
    await tap(tester, 'pad-prev');
    expect(rig.session.calls, isEmpty);
    expect(rig.chrome.shows, 1);

    rig.session
      ..episodes = const [
        Episode(bvid: 'BV1', cid: 1, title: 'P1', current: false),
        Episode(bvid: 'BV1', cid: 2, title: 'P2', current: true),
      ]
      ..changed();
    await tester.pump();
    await tap(tester, 'pad-prev');
    expect(rig.session.calls, ['playEpisode BV1 1']);
    // With parts, 选集 comes before 倍速 as on the phone.
    await tap(tester, 'pad-episodes');
    expect(rig.panels.value, PlayerPanel.episodes);
  });

  testWidgets('the field reads UP主已关闭弹幕 and opens nothing when the uploader closed danmaku', (tester) async {
    final rig = rig08();
    rig.danmaku!.feed.uploaderClosed = true;
    await mount(tester, rig: rig);
    expect(find.text('UP主已关闭弹幕'), findsOneWidget);
    await tap(tester, 'pad-danmaku-field');
    expect(rig.danmaku!.session.sendOpen.value, isFalse);
  });

  testWidgets('the chapter line names the chapter playing; the times are either side of the bar', (tester) async {
    final rig = await mount(tester);
    expect(find.text('章节 · 引言'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('04:14'), findsOneWidget);

    rig.session.clock.jump(100);
    rig.session.readout.refresh();
    await tester.pump();
    expect(find.text('章节 · 猎手出动'), findsOneWidget);
    expect(find.text('01:40'), findsOneWidget);

    rig.session
      ..chapters = const []
      ..changed();
    await tester.pump();
    expect(find.byKey(const ValueKey('pad-chapter')), findsNothing);
    // The bar keeps its place without chapters.
    expect(centreOf(tester, 'pad-bar').dy, closeTo(732, 1));
  });

  testWidgets('hidden: the controls fade and take no touches, 09\'s strip names the chapters; a panel hides both', (
    tester,
  ) async {
    final rig = await mount(tester);
    IgnorePointer chrome() => tester.widget<IgnorePointer>(find.byKey(const ValueKey('pad-chrome')));
    double stripOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: find.byKey(const ValueKey('pad-strip')), matching: find.byType(AnimatedOpacity)).first,
        )
        .opacity;
    expect(chrome().ignoring, isFalse);
    expect(stripOpacity(), 0);

    rig.chrome.hide();
    await tester.pumpAndSettle();
    expect(chrome().ignoring, isTrue);
    expect(stripOpacity(), 1);
    expect(find.text('选择藏匿点'), findsOneWidget);
    // Under 16:9's video, 752.8 pt down.
    expect(tester.getTopLeft(find.byKey(const ValueKey('pad-strip'))).dy, closeTo(752.8, 0.5));

    rig.panels.open(PlayerPanel.speed);
    await tester.pumpAndSettle();
    expect(stripOpacity(), 0);
    expect(chrome().ignoring, isTrue);
  });

  testSheets('holding the bar keeps the controls up and shows the preview over the TV', (tester) async {
    final rig = await mount(tester);
    rig.session.seekFrames.value = VideoShot(
      sheets: const ['https://i0.hdslb.com/bfs/videoshot/sheet.jpg'],
      columns: 10,
      rows: 10,
      times: [for (var i = 0; i <= 100; i++) i * 3],
    );
    final bar = find.byKey(const ValueKey('pad-bar'));
    final gesture = await tester.startGesture(tester.getCenter(bar));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.chrome.barHeld, isTrue);
    expect(rig.session.calls, contains('wantSeekFrames'));
    expect(tester.widget<IgnorePointer>(find.byKey(const ValueKey('pad-chrome'))).ignoring, isFalse);
    expect(
      tester.widget<AnimatedOpacity>(find.byKey(const ValueKey('seek-preview'))).opacity,
      1,
    );
    expect(find.byKey(const ValueKey('seek-preview-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('seek-preview-chapter')), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(rig.session.calls.last, startsWith('commitSeek'));
    expect(rig.chrome.barHeld, isFalse);
    // The sheets never load in tests; let the preview's fade finish.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the play glyph follows the player', (tester) async {
    final rig = await mount(tester);
    expect(find.bySemanticsLabel('播放'), findsOneWidget);
    rig.session.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('暂停'), findsOneWidget);
  });

  testWidgets('upright (no screenshot): the same bars at 834 wide, nothing overflowing, the title giving way', (
    tester,
  ) async {
    await mount(tester, landscape: false);
    expect(tester.takeException(), isNull);
    expect(centreOf(tester, 'pad-more').dx, closeTo(834 - 34, 1));
    expect(centreOf(tester, 'pad-like').dx, closeTo(834 - 454, 1));
    expect(centreOf(tester, 'pad-exit').dx, closeTo(834 - 34.2, 1));
    expect(centreOf(tester, 'pad-bar').dy, closeTo(1194 - 102, 1));
    final title = tester.getRect(find.byKey(const ValueKey('pad-title')));
    expect(title.right, lessThan(834 - 454 - 22));
    expect(tester.getSize(find.byKey(const ValueKey('pad-danmaku-field'))).width, greaterThan(200));
  });

  testWidgets('the phone keeps LandscapeChrome; the iPad chrome is its own', (tester) async {
    final rig = await mount(tester);
    expect(find.byType(LandscapeChrome), findsNothing);
    expect(find.byKey(const ValueKey('landscape-chrome')), findsNothing);
    expect(rig.ui.session, isNotNull);
  });
}
