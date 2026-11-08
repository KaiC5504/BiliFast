import 'dart:async';

import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/ios/ios_player_events.dart';
import 'package:bilifast/player/ios/player_api.g.dart';
import 'package:bilifast/player/ios_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// The registry's side of 后台听视频 and the lock screen, recorded instead of sent.
final class _Host extends PlayerHostApi {
  _Host({this.id = 7});

  final int id;
  final calls = <String>[];
  final nowPlaying = <NativeNowPlaying?>[];
  Completer<void>? holdLoad;

  @override
  Future<int> create() async => id;

  @override
  Future<bool> pictureInPictureSupported() async => true;

  @override
  Future<void> load(int playerId, String url, Map<String, String> headers, double startSeconds, bool autoplay) async {
    calls.add('load $playerId');
    await holdLoad?.future;
  }

  @override
  Future<void> setBackgroundPlayback(int playerId, bool enabled) async => calls.add('background $playerId $enabled');

  @override
  Future<void> setNowPlaying(int playerId, NativeNowPlaying? info) async {
    calls.add('now playing $playerId');
    nowPlaying.add(info);
  }

  @override
  Future<void> dispose(int playerId) async => calls.add('dispose $playerId');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Host host;
  late IosPlayerEvents hub;
  late IosPlayer player;
  late List<PlayerEvent> seen;
  late StreamSubscription<PlayerEvent> subscription;

  setUp(() async {
    host = _Host();
    hub = IosPlayerEvents();
    player = await IosPlayer.connect(host, hub);
    seen = [];
    subscription = player.events.listen(seen.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await player.dispose();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('commands', () {
    test('后台听视频 reaches the same native player, on and off', () async {
      await player.setBackgroundPlayback(true);
      await player.setBackgroundPlayback(false);
      expect(host.calls, ['background 7 true', 'background 7 false']);
    });

    test('now playing hands over every field, and null takes it off', () async {
      await player.setNowPlaying(const NowPlayingInfo(
        title: '【4K】城市夜景',
        artist: '某UP主',
        artworkPath: '/caches/images/cover.jpg',
        hasPrevious: true,
        hasNext: false,
      ));
      await player.setNowPlaying(const NowPlayingInfo(title: '第二个', artist: 'UP'));
      await player.setNowPlaying(null);

      expect(host.calls, ['now playing 7', 'now playing 7', 'now playing 7']);
      final first = host.nowPlaying[0]!;
      expect(first.title, '【4K】城市夜景');
      expect(first.artist, '某UP主');
      expect(first.artworkPath, '/caches/images/cover.jpg');
      expect(first.hasPrevious, isTrue);
      expect(first.hasNext, isFalse);
      final second = host.nowPlaying[1]!;
      expect(second.artworkPath, isNull);
      expect((second.hasPrevious, second.hasNext), (false, false));
      expect(host.nowPlaying[2], isNull);
    });

    test('after dispose both throw StateError and nothing reaches the native side', () async {
      await player.dispose();
      await expectLater(player.setBackgroundPlayback(true), throwsStateError);
      await expectLater(player.setNowPlaying(null), throwsStateError);
      expect(host.calls, ['dispose 7']);
    });
  });

  group('events', () {
    test('every native remote command becomes its RemoteCommand, seek with its position', () async {
      for (final command in NativeRemoteCommand.values) {
        await hub.onRemoteCommand(7, command, command == NativeRemoteCommand.seek ? 93.5 : null);
      }
      await settle();

      final commands = seen.cast<RemoteCommand>();
      expect(commands.map((event) => event.kind.name), [
        for (final command in NativeRemoteCommand.values) command.name,
      ]);
      expect(commands.firstWhere((event) => event.kind == RemoteCommandKind.seek).seconds, 93.5);
      expect(commands.where((event) => event.kind != RemoteCommandKind.seek).map((event) => event.seconds),
          everyElement(isNull));
    });

    test('an interruption arrives as it began and as it ended, with the hint to resume', () async {
      await hub.onInterruption(7, true, false);
      await hub.onInterruption(7, false, true);
      await settle();

      final interruptions = seen.cast<AudioInterruption>();
      expect(interruptions.map((event) => (event.began, event.shouldResume)), [(true, false), (false, true)]);
    });

    test("another player's commands and interruptions stay with that player", () async {
      final other = await IosPlayer.connect(_Host(id: 8), hub);
      final otherSeen = <PlayerEvent>[];
      final otherSubscription = other.events.listen(otherSeen.add);
      await hub.onRemoteCommand(8, NativeRemoteCommand.pause, null);
      await hub.onInterruption(8, true, false);
      await hub.onRemoteCommand(9, NativeRemoteCommand.play, null);
      await settle();

      expect(seen, isEmpty);
      expect(otherSeen.map((event) => event.runtimeType), [RemoteCommand, AudioInterruption]);
      expect((otherSeen.first as RemoteCommand).kind, RemoteCommandKind.pause);
      await otherSubscription.cancel();
      await other.dispose();
    });

    test('a button pressed while a load runs is not taken for the old item and dropped', () async {
      host.holdLoad = Completer<void>();
      final loading = player.load(PlayerSource(master: Uri.parse('http://127.0.0.1:1/t/master.m3u8')));
      await hub.onRemoteCommand(7, NativeRemoteCommand.toggle, null);
      await hub.onInterruption(7, true, false);
      host.holdLoad!.complete();
      await loading;
      await settle();

      expect(seen.map((event) => event.runtimeType), [StatusChanged, RemoteCommand, AudioInterruption]);
    });

    test('nothing arrives after dispose', () async {
      await player.dispose();
      await hub.onRemoteCommand(7, NativeRemoteCommand.play, null);
      await hub.onInterruption(7, false, true);
      await settle();
      expect(seen, isEmpty);
    });
  });
}
