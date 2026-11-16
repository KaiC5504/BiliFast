import 'dart:convert';
import 'dart:io';

import 'package:bilifast/live/player/live_player_controller.dart';
import 'package:bilifast/live/player/live_player_prefs.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_player_fakes.dart';

void main() {
  /// A rig started and live at 原画, its stream playing.
  Future<LiveRig> playing(WidgetTester tester, {PlayerPrefs? playerPrefs, bool muted = false}) async {
    final rig = await liveRig(playerPrefs: playerPrefs, muted: muted);
    await rig.controller.start();
    rig.room.go(LiveRoomState.live, play: playAt(10000));
    await tester.pump();
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump();
    return rig;
  }

  List<String> loads(LiveRig rig) => [
    for (final call in rig.player.calls)
      if (call.startsWith('load ')) call,
  ];

  testWidgets('waits for the play info, then plays the stream straight on the player with the stream headers', (
    tester,
  ) async {
    final rig = await liveRig();
    await rig.controller.start();
    expect(rig.controller.phase, LivePlayerPhase.waiting);
    expect(loads(rig), isEmpty);

    rig.room.go(LiveRoomState.live, play: playAt(10000));
    await tester.pump();
    expect(loads(rig), ['load https://example.invalid/live/10000/0/index.m3u8']);
    expect(rig.player.loaded!.autoplay, isTrue);
    expect(rig.player.loaded!.headers, rig.room.api.streamHeaders);
    expect(rig.controller.phase, LivePlayerPhase.loading);

    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump();
    expect(rig.controller.phase, LivePlayerPhase.playing);
    expect(rig.controller.playing, isTrue);
    expect(rig.controller.quality?.name, '1080P 原画 (高帧率)');
    // The lock screen: the room's title and anchor, no timeline (the player marks the stream live itself).
    expect(rig.player.nowPlaying?.title, '全国大赛 AQ vs LGD');
    expect(rig.player.nowPlaying?.artist, '夜莲 Annbbers');
    expect(rig.player.nowPlaying?.hasNext, isFalse);
    expect(rig.player.nowPlaying?.hasPrevious, isFalse);
    expect(rig.player.calls, contains('pip auto true'));

    // A notify that changes nothing of the stream loads nothing again.
    rig.room.go(LiveRoomState.live);
    await tester.pump();
    expect(loads(rig), hasLength(1));
  });

  testWidgets('--mute mutes the player before anything loads', (tester) async {
    final rig = await liveRig(muted: true);
    await rig.controller.start();
    rig.room.go(LiveRoomState.live, play: playAt(10000));
    await tester.pump();
    expect(rig.player.calls.indexOf('muted true'), lessThan(rig.player.calls.indexWhere((c) => c.startsWith('load'))));
    rig.controller.dispose();
  });

  testWidgets('a quality switch toasts 切换中，请稍候, loads its stream and toasts 已成功切换至 once it plays', (tester) async {
    final rig = await playing(tester);
    await rig.controller.pickQuality(qualities[2]);
    await tester.pump();
    expect(rig.room.asked, ['quality 250']);
    expect(rig.controller.notices.shown.map((n) => n.text), ['切换中，请稍候']);
    expect(loads(rig).last, 'load https://example.invalid/live/250/1/index.m3u8');

    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump();
    expect(rig.controller.notices.shown.map((n) => n.text), ['切换中，请稍候', '已成功切换至720P 超清']);

    // 210 picks 1080P 原画 (高帧率) and says 已成功切换至1080P 原画.
    await rig.controller.pickQuality(qualities[0]);
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump();
    expect(rig.controller.notices.shown.last.text, '已成功切换至1080P 原画');

    // The quality playing asks nothing; 自动 asks the room's default.
    await rig.controller.pickQuality(qualities[0]);
    expect(rig.room.asked, ['quality 250', 'quality 10000']);
    await rig.controller.pickQuality(null);
    expect(rig.room.asked.last, 'quality 0');
    expect(rig.controller.autoQuality, isTrue);

    await tester.pump(LivePlayerTheme.noteShown);
    expect(rig.controller.notices.shown, isEmpty);
    rig.controller.dispose();
  });

  testWidgets('⟳ asks the room for its stream again and loads it', (tester) async {
    final rig = await playing(tester);
    await rig.controller.refreshStream();
    await tester.pump();
    expect(rig.room.asked, ['refresh']);
    expect(loads(rig), hasLength(2));
    expect(rig.controller.phase, LivePlayerPhase.loading);
    rig.controller.dispose();
  });

  testWidgets('a stall asks a fresh stream once; a second shows 重试, which asks again', (tester) async {
    final rig = await playing(tester);
    rig.player.emit(const StatusChanged(PlayerStatus.buffering));
    await tester.pump(const Duration(seconds: 1));
    expect(rig.room.asked, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(rig.room.asked, ['refresh']);
    expect(loads(rig), hasLength(2));

    // The fresh stream stalls too.
    rig.player.emit(const StatusChanged(PlayerStatus.buffering));
    await tester.pump(const Duration(seconds: 2));
    expect(rig.room.asked, ['refresh']);
    expect(rig.controller.phase, LivePlayerPhase.failed);
    expect(rig.player.calls, contains('unload'));

    await rig.controller.retry();
    await tester.pump();
    expect(rig.room.asked, ['refresh', 'refresh']);
    expect(rig.controller.phase, LivePlayerPhase.loading);
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump();
    expect(rig.controller.phase, LivePlayerPhase.playing);

    // Having played, the next failure gets its one fresh stream again.
    rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    await tester.pump();
    expect(rig.room.asked, ['refresh', 'refresh', 'refresh']);
    expect(rig.controller.phase, LivePlayerPhase.loading);
    rig.controller.dispose();
  });

  testWidgets('a fresh stream the room fails to give shows 重试', (tester) async {
    final rig = await playing(tester);
    rig.room.refreshError = StateError('no stream');
    rig.player.emit(const PlayerFailed('网络连接失败，请检查网络后重试'));
    await tester.pump();
    expect(rig.controller.phase, LivePlayerPhase.failed);
  });

  testWidgets('a room that ends unloads the stream; a failed play info shows 重试, which asks the room again', (
    tester,
  ) async {
    final rig = await playing(tester);
    rig.room.go(LiveRoomState.ended);
    await tester.pump();
    expect(rig.controller.phase, LivePlayerPhase.ended);
    expect(rig.player.calls, contains('unload'));

    final failed = await liveRig();
    await failed.controller.start();
    failed.room.go(LiveRoomState.failed);
    await tester.pump();
    expect(failed.controller.phase, LivePlayerPhase.failed);
    await failed.controller.retry();
    await tester.pump();
    expect(failed.room.asked, ['retry']);
    expect(loads(failed), hasLength(1));
    failed.controller.dispose();
  });

  testWidgets('covered, it pauses and drops auto picture in picture; shown, it resumes only if it was playing', (
    tester,
  ) async {
    final rig = await playing(tester);
    rig.player.calls.clear();
    rig.controller.setCovered(true);
    await tester.pump();
    expect(rig.player.calls, containsAllInOrder(['pip stop', 'pause', 'pip auto false']));
    rig.player.emit(const StatusChanged(PlayerStatus.paused));
    await tester.pump();
    // Covered, the lock screen is the page on top's.
    expect(rig.player.nowPlaying, isNull);

    rig.player.calls.clear();
    rig.controller.setCovered(false);
    await tester.pump();
    expect(rig.player.calls, containsAllInOrder(['pip auto true', 'play']));

    // Paused by the user, it stays paused when shown again.
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await rig.controller.togglePlay();
    rig.player.emit(const StatusChanged(PlayerStatus.paused));
    await tester.pump();
    expect(rig.controller.phase, LivePlayerPhase.paused);
    rig.controller.setCovered(true);
    rig.player.calls.clear();
    rig.controller.setCovered(false);
    await tester.pump();
    expect(rig.player.calls, isNot(contains('play')));
  });

  testWidgets('a stream loaded while covered loads paused', (tester) async {
    final rig = await liveRig();
    await rig.controller.start();
    rig.controller.setCovered(true);
    rig.room.go(LiveRoomState.live, play: playAt(10000));
    await tester.pump();
    expect(rig.player.loaded!.autoplay, isFalse);
  });

  testWidgets('⏸ and ▶, and the lock screen\'s buttons; live has no seek', (tester) async {
    final rig = await playing(tester);
    await rig.controller.togglePlay();
    expect(rig.player.calls.last, 'pause');
    expect(rig.controller.playing, isFalse);
    await rig.controller.togglePlay();
    expect(rig.player.calls.last, 'play');

    rig.player.emit(const RemoteCommand(RemoteCommandKind.pause));
    await tester.pump();
    expect(rig.controller.playing, isFalse);
    rig.player.calls.clear();
    rig.player.emit(const RemoteCommand(RemoteCommandKind.seek, seconds: 10));
    rig.player.emit(const RemoteCommand(RemoteCommandKind.next));
    await tester.pump();
    expect(rig.player.calls.where((call) => call.startsWith('seek') || call.startsWith('load')), isEmpty);
    rig.player.emit(const RemoteCommand(RemoteCommandKind.toggle));
    await tester.pump();
    expect(rig.controller.playing, isTrue);
  });

  testWidgets('with 后台听视频 off the stream pauses away from the screen and plays again on return', (tester) async {
    final prefs = PlayerPrefs.memory()..backgroundListen = false;
    final rig = await playing(tester, playerPrefs: prefs);
    expect(rig.player.calls, contains('background false'));
    rig.player.calls.clear();
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(rig.player.calls, contains('pause'));
    expect(rig.player.nowPlaying, isNull);
    rig.player.emit(const StatusChanged(PlayerStatus.paused));
    await tester.pump();
    expect(rig.controller.playing, isTrue);

    rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(rig.player.calls, contains('play'));
  });

  testWidgets('with 后台听视频 on, or in the small window, it plays on away', (tester) async {
    final rig = await playing(tester);
    rig.player.calls.clear();
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    expect(rig.player.calls, isNot(contains('pause')));

    final off = await playing(tester, playerPrefs: PlayerPrefs.memory()..backgroundListen = false);
    await off.controller.startPictureInPicture();
    expect(off.player.calls.last, 'pip start');
    off.player.emit(const PictureInPictureChanged(true));
    off.player.calls.clear();
    off.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    expect(off.player.calls, isNot(contains('pause')));
    expect(off.controller.pictureInPicture, isTrue);
  });

  testWidgets('an interruption that ends asking to resume plays again', (tester) async {
    final rig = await playing(tester);
    rig.player.emit(const AudioInterruption(began: true));
    rig.player.emit(const StatusChanged(PlayerStatus.paused));
    rig.player.calls.clear();
    rig.player.emit(const AudioInterruption(began: false, shouldResume: true));
    await tester.pump();
    expect(rig.player.calls, ['play']);
  });

  testWidgets('弹 is kept between rooms and toasts its state', (tester) async {
    final prefs = LivePlayerPrefs.memory();
    final rig = await liveRig(prefs: prefs);
    expect(rig.controller.danmakuOn, isTrue);
    rig.controller.setDanmakuOn(false);
    expect(rig.controller.notices.shown.single.text, '已关闭弹幕');
    final next = await liveRig(prefs: prefs);
    expect(next.controller.danmakuOn, isFalse);
    next.controller.setDanmakuOn(true);
    expect(next.controller.notices.shown.single.text, '已开启弹幕');
    expect(prefs.danmakuOn, isTrue);
    rig.controller.dispose();
    next.controller.dispose();
  });

  test('弹 survives in live_player.json', () async {
    final folder = await Directory.systemTemp.createTemp('live_prefs');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}${Platform.pathSeparator}live_player.json';
    final prefs = LivePlayerPrefs.loadFrom(path)..danmakuOn = false;
    await prefs.settle();
    expect(jsonDecode(await File(path).readAsString()), {'danmakuOn': false});
    expect(LivePlayerPrefs.loadFrom(path).danmakuOn, isFalse);
    await File(path).writeAsString('{not json');
    expect(LivePlayerPrefs.loadFrom(path).danmakuOn, isTrue);
  });

  testWidgets('full screen by the button, the lock, and back to upright', (tester) async {
    final rig = await playing(tester);
    final orientation = rig.services.device.orientation;
    expect(rig.controller.fullScreen, isFalse);
    await rig.controller.setFullScreen(true);
    expect(rig.controller.fullScreen, isTrue);

    rig.controller.setLocked(true);
    expect(rig.controller.locked, isTrue);
    expect(orientation.locked, isTrue);
    rig.controller.setLocked(false);
    expect(rig.controller.locked, isFalse);

    expect(rig.controller.back(), isTrue);
    expect(rig.controller.fullScreen, isFalse);
    expect(rig.controller.back(), isFalse);

    // Covered, the room gives the orientation up, with the 开发者 turn choice as it was.
    await rig.controller.setFullScreen(true);
    rig.controller.setCovered(true);
    expect(orientation.presentation.fullScreen, isFalse);
    expect(rig.controller.fullScreen, isFalse);
  });

  testWidgets('分享 hands the room link to the share sheet; 小窗播放 starts picture in picture', (tester) async {
    final rig = await playing(tester);
    await tester.pumpWidget(const SizedBox());
    await rig.controller.share(tester.element(find.byType(SizedBox)));
    expect(rig.shared, [Uri.parse('https://live.bilibili.com/7734200')]);
    await rig.controller.startPictureInPicture();
    expect(rig.player.calls.last, 'pip start');
  });
}
