import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/page/offline_playback.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/playback/shared_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player.dart';

/// Local playback's failures reach the log without the container's paths, and none goes unlogged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const container = '/private/var/mobile/Containers/Data/Application/0F00/Library/offline/7003/v.m4s';

  test('a file error in a local prepare logs the OS\'s words, never the path', () async {
    final logs = MemorySink();
    final logger = Logger(session: 'test')..add(logs);
    final engine = FakeEngine()
      ..prepareErrors.add(const FileSystemException('Cannot open file', container, OSError('No such file', 2)));
    final controller = PlaybackController(
      client: BiliClient(transport: Canned.http(), cookies: CookieJar(Canned.cookies), logger: logger),
      engine: engine,
      player: FakePlayer(),
      clock: ManualClock(1000).clock,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    addTearDown(controller.dispose);
    final library = FakeOfflineLibrary.demo();

    await controller.openLocal(() async => localVideoOf((await library.playback(7003))!));
    await settle();
    expect(controller.phase, PlaybackPhase.failed);
    final text = logs.events.map((event) => jsonEncode(event.toJson())).join('\n');
    expect(text, contains('No such file'));
    expect(text, isNot(contains('Containers')));
  });

  test('a local source prepared after the lease let go is released, and a failed release is logged', () async {
    final logs = MemorySink();
    final engine = FakeEngine()..releaseError = StateError('gone');
    final shared = SharedEngine(() async => engine, logger: Logger(session: 'test')..add(logs));
    final lease = await shared.lease();
    final files = (await FakeOfflineLibrary.demo().playback(7003))!.files;

    final preparing = lease.prepareLocal(files);
    await lease.dispose();
    await preparing;
    await settle();
    final failed = logs.events.where((event) => event.msg == 'release failed').single;
    expect(failed.level, LogLevel.debug);
    expect(failed.f['error']?.toJson(), 'StateError');
  });
}
