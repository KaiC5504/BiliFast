import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/live/player/live_player_controller.dart';
import 'package:bilifast/live/player/live_player_prefs.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/pip_keeper.dart';
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
    expect(rig.player.nowPlaying?.title, '演示比赛 AA vs BB');
    expect(rig.player.nowPlaying?.artist, '演示 Streamer');
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

  testWidgets('after 自动 has played, picking the quality it landed on asks nothing and says nothing', (tester) async {
    final rig = await playing(tester);
    await rig.controller.pickQuality(null);
    await tester.pump();
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump();
    expect(rig.controller.autoQuality, isTrue);
    final said = rig.controller.notices.shown.length;

    await rig.controller.pickQuality(qualities[0]);
    await tester.pump();
    expect(rig.room.asked, ['quality 0']);
    expect(rig.controller.autoQuality, isFalse);
    expect(rig.controller.notices.shown, hasLength(said), reason: 'no 切换中');
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump();
    expect(rig.controller.notices.shown, hasLength(said), reason: 'nothing was pending');

    await tester.pump(LivePlayerTheme.noteShown);
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

  testWidgets('a fresh stream that plays and fails at once gets no second ask; one that played 60 s does', (
    tester,
  ) async {
    final rig = await playing(tester);
    rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    await tester.pump();
    expect(rig.room.asked, ['refresh']);

    // The fresh stream plays a moment, then fails: no loop of asks.
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump(const Duration(seconds: 5));
    rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    await tester.pump();
    expect(rig.room.asked, ['refresh']);
    expect(rig.controller.phase, LivePlayerPhase.failed);

    await rig.controller.retry();
    await tester.pump();
    expect(rig.room.asked, ['refresh', 'refresh']);
    rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    await tester.pump();
    expect(rig.room.asked, hasLength(3), reason: '重试 starts the asks over');

    // Played steadily for a minute, the next failure gets its fresh stream; a pause on the way starts the count over.
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump(const Duration(seconds: 40));
    rig.player.emit(const StatusChanged(PlayerStatus.buffering));
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump(const Duration(seconds: 40));
    rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    await tester.pump();
    expect(rig.room.asked, hasLength(3));
    expect(rig.controller.phase, LivePlayerPhase.failed);

    await rig.controller.retry();
    await tester.pump();
    rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    await tester.pump();
    expect(rig.room.asked, hasLength(5));
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump(LivePlayerController.steadyPlay);
    rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    await tester.pump();
    expect(rig.room.asked, hasLength(6));
    expect(rig.controller.phase, LivePlayerPhase.loading);
    rig.controller.dispose();
  });

  testWidgets('three fresh asks in five minutes, then 重试 and nothing asked until it is pressed', (tester) async {
    final rig = await playing(tester);
    Future<void> playThenFail() async {
      rig.player.emit(const StatusChanged(PlayerStatus.playing));
      await tester.pump(LivePlayerController.steadyPlay);
      rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
      await tester.pump();
    }

    rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    await tester.pump();
    await playThenFail();
    await playThenFail();
    expect(rig.room.asked, ['refresh', 'refresh', 'refresh']);
    await playThenFail();
    expect(rig.room.asked, hasLength(3));
    expect(rig.controller.phase, LivePlayerPhase.failed);
    await tester.pump(const Duration(minutes: 10));
    expect(rig.room.asked, hasLength(3));

    await rig.controller.retry();
    await tester.pump();
    expect(rig.room.asked, hasLength(4));
    rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    await tester.pump();
    expect(rig.room.asked, hasLength(5), reason: 'pressed, the count starts over');

    // Asks older than five minutes no longer count.
    final later = await playing(tester);
    Future<void> playFor(Duration time) async {
      later.player.emit(const StatusChanged(PlayerStatus.playing));
      await tester.pump(time);
      later.player.emit(const PlayerFailed('播放失败，请稍后重试'));
      await tester.pump();
    }

    later.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    await tester.pump();
    await playFor(LivePlayerController.freshWindow);
    await playFor(LivePlayerController.steadyPlay);
    await playFor(LivePlayerController.steadyPlay);
    expect(later.room.asked, hasLength(4));
    expect(later.controller.phase, LivePlayerPhase.loading);
    rig.controller.dispose();
    later.controller.dispose();
  });

  testWidgets('a quality switch that fails says 切换失败，请稍后重试 and keeps the quality playing', (tester) async {
    final rig = await playing(tester);
    rig.room.qualityError = StateError('no stream');
    rig.player.calls.clear();
    await rig.controller.pickQuality(qualities[2]);
    await tester.pump();
    expect(rig.room.asked, ['quality 250']);
    expect(rig.controller.notices.shown.map((n) => n.text), ['切换中，请稍候', '切换失败，请稍后重试']);
    expect(rig.controller.quality?.name, '1080P 原画 (高帧率)');
    expect(rig.controller.phase, LivePlayerPhase.playing);
    expect(loads(rig), isEmpty);
    expect(rig.player.calls, isNot(contains('pause')));

    // A later play says nothing of a switch.
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump();
    expect(rig.controller.notices.shown, hasLength(2));
    await tester.pump(LivePlayerTheme.noteShown);
    rig.controller.dispose();
  });

  testWidgets('a room live with no stream the player can play says 暂不支持该直播流', (tester) async {
    final rig = await liveRig();
    await rig.controller.start();
    rig.room.go(
      LiveRoomState.live,
      play: const LivePlayInfo(roomId: 1000002, uid: 2000002, status: LiveStatus.live, qualities: qualities),
    );
    await tester.pump();
    expect(rig.controller.phase, LivePlayerPhase.failed);
    expect(rig.controller.unsupportedStream, isTrue);
    expect(rig.controller.failureText, '暂不支持该直播流');

    rig.room.go(LiveRoomState.live, play: playAt(10000));
    await tester.pump();
    rig.player.emit(const PlayerFailed('播放失败，请稍后重试'));
    rig.room.refreshError = StateError('no stream');
    await tester.pump();
    expect(rig.controller.phase, LivePlayerPhase.failed);
    expect(rig.controller.failureText, '直播加载失败');
    rig.controller.dispose();
  });

  testWidgets(
    'kept for the small window it gives the orientation up and is restorable; the restore button reaches it',
    (tester) async {
      final rig = await playing(tester);
      final orientation = rig.services.device.orientation;
      final restores = <void>[];
      final sub = rig.controller.restoreRequests.listen(restores.add);
      addTearDown(sub.cancel);
      await rig.controller.setFullScreen(true);
      rig.player.calls.clear();

      rig.controller.setKept(true);
      expect(rig.player.calls, containsAllInOrder(['restorable true', 'pip auto false']));
      expect(orientation.presentation.fullScreen, isFalse);
      expect(rig.controller.fullScreen, isFalse);
      rig.player.emit(const PictureInPictureRestore());
      await tester.pump();
      expect(restores, hasLength(1));

      rig.player.calls.clear();
      rig.controller.setKept(false);
      expect(rig.player.calls, containsAllInOrder(['restorable false', 'pip auto true']));
      await rig.controller.setFullScreen(true);
      expect(rig.controller.fullScreen, isTrue);
      rig.controller.refuseRestore();
      expect(rig.player.calls.last, 'restorable false');
      rig.controller.dispose();
    },
  );

  testWidgets('a fresh page plays without releasing its own kept entry', (tester) async {
    final rig = await liveRig();
    final kept = _Kept();
    rig.services.pipKeeper.pageRemoved(kept);
    expect(rig.services.pipKeeper.kept, same(kept));
    rig.controller.keptAs = kept;
    await rig.controller.start();
    rig.room.go(LiveRoomState.live, play: playAt(10000));
    await tester.pump();
    expect(rig.services.pipKeeper.kept, same(kept));

    // Anything else kept lets go before the stream plays.
    rig.controller.keptAs = null;
    rig.room.go(LiveRoomState.live, play: playAt(250));
    await tester.pump();
    expect(rig.services.pipKeeper.kept, isNull);
    expect(kept.closed, isTrue);
    rig.controller.dispose();
  });

  testWidgets('a fresh stream the room fails to give shows 重试', (tester) async {
    final rig = await playing(tester);
    rig.room.refreshError = StateError('no stream');
    rig.player.emit(const PlayerFailed('网络连接失败，请检查网络后重试'));
    await tester.pump();
    expect(rig.controller.phase, LivePlayerPhase.failed);
    rig.controller.dispose();
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

  testWidgets('with 后台听视频 off, a stream still loading as the app leaves is paused, and stays so when it plays', (
    tester,
  ) async {
    final prefs = PlayerPrefs.memory()..backgroundListen = false;
    final rig = await liveRig(playerPrefs: prefs);
    await rig.controller.start();
    rig.room.go(LiveRoomState.live, play: playAt(10000));
    await tester.pump();
    rig.player.emit(const StatusChanged(PlayerStatus.loading));
    await tester.pump();
    rig.player.calls.clear();
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(rig.player.calls, contains('pause'));

    // The load lands playing anyway: paused again, the lock screen left alone.
    rig.player.calls.clear();
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump();
    expect(rig.player.calls, contains('pause'));
    expect(rig.player.nowPlaying, isNull);
    rig.player.emit(const StatusChanged(PlayerStatus.paused));
    await tester.pump();
    expect(rig.controller.playing, isTrue);
    expect(rig.controller.phase, LivePlayerPhase.paused);

    rig.player.calls.clear();
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(rig.player.calls, contains('play'));
    rig.controller.dispose();
  });

  testWidgets('a play reported in the away grace is left for the small window', (tester) async {
    final prefs = PlayerPrefs.memory()..backgroundListen = false;
    final rig = await liveRig(playerPrefs: prefs);
    await rig.controller.start();
    rig.room.go(LiveRoomState.live, play: playAt(10000));
    await tester.pump();
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    rig.player.calls.clear();
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    rig.player.emit(const PictureInPictureChanged(true));
    await tester.pump(const Duration(seconds: 2));
    expect(rig.player.calls, isNot(contains('pause')));
    rig.controller.dispose();
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
    expect(rig.shared, [Uri.parse('https://live.bilibili.com/1000002')]);
    await rig.controller.startPictureInPicture();
    expect(rig.player.calls.last, 'pip start');
  });
}

/// Another page's playback kept for the small window.
final class _Kept implements KeptPlayback {
  bool closed = false;

  @override
  bool get pipActive => true;

  @override
  String get bvid => 'BV1kept';

  @override
  void keep() {}

  @override
  void returned() {}

  @override
  void close() => closed = true;

  @override
  bool pushPage() => false;
}
