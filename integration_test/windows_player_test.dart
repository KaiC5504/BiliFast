import 'dart:io';

import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/windows_player.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../test/support/player_contract.dart';
import 'support/fixture_server.dart';

Future<void> main() async {
  // Frames as in the app: media_kit's VideoController only starts after a frame, and the contract's plain tests
  // pump none.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final server = await FixtureServer.start();
  tearDownAll(server.close);
  setUp(server.requests.clear);

  playerContract('WindowsPlayer', () => WindowsPlayer.create(muted: true), playable: server.master);

  Future<WindowsPlayer> mounted(WidgetTester tester, {MpvSource source = MpvSource.auto}) async {
    final player = await WindowsPlayer.create(source: source, muted: true);
    addTearDown(player.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: 320, height: 180, child: player.buildView())),
    ));
    return player;
  }

  PlayerSource fixture({String session = 'hls', double startSeconds = 0, bool autoplay = true, Map<String, String> headers = const {}}) =>
      PlayerSource(
        master: server.uri('master.m3u8', session: session),
        video: server.uri('v.mp4', session: session),
        audio: server.uri('a.mp4', session: session),
        startSeconds: startSeconds,
        autoplay: autoplay,
        headers: headers,
      );

  testWidgets('plays the two files: events, pause, precise seek, rate and the end', (tester) async {
    final player = await mounted(tester);
    final seen = Recorder(player);
    await player.load(fixture());
    await until(tester, 'playback past 1 s', () => (seen.position ?? 0) > 1);

    expect(seen.statuses.first, PlayerStatus.loading);
    expect(seen.statuses, contains(PlayerStatus.playing));
    expect(seen.opened, ['edl']);
    expect(seen.of<DurationChanged>().last.seconds, closeTo(3, 0.15));
    expect(seen.of<SizeChanged>().map((size) => (size.width, size.height)), [(320, 180)]);
    expect(seen.of<BufferedChanged>().last.ranges.last.end, greaterThan(1));
    expect(server.requests.map((request) => request.name).toSet(), {'v.mp4', 'a.mp4'});

    final readings = seen.of<PositionChanged>().where((reading) => reading.seconds > 0.1).toList();
    expect(readings.length, greaterThanOrEqualTo(5));
    final gaps = [for (var index = 1; index < readings.length; index++) readings[index].hostMs - readings[index - 1].hostMs];
    expect(gaps.every((gap) => gap > 0), isTrue);
    expect(median(gaps), inInclusiveRange(80, 200));
    final first = readings.first, last = readings.last;
    expect((last.seconds - first.seconds) / ((last.hostMs - first.hostMs) / 1000), closeTo(1, 0.15));
    expect(readings.every((reading) => reading.rate == 1), isTrue);

    await player.pause();
    await until(tester, 'paused', () => seen.status == PlayerStatus.paused);
    await settle(tester, 200);
    final pausedAt = seen.position!;
    await settle(tester, 500);
    expect(seen.position, closeTo(pausedAt, 0.02));

    await player.seek(0.5, precise: true);
    await until(tester, 'the seek to 0.5 s', () => (seen.position! - 0.5).abs() < 0.06);
    expect(seen.status, PlayerStatus.paused);

    await player.setRate(2);
    await until(tester, 'rate 2', () => seen.of<RateChanged>().any((event) => event.rate == 2));
    await player.play();
    await until(tester, 'playback past 0.8 s', () => seen.position! > 0.8);
    final from = seen.of<PositionChanged>().last;
    await until(tester, 'a second of media', () => seen.position! > from.seconds + 1);
    final to = seen.of<PositionChanged>().last;
    expect((to.seconds - from.seconds) / ((to.hostMs - from.hostMs) / 1000), closeTo(2, 0.3));
    expect(to.rate, 2);
    await until(tester, 'the end', () => seen.status == PlayerStatus.ended);
    expect(seen.position, closeTo(3, 0.1));

    await player.seek(1);
    await until(tester, 'a loose seek back from the end',
        () => seen.status == PlayerStatus.paused && seen.position! < 2.5);
    // A loose seek lands on the keyframe at or before the target.
    expect(seen.position, lessThanOrEqualTo(1.05));
    expect(seen.of<PlayerFailed>(), isEmpty);
  }, timeout: _timeout);

  testWidgets('starts at startSeconds, waits without autoplay, and takes fit and mirroring', (tester) async {
    final player = await mounted(tester);
    final seen = Recorder(player);
    await player.load(fixture(startSeconds: 2, autoplay: false));
    await until(tester, 'ready and paused', () => seen.status == PlayerStatus.paused && seen.position != null);
    expect(seen.position, closeTo(2, 0.15));
    await settle(tester, 500);
    expect(seen.position, closeTo(2, 0.15));
    expect(seen.statuses, isNot(contains(PlayerStatus.playing)));

    const fits = {
      FitMode.fit: (BoxFit.contain, null),
      FitMode.fill: (BoxFit.cover, null),
      FitMode.stretch: (BoxFit.fill, null),
      FitMode.ratio16x9: (BoxFit.contain, 16 / 9),
      FitMode.ratio4x3: (BoxFit.contain, 4 / 3),
    };
    for (final MapEntry(key: mode, value: (fit, aspectRatio)) in fits.entries) {
      await player.setFit(mode);
      await tester.pump();
      final video = tester.widget<Video>(find.byType(Video));
      expect((video.fit, video.aspectRatio), (fit, aspectRatio), reason: mode.name);
    }
    Matrix4 flip() => tester
        .widget<Transform>(find.ancestor(of: find.byType(Video), matching: find.byType(Transform)).first)
        .transform;
    expect(flip().entry(0, 0), 1);
    await player.setMirrored(true);
    await tester.pump();
    expect(flip().entry(0, 0), -1);

    await player.play();
    await until(tester, 'the end', () => seen.status == PlayerStatus.ended);
  }, timeout: _timeout);

  testWidgets('plays the HLS master in AVPlayer\'s request shape, headers included', (tester) async {
    final player = await mounted(tester, source: MpvSource.hls);
    final seen = Recorder(player);
    const headers = {'User-Agent': 'BiliFastTest/1.0', 'Referer': 'https://www.bilibili.com/'};
    await player.load(fixture(headers: headers));
    await until(tester, 'playback past 1 s', () => (seen.position ?? 0) > 1);
    expect(seen.opened, ['hls']);
    expect(seen.of<DurationChanged>().last.seconds, closeTo(3, 0.1));
    expect(seen.of<SizeChanged>().map((size) => (size.width, size.height)), [(320, 180)]);

    await player.pause();
    await until(tester, 'paused', () => seen.status == PlayerStatus.paused);
    await player.seek(0.5, precise: true);
    await until(tester, 'the seek to 0.5 s inside the cache', () => (seen.position! - 0.5).abs() < 0.06);

    final names = server.requests.map((request) => request.name).toSet();
    expect(names, containsAll(['master.m3u8', 'v.m3u8', 'a.m3u8', 'v.mp4', 'a.mp4']));
    final ranges = server.requests.where((request) => request.name.endsWith('.mp4')).map((request) => request.range).toSet();
    expect(ranges, containsAll([...playlistRanges('v.m3u8'), ...playlistRanges('a.m3u8')]));
    expect(server.requests.map((request) => (request.userAgent, request.referer)).toSet(),
        {('BiliFastTest/1.0', 'https://www.bilibili.com/')});
    expect(seen.of<PlayerFailed>(), isEmpty);
  }, timeout: _timeout);

  testWidgets('direct-mode headers reach both files, and go on the next load', (tester) async {
    final player = await mounted(tester);
    final seen = Recorder(player);
    const headers = {'User-Agent': 'BiliFastTest/1.0', 'Referer': 'https://www.bilibili.com/'};
    Set<(String?, String?)> sent(String session) => {
          for (final request in server.requests)
            if (request.session == session) (request.userAgent, request.referer),
        };

    await player.load(fixture(session: 'direct', headers: headers, autoplay: false));
    await until(tester, 'ready', () => seen.status == PlayerStatus.paused && sent('direct').isNotEmpty);
    expect(sent('direct'), {('BiliFastTest/1.0', 'https://www.bilibili.com/')});

    await player.load(fixture(session: 'local', autoplay: false));
    await until(tester, 'ready again', () => sent('local').isNotEmpty);
    await settle(tester, 300);
    // mpv can't unset its referrer option, so an empty one goes out.
    expect(sent('local'), {('libmpv', '')});
  }, timeout: _timeout);

  testWidgets('falls back to the HLS master when the files do not open', (tester) async {
    final player = await mounted(tester);
    final seen = Recorder(player);
    await player.load(PlayerSource(master: server.master, video: server.missing('v.mp4'), audio: server.missing('a.mp4')));
    await until(tester, 'playback past 1 s', () => (seen.position ?? 0) > 1, timeout: const Duration(seconds: 15));
    expect(seen.opened, ['edl', 'hls']);
    expect(seen.of<PlayerLog>().where((log) => log.kind == 'fallback'), hasLength(1));
    expect(seen.of<PlayerFailed>(), isEmpty);
    expect(seen.statuses.last, PlayerStatus.playing);
  }, timeout: _timeout);

  testWidgets('reports a failure without the URL query when nothing plays', (tester) async {
    final player = await mounted(tester);
    final seen = Recorder(player);
    await player.load(PlayerSource(master: server.missing('master.m3u8').replace(query: 'deadline=1&upsig=secret')));
    await until(tester, 'the failure', () => seen.of<PlayerFailed>().isNotEmpty);
    await settle(tester, 300);
    final failure = seen.of<PlayerFailed>().single;
    expect(failure.domain, 'mpv');
    expect(failure.message, contains('/gone/master.m3u8'));
    expect(failure.message, isNot(contains('upsig')));
    expect(failure.formatRejected, isFalse);
  }, timeout: _timeout);
}

