import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/ios/ios_player_events.dart';
import 'package:bilifast/player/ios/player_api.g.dart';
import 'package:bilifast/player/ios_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/player_contract.dart';
import 'fake_player_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  playerContract('IosPlayer', () => IosPlayer.connect(FakePlayerHost(), IosPlayerEvents()));
  playerContract(
    'IosPlayer without picture in picture',
    () => IosPlayer.connect(FakePlayerHost(pictureInPicture: false), IosPlayerEvents()),
  );

  late FakePlayerHost host;
  late ManualClock clock;
  late IosPlayerEvents hub;
  late IosPlayer player;
  late List<PlayerEvent> seen;
  late StreamSubscription<PlayerEvent> subscription;

  setUp(() async {
    host = FakePlayerHost();
    clock = ManualClock(1000);
    hub = IosPlayerEvents(clock: clock.clock);
    player = await IosPlayer.connect(host, hub);
    seen = [];
    subscription = player.events.listen(seen.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await player.dispose();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test("the registry's lines for a player not attached yet, or gone, still reach the log", () async {
    final logger = Logger(session: 'test');
    final sink = MemorySink();
    logger.add(sink);
    final events = IosPlayerEvents(logger: logger);
    await events.onLog(9, 'native player disposed', {'live': 0});
    final event = sink.events.single;
    expect((event.cat, event.msg), (LogCategory.player, 'native player disposed'));
    expect(event.f['playerId'], const LogInt(9));
    expect(event.f['live'], const LogInt(0));

    await hub.onLog(player.nativeId, 'item ready', {});
    expect(seen.whereType<PlayerLog>().single.kind, 'item ready');
  });

  group('commands', () {
    test('create asks the registry for a player and whether it can do picture in picture', () async {
      expect(host.calls, ['create']);
      expect(player.nativeId, 7);
      expect(player.capabilities.pictureInPicture, isTrue);
      expect(player.capabilities.frameCapture, isTrue);
    });

    test('load passes the master URL, headers, start and autoplay', () async {
      await player.load(PlayerSource(
        master: Uri.parse('http://127.0.0.1:8080/tok/master.m3u8'),
        headers: const {'User-Agent': 'Safari', 'Referer': 'https://www.bilibili.com/'},
        startSeconds: 12.5,
        autoplay: false,
      ));
      expect(host.calls.last, 'load 7 http://127.0.0.1:8080/tok/master.m3u8 12.5 false');
      expect(host.headers, {'User-Agent': 'Safari', 'Referer': 'https://www.bilibili.com/'});
    });

    test('playback commands go to the same native player', () async {
      await player.play();
      await player.pause();
      await player.seek(30);
      await player.seek(31.5, precise: true);
      await player.setRate(1.5);
      await player.setMirrored(true);
      expect(host.calls.skip(1), [
        'play 7',
        'pause 7',
        'seek 7 30.0 false',
        'seek 7 31.5 true',
        'rate 7 1.5',
        'mirrored 7 true',
      ]);
    });

    test('mute goes to the native player, keep awake to the app', () async {
      expect(player.muted, isFalse);
      await player.setMuted(true);
      expect(player.muted, isTrue);
      await player.setKeepAwake(true);
      await player.setMuted(false);
      await player.setKeepAwake(false);
      expect(player.muted, isFalse);
      expect(host.calls.skip(1), ['muted 7 true', 'keep awake true', 'muted 7 false', 'keep awake false']);
    });

    test('unload goes to the same native player, and a load after it works', () async {
      await player.unload();
      await player.load(PlayerSource(master: Uri.parse('http://127.0.0.1:8080/tok/master.m3u8')));
      expect(host.calls.skip(1), ['unload 7', 'load 7 http://127.0.0.1:8080/tok/master.m3u8 0.0 true']);
    });

    test('every fit mode maps to its native mode', () async {
      for (final fit in FitMode.values) {
        await player.setFit(fit);
      }
      expect(host.calls.skip(1), [for (final fit in FitMode.values) 'fit 7 ${fit.name}']);
    });

    test('picture in picture and capture reach the native player', () async {
      await player.startPictureInPicture();
      await player.stopPictureInPicture();
      await player.setAutoPictureInPicture(false);
      expect(await player.captureFrame(), isTrue);
      expect(host.calls.skip(1), ['pip start 7', 'pip stop 7', 'pip auto 7 false', 'capture 7']);
    });

    test('a failed capture is reported as false', () async {
      final failing = await IosPlayer.connect(FakePlayerHost(captureResult: false), IosPlayerEvents());
      expect(await failing.captureFrame(), isFalse);
      await failing.dispose();
    });

    test('without picture in picture the commands never reach the native side', () async {
      final noPiP = FakePlayerHost(pictureInPicture: false);
      final other = await IosPlayer.connect(noPiP, IosPlayerEvents());
      await other.startPictureInPicture();
      await other.stopPictureInPicture();
      await other.setAutoPictureInPicture(true);
      expect(noPiP.calls, ['create']);
      await other.dispose();
    });

    test('dispose releases the native player once', () async {
      await player.dispose();
      await player.dispose();
      expect(host.calls.where((call) => call.startsWith('dispose')), ['dispose 7']);
    });
  });

  group('events', () {
    test('position is stamped with the host clock when it arrives', () async {
      clock.set(2500);
      await hub.onPosition(7, 12.25, 1.5);
      await settle();
      final position = seen.single as PositionChanged;
      expect(position.seconds, 12.25);
      expect(position.rate, 1.5);
      expect(position.hostMs, 2500);
    });

    test('every native event becomes its PlayerEvent', () async {
      await hub.onDuration(7, 600);
      await hub.onBuffered(7, [NativeTimeRange(start: 0, end: 30), NativeTimeRange(start: 60, end: 75)]);
      await hub.onStatus(7, NativePlayerStatus.buffering);
      await hub.onRate(7, 2);
      await hub.onSize(7, 3840, 2160);
      await hub.onFailure(7, '播放失败，请稍后重试', 'AVFoundationErrorDomain', -11821, true);
      await hub.onPictureInPicture(7, true);
      await hub.onPictureInPictureRestore(7);
      await hub.onLog(7, 'access log', {'observedBitrate': 12000000.0, 'stalls': 0});
      await settle();

      expect(seen, hasLength(9));
      expect((seen[0] as DurationChanged).seconds, 600);
      expect((seen[1] as BufferedChanged).ranges, [(start: 0.0, end: 30.0), (start: 60.0, end: 75.0)]);
      expect((seen[2] as StatusChanged).status, PlayerStatus.buffering);
      expect((seen[3] as RateChanged).rate, 2);
      final size = seen[4] as SizeChanged;
      expect((size.width, size.height), (3840, 2160));
      final failure = seen[5] as PlayerFailed;
      expect(failure.message, '播放失败，请稍后重试');
      expect(failure.domain, 'AVFoundationErrorDomain');
      expect(failure.code, -11821);
      expect(failure.formatRejected, isTrue);
      expect((seen[6] as PictureInPictureChanged).active, isTrue);
      expect(seen[7], isA<PictureInPictureRestore>());
      final log = seen[8] as PlayerLog;
      expect(log.kind, 'access log');
      expect(log.fields, {'observedBitrate': 12000000.0, 'stalls': 0});
    });

    test('every native status maps to the same PlayerStatus', () async {
      for (final status in NativePlayerStatus.values) {
        await hub.onStatus(7, status);
      }
      await settle();
      expect(seen.cast<StatusChanged>().map((event) => event.status.name), [
        for (final status in NativePlayerStatus.values) status.name,
      ]);
    });

    test('load announces loading itself and the native echo is dropped', () async {
      await player.load(PlayerSource(master: Uri.parse('http://127.0.0.1:1/t/master.m3u8')));
      await hub.onStatus(7, NativePlayerStatus.loading);
      await hub.onStatus(7, NativePlayerStatus.playing);
      await hub.onStatus(7, NativePlayerStatus.playing);
      await settle();
      expect(seen.cast<StatusChanged>().map((event) => event.status), [PlayerStatus.loading, PlayerStatus.playing]);
    });

    test('every load announces loading, even right after another', () async {
      final source = PlayerSource(master: Uri.parse('http://127.0.0.1:1/t/master.m3u8'));
      await player.load(source);
      await player.load(source);
      await settle();
      expect(seen.cast<StatusChanged>().map((event) => event.status), [PlayerStatus.loading, PlayerStatus.loading]);
    });

    test('what the old item reports while the native load runs is dropped', () async {
      await hub.onStatus(7, NativePlayerStatus.playing);
      host.holdLoad = Completer<void>();
      final loading = player.load(PlayerSource(master: Uri.parse('http://127.0.0.1:1/t/master.m3u8')));
      await hub.onPosition(7, 300, 1);
      await hub.onDuration(7, 600);
      await hub.onBuffered(7, [NativeTimeRange(start: 0, end: 320)]);
      await hub.onSize(7, 1920, 1080);
      await hub.onFailure(7, 'old', null, null, false);
      await hub.onStatus(7, NativePlayerStatus.paused);
      await hub.onPictureInPicture(7, true);
      await hub.onRate(7, 1.25);
      await hub.onLog(7, 'access log', const {});
      host.holdLoad!.complete();
      await loading;
      await hub.onDuration(7, 90);
      await settle();

      expect(seen.map((event) => event.runtimeType), [
        StatusChanged,
        StatusChanged,
        PictureInPictureChanged,
        RateChanged,
        PlayerLog,
        DurationChanged,
      ]);
      expect((seen[1] as StatusChanged).status, PlayerStatus.loading);
      expect((seen.last as DurationChanged).seconds, 90);
    });

    test('events for another player stay with that player', () async {
      final otherHost = FakePlayerHost(id: 8);
      final other = await IosPlayer.connect(otherHost, hub);
      final otherSeen = <PlayerEvent>[];
      final otherSubscription = other.events.listen(otherSeen.add);
      await hub.onDuration(8, 90);
      await hub.onDuration(9, 45);
      await settle();
      expect(seen, isEmpty);
      expect((otherSeen.single as DurationChanged).seconds, 90);
      await otherSubscription.cancel();
      await other.dispose();
    });

    test('nothing arrives after dispose', () async {
      await player.dispose();
      await hub.onDuration(7, 600);
      await settle();
      expect(seen, isEmpty);
    });
  });

  group('view', () {
    test('a UiKitView of bilifast/player with the id, transparent to touches', () {
      final view = player.buildView() as UiKitView;
      expect(view.viewType, 'bilifast/player');
      expect(view.creationParams, {'id': 7});
      expect(view.creationParamsCodec, isA<StandardMessageCodec>());
      expect(view.hitTestBehavior, PlatformViewHitTestBehavior.transparent);
      expect(view.gestureRecognizers, anyOf(isNull, isEmpty));
    });

    testWidgets('the native side receives the player id in the creation params', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final created = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
        if (call.method == 'create') created.add(call.arguments as Map<Object?, Object?>);
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      });

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 400, height: 225, child: player.buildView()),
      ));
      debugDefaultTargetPlatformOverride = null;

      expect(created, hasLength(1));
      expect(created.single['viewType'], 'bilifast/player');
      final params = created.single['params'] as Uint8List;
      expect(const StandardMessageCodec().decodeMessage(ByteData.sublistView(params)), {'id': 7});
    });
  });
}
