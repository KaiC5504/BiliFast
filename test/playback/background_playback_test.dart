import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player.dart';
import 'fakes.dart';

const bv = 'BV1GJ411x7h7';

void main() {
  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late ManualClock time;
  late MemorySink logs;

  setUp(() {
    http = Canned.http();
    engine = FakeEngine();
    player = FakePlayer();
    time = ManualClock(10000);
    logs = MemorySink();
  });

  PlaybackController make() {
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final logger = Logger(session: 'test')..add(logs);
    final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
    return PlaybackController(
      client: client,
      engine: engine,
      player: player,
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
  }

  List<String> callsOf(String kind) => [
        for (final call in player.calls)
          if (call.startsWith(kind)) call,
      ];

  const first = NowPlayingInfo(title: 'one', artist: 'up', artworkPath: '/covers/1.jpg', hasNext: true);
  const second = NowPlayingInfo(title: 'two', artist: 'up');

  group('后台听视频', () {
    test('every call reaches the player, and none after dispose', () async {
      final controller = make();
      await controller.setBackgroundPlayback(false);
      await controller.setBackgroundPlayback(true);
      expect(callsOf('background'), ['background false', 'background true']);

      controller.dispose();
      await controller.setBackgroundPlayback(false);
      await settle();
      expect(callsOf('background'), hasLength(2));
      expect(logs.events.where((event) => event.msg.endsWith('failed')), isEmpty);
    });

    test('a player that refuses it is logged, not thrown to the page', () async {
      player.backgroundError = StateError('refused');
      final controller = make();
      await controller.setBackgroundPlayback(true);
      await controller.setNowPlaying(first);
      await settle();
      expect(logs.events.map((event) => event.msg), containsAll(['background playback failed', 'now playing failed']));
      controller.dispose();
    });
  });

  group('now playing', () {
    test('every info reaches the player, so a page can take the lock screen back; a second clear sends nothing',
        () async {
      final controller = make();
      await controller.setNowPlaying(first);
      await controller.setNowPlaying(const NowPlayingInfo(
        title: 'one',
        artist: 'up',
        artworkPath: '/covers/1.jpg',
        hasNext: true,
      ));
      await controller.setNowPlaying(second);
      await controller.setNowPlaying(second);
      await controller.setNowPlaying(null);
      await controller.setNowPlaying(null);
      await controller.setNowPlaying(first);
      expect(callsOf('now playing'), [
        'now playing one',
        'now playing one',
        'now playing two',
        'now playing two',
        'now playing null',
        'now playing one',
      ]);
      expect(player.nowPlaying, first);
      controller.dispose();
    });

    test('dispose takes it off the lock screen before the player goes', () async {
      final controller = make();
      await controller.open(bv);
      await controller.setNowPlaying(first);
      controller.dispose();
      await settle();
      // The fake refuses every call once disposed, so the clear was recorded only if it came first.
      expect(callsOf('now playing'), ['now playing one', 'now playing null']);
      expect(player.nowPlaying, isNull);
      expect(player.disposed, isTrue);
      expect(logs.events.where((event) => event.msg == 'now playing failed'), isEmpty);
    });

    test('a controller that showed nothing, or already took it off, sends no clear on dispose', () async {
      final controller = make();
      await controller.setNowPlaying(null);
      controller.dispose();
      await settle();
      expect(callsOf('now playing'), isEmpty);

      player = FakePlayer();
      final cleared = make();
      await cleared.setNowPlaying(first);
      await cleared.setNowPlaying(null);
      cleared.dispose();
      await settle();
      expect(callsOf('now playing'), ['now playing one', 'now playing null']);
    });

    test('nothing is sent after dispose', () async {
      final controller = make();
      controller.dispose();
      await controller.setNowPlaying(first);
      await settle();
      expect(callsOf('now playing'), isEmpty);
    });
  });

  group('remote commands and interruptions', () {
    test('each arrives on its own stream, as the player reported it', () async {
      final controller = make();
      final commands = <RemoteCommand>[];
      final interruptions = <AudioInterruption>[];
      controller.remoteCommands.listen(commands.add);
      controller.interruptions.listen(interruptions.add);

      player.emit(const RemoteCommand(RemoteCommandKind.pause));
      player.emit(const AudioInterruption(began: true));
      player.emit(const RemoteCommand(RemoteCommandKind.seek, seconds: 93.5));
      player.emit(const AudioInterruption(began: false, shouldResume: true));
      player.emit(const RemoteCommand(RemoteCommandKind.next));
      await settle();

      expect(commands.map((command) => (command.kind, command.seconds)), [
        (RemoteCommandKind.pause, null),
        (RemoteCommandKind.seek, 93.5),
        (RemoteCommandKind.next, null),
      ]);
      expect(interruptions.map((event) => (event.began, event.shouldResume)), [(true, false), (false, true)]);
      controller.dispose();
    });

    test('both are broadcast, logged once (by the native side), and close on dispose', () async {
      final controller = make();
      expect(controller.remoteCommands.isBroadcast, isTrue);
      expect(controller.interruptions.isBroadcast, isTrue);
      final commandsDone = Completer<void>();
      final interruptionsDone = Completer<void>();
      controller.remoteCommands.listen(null, onDone: commandsDone.complete);
      controller.interruptions.listen(null, onDone: interruptionsDone.complete);

      player.emit(const RemoteCommand(RemoteCommandKind.seek, seconds: 61.6));
      player.emit(const AudioInterruption(began: true));
      expect(logs.events.where((event) => event.msg == 'remote command' || event.msg == 'audio interruption'), isEmpty);

      controller.dispose();
      await commandsDone.future.timeout(const Duration(seconds: 5));
      await interruptionsDone.future.timeout(const Duration(seconds: 5));
    });
  });

  group('in the background', () {
    List<String> segments() => [
          for (final request in http.to(Canned.segmentPath)) request.url.queryParameters['segment_index']!,
        ];

    void emitPosition(double seconds) =>
        player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));

    test('the playhead fetches no danmaku segment; back, the one it reached is fetched at once', () async {
      final controller = make();
      await controller.open(bv);
      player.emit(const StatusChanged(PlayerStatus.playing));
      emitPosition(1);
      await controller.danmaku.settle();
      expect(segments(), ['1']);

      controller.inBackground = true;
      emitPosition(330);
      emitPosition(400);
      emitPosition(410);
      await controller.danmaku.settle();
      expect(segments(), ['1'], reason: 'nothing draws them in the background');

      controller.inBackground = false;
      await controller.danmaku.settle();
      expect(segments(), ['1', '2'], reason: 'without waiting for the next reading');

      emitPosition(411);
      await controller.danmaku.settle();
      expect(segments(), ['1', '2']);
      controller.dispose();
    });

    test('a part opened in the background waits for the app to come back for its danmaku', () async {
      final controller = make();
      controller.inBackground = true;
      await controller.open(bv);
      player.emit(const StatusChanged(PlayerStatus.playing));
      emitPosition(1);
      await controller.danmaku.settle();
      expect(segments(), isEmpty);

      controller.inBackground = false;
      await controller.danmaku.settle();
      expect(segments(), ['1']);
      expect(controller.danmaku.timeline, isNotNull);
      controller.dispose();
    });
  });
}
