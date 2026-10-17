import 'dart:async';

import 'package:bilifast/player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rules in BiliPlayer's doc comment, checked against one implementation. iOS runs it with a fake native
/// side, Windows in an integration test with real mpv, the fakes in plain widget tests.
void playerContract(String name, Future<BiliPlayer> Function() create, {Uri? playable}) {
  final source = PlayerSource(master: playable ?? Uri.parse('http://127.0.0.1:9/none/master.m3u8'), autoplay: false);

  group('$name keeps the player contract', () {
    test('events is a broadcast stream that closes on dispose', () async {
      final player = await create();
      expect(player.events.isBroadcast, isTrue);
      final done = Completer<void>();
      player.events.listen(null, onDone: done.complete);
      await player.dispose();
      await done.future.timeout(const Duration(seconds: 5));
    });

    test('load reports loading before it completes', () async {
      final player = await create();
      final seen = <PlayerEvent>[];
      final subscription = player.events.listen(seen.add);
      await player.load(source);
      await Future<void>.delayed(Duration.zero);
      expect(seen.whereType<StatusChanged>().map((event) => event.status), contains(PlayerStatus.loading));
      expect((seen.firstWhere((event) => event is StatusChanged) as StatusChanged).status, PlayerStatus.loading);
      await subscription.cancel();
      await player.dispose();
    });

    test('picture in picture and capture are harmless when unsupported', () async {
      final player = await create();
      if (!player.capabilities.pictureInPicture) {
        await player.startPictureInPicture();
        await player.stopPictureInPicture();
        await player.setAutoPictureInPicture(true);
      }
      if (!player.capabilities.frameCapture) expect(await player.captureFrame(), isFalse);
      await player.dispose();
    });

    test('commands after dispose throw StateError', () async {
      final player = await create();
      await player.dispose();
      await expectLater(player.play(), throwsStateError);
      await expectLater(player.seek(1), throwsStateError);
      await expectLater(player.load(source), throwsStateError);
    });

    test('dispose twice is fine', () async {
      final player = await create();
      await player.dispose();
      await player.dispose();
    });
  });
}