const _timeout = Timeout(Duration(minutes: 1));

/// Every event a player sends, from when it is attached.
final class Recorder {
  Recorder(BiliPlayer player) {
    player.events.listen(events.add);
  }

  final events = <PlayerEvent>[];

  Iterable<T> of<T extends PlayerEvent>() => events.whereType<T>();

  List<PlayerStatus> get statuses => [for (final event in of<StatusChanged>()) event.status];

  PlayerStatus? get status => statuses.lastOrNull;

  double? get position => of<PositionChanged>().lastOrNull?.seconds;

  List<Object?> get opened => [for (final log in of<PlayerLog>()) if (log.kind == 'open') log.fields['mode']];
}

Future<void> until(WidgetTester tester, String what, bool Function() done,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > timeout) fail('timed out waiting for $what');
    await settle(tester, 20);
  }
}

Future<void> settle(WidgetTester tester, int ms) async {
  await tester.pump();
  await Future<void>.delayed(Duration(milliseconds: ms));
}

double median(List<double> values) => (List.of(values)..sort())[values.length ~/ 2];

/// The `Range` header of each EXT-X-MAP and EXT-X-BYTERANGE in a fixture playlist.
List<String> playlistRanges(String playlist) {
  final text = File('${fixtureDirectory().path}/$playlist').readAsStringSync();
  return [
    for (final match in RegExp(r'BYTERANGE[:=]"?(\d+)@(\d+)').allMatches(text))
      'bytes=${match[2]}-${int.parse(match[2]!) + int.parse(match[1]!) - 1}',
  ];
}
