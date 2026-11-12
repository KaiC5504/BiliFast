import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/video/history_outbox.dart';
import 'package:bilifast/video/watch_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player.dart';

const mobilePath = '/x/report/heartbeat/mobile';
const historyPath = '/x/v2/history/report';
const webPath = '/x/click-interface/web/heartbeat';
const recentPath = '/x/web-interface/history/cursor';
const ok = '{"code":0,"message":"0","ttl":1}';
const bv = 'BV1GJ411x7h7';
const cid = 137649199;

const recommended = PlaySource(
  fromSpmid: 'tm.recommend.0.0',
  from: '7',
  trackId: 'TRACK.1.2.3',
  flowData: '{"flow_card_type":"av"}',
);

AppToken tokenOf(OfficialIdentity identity, {int mid = 7}) => AppToken(
  accessToken: 'ACCESS',
  refreshToken: 'REFRESH',
  mid: mid,
  expiresAt: DateTime.utc(2027, 4, 1),
  identity: identity,
);

/// With an iPhone-identity token the reporter sends the official iPhone app's reports
/// (docs/reference/official-iphone-calls.md): a start report, then at the play's end an end report and the history
/// report; no web heartbeat.
void main() {
  late CannedHttp http;
  late FakePlayer player;
  late ManualClock time;
  late BiliClient client;
  late PlaybackController controller;
  late MemorySink logs;
  late Logger logger;
  late DateTime wall;
  late double at;
  var loggedIn = true;
  final began = DateTime.utc(2026, 11, 12, 8);

  setUp(() async {
    loggedIn = true;
    wall = began;
    at = 0;
    http = Canned.http()
      ..routes[mobilePath] = (200, ok)
      ..routes[historyPath] = (200, ok)
      ..routes[webPath] = (200, ok)
      ..routes[recentPath] = (200, '{"code":0,"message":"0","data":{"list":[]}}');
    player = FakePlayer();
    time = ManualClock(10000);
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger)
      ..appToken = tokenOf(OfficialIdentity.iphone);
    controller = PlaybackController(
      client: client,
      engine: FakeEngine(),
      player: player,
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    await controller.openVideo(bv, cid: cid, start: 0);
  });

  final seen = <int>[];
  setUp(seen.clear);

  WatchReporter make({HistoryOutbox? outbox, PlaySource Function()? source, bool followed = false}) => WatchReporter(
    controller: controller,
    client: client,
    loggedIn: () => loggedIn,
    onProgress: (bvid, cid, seconds) => seen.add(seconds),
    outbox: outbox,
    source: source,
    followed: followed,
    now: () => wall,
    logger: logger,
  );

  void emit(PlayerStatus status) => player.emit(StatusChanged(status));

  /// Plays on to [seconds], the phone's clock moving as far.
  void playTo(double seconds) {
    wall = wall.add(Duration(milliseconds: ((seconds - at) * 1000).round()));
    at = seconds;
    time.advance(PlaybackClock.jumpSettleMs);
    player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));
  }

  /// A seek as the page's session makes it: the controller is told, then the reporter.
  void seek(WatchReporter reporter, double seconds) {
    controller.userSeeked(seconds);
    reporter.seeked(seconds);
    at = seconds;
  }

  Map<String, String> form(HTTPRequest request) => Uri.splitQueryString(utf8.decode(request.body!));
  List<Map<String, String>> beats() => [for (final request in http.to(mobilePath)) form(request)];
  List<Map<String, String>> places() => [for (final request in http.to(historyPath)) form(request)];
  List<String> official() => [
    for (final path in http.paths)
      if (path == mobilePath || path == historyPath) path,
  ];

  /// What the end heartbeat says of the play: played, actually played, total, paused, last and furthest.
  List<String?> times(Map<String, String> beat) => [
    beat['played_time'],
    beat['actual_played_time'],
    beat['total_time'],
    beat['paused_time'],
    beat['last_play_progress_time'],
    beat['max_play_progress_time'],
  ];

  List<Map<String, Object>> reportLines() => [
    for (final event in logs.events)
      if (event.msg == 'watch report') {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
  ];

  Future<void> flush(HistoryOutbox outbox) =>
      outbox.flush(client.heartbeat, recent: client.history, plays: WatchReporter.playSender(client, logger: logger));

  test('a start report as playback starts; at leaving, the end report with what was watched, then the history report',
      () async {
    final reporter = make();
    emit(PlayerStatus.playing);
    await pumpEventQueue();
    expect(official(), [mobilePath]);
    final start = beats().single;
    expect(start['session'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(start['start_ts'], '0');
    expect(times(start), ['0', '0', '0', '0', '0', '0']);
    expect(start['aid'], '80433022');
    expect(start['cid'], '$cid');
    expect(start['mid'], '7');
    expect(start['video_duration'], '712');
    expect(start['spmid'], 'united.player-video-detail.0.0');
    expect(start['auto_play'], '0');
    expect(start['quality'], '${controller.playing!.quality}');
    expect(start['quality'], isNot('0'));
    expect(start['from'], '');
    expect(start['from_spmid'], '');
    expect(start['track_id'], '');

    playTo(5);
    playTo(14);
    playTo(16);
    playTo(31);
    await pumpEventQueue();
    expect(official(), [mobilePath], reason: 'nothing goes out while it plays');

    await reporter.leave();
    expect(official(), [mobilePath, mobilePath, historyPath]);
    final end = beats().last;
    expect(end['session'], start['session']);
    expect(end['sessionID'], start['session']);
    expect(end['start_ts'], '${began.millisecondsSinceEpoch ~/ 1000}');
    expect(times(end), ['31', '31', '31', '0', '31', '31']);
    final place = places().single;
    expect(place['aid'], '80433022');
    expect(place['cid'], '$cid');
    expect(place['progress'], '31');
    expect(place['duration'], '712');
    expect(place['start_ts'], end['start_ts']);
    expect(http.to(webPath), isEmpty, reason: 'no web heartbeat in this mode');

    await reporter.leave();
    expect(official(), hasLength(3), reason: 'one end per play');
  });

  test('the video finishing ends the play: the history report says -1, and leaving adds nothing', () async {
    final reporter = make();
    emit(PlayerStatus.playing);
    playTo(20);
    emit(PlayerStatus.ended);
    await pumpEventQueue();
    expect(official(), [mobilePath, mobilePath, historyPath]);
    expect(times(beats().last), ['20', '20', '20', '0', '20', '20']);
    expect(places().single['progress'], '-1');
    await reporter.leave();
    expect(official(), hasLength(3));
  });

  test('pauses and seeks: paused time is its own, a seek moves the place without being played', () async {
    final reporter = make();
    emit(PlayerStatus.playing);
    playTo(10);
    emit(PlayerStatus.paused);
    wall = wall.add(const Duration(seconds: 30));
    emit(PlayerStatus.playing);
    playTo(15);
    seek(reporter, 300);
    playTo(302);
    seek(reporter, 40);
    playTo(43);
    await reporter.leave();
    expect(times(beats().last), ['20', '20', '50', '30', '43', '302']);
    expect(places().single['progress'], '43');
  });

  test('once a newer open moved the controller on, leaving ends this play where it was', () async {
    final reporter = make();
    emit(PlayerStatus.playing);
    playTo(10);
    await controller.openVideo(bv, cid: 137649200, start: 0);
    emit(PlayerStatus.playing);
    playTo(50);
    reporter.seeked(60);
    await reporter.leave();
    expect(beats().map((beat) => beat['cid']), ['$cid', '$cid']);
    expect(beats().last['last_play_progress_time'], '10');
    expect(places().single['cid'], '$cid');
    expect(places().single['progress'], '10');
  });

  test('played again after its end (重播, a loop), the open is another play with its own session', () async {
    final reporter = make(followed: true);
    emit(PlayerStatus.playing);
    playTo(16);
    emit(PlayerStatus.ended);
    seek(reporter, 0);
    emit(PlayerStatus.playing);
    playTo(5);
    await reporter.leave();
    expect(official(), [mobilePath, mobilePath, historyPath, mobilePath, mobilePath, historyPath]);
    final [start, end, again, left] = beats();
    expect(end['session'], start['session']);
    expect(left['session'], again['session']);
    expect(again['session'], isNot(start['session']));
    expect(times(again), ['0', '0', '0', '0', '0', '0']);
    expect(times(left), ['5', '5', '5', '0', '5', '5']);
    expect(places().map((place) => place['progress']), ['-1', '5']);
    expect(beats().map((beat) => beat['auto_play']), ['99', '99', '0', '0'], reason: 'only the open came unasked');
  });

  test('the source and auto_play: a 推荐 card\'s track data on both heartbeats, 99 for an open nobody asked for',
      () async {
    final reporter = make(source: () => recommended, followed: true);
    emit(PlayerStatus.playing);
    playTo(8);
    await reporter.leave();
    for (final beat in beats()) {
      expect(beat['from'], '7');
      expect(beat['from_spmid'], 'tm.recommend.0.0');
      expect(beat['track_id'], 'TRACK.1.2.3');
      expect(beat['report_flow_data'], '{"flow_card_type":"av"}');
      expect(beat['auto_play'], '99');
    }
    expect(beats(), hasLength(2));
  });

  group('who reports', () {
    /// The web heartbeats' own script, as watch_reporter_test.dart plays it.
    Future<void> script(WatchReporter reporter) async {
      emit(PlayerStatus.playing);
      playTo(5);
      playTo(14);
      playTo(16);
      playTo(25);
      emit(PlayerStatus.paused);
      await pumpEventQueue();
      seek(reporter, 300);
      emit(PlayerStatus.playing);
      playTo(301);
      emit(PlayerStatus.ended);
      await pumpEventQueue();
      await reporter.leave();
    }

    List<String?> web() => [for (final request in http.to(webPath)) form(request)['played_time']];

    test('under an Android token, or none, the web heartbeats go out as ever and nothing official', () async {
      for (final token in [tokenOf(OfficialIdentity.android), null]) {
        http.requests.clear();
        seen.clear();
        await controller.openVideo(bv, cid: cid, start: 0);
        at = 0;
        client.appToken = token;
        await script(make());
        expect(web(), ['0', '16', '25', '300', '-1'], reason: '$token');
        expect(official(), isEmpty, reason: '$token');
        expect(seen, [0, 16, 25, 300, 712], reason: '$token');
      }
    });

    test('onProgress hears the same positions under the iPhone token', () async {
      await script(make());
      expect(seen, [0, 16, 25, 300, 712]);
      expect(web(), isEmpty);
      expect(official(), [mobilePath, mobilePath, historyPath]);
    });

    test('nothing goes out while the account may not report (logged out, 推荐\'s card, --fake-account)', () async {
      loggedIn = false;
      final outbox = HistoryOutbox.memory(logger: logger, now: () => wall);
      await script(make(outbox: outbox));
      expect(seen, [0, 16, 25, 300, 712]);
      expect(http.to(webPath), isEmpty);
      expect(official(), isEmpty);
      expect(outbox.plays, isEmpty);
      expect(outbox.holds(bv, cid), isFalse, reason: 'nothing kept either');
    });

    test('a play the page takes over mid-way (推荐\'s card) is reported from there', () async {
      loggedIn = false;
      final reporter = make(source: () => loggedIn ? recommended : PlaySource.unknown);
      emit(PlayerStatus.playing);
      playTo(12);
      await pumpEventQueue();
      expect(official(), isEmpty);

      loggedIn = true;
      playTo(13);
      await pumpEventQueue();
      expect(beats().single['from_spmid'], 'tm.recommend.0.0', reason: 'the source is asked as the play starts');
      playTo(20);
      await reporter.leave();
      expect(times(beats().last), ['7', '7', '7', '0', '20', '20'], reason: 'counted from the take-over');
      expect(beats().last['start_ts'], '${began.add(const Duration(seconds: 13)).millisecondsSinceEpoch ~/ 1000}');
    });

    test('the mode is the open\'s: a token that comes mid-play changes nothing until the next open', () async {
      client.appToken = null;
      final reporter = make();
      emit(PlayerStatus.playing);
      client.appToken = tokenOf(OfficialIdentity.iphone);
      playTo(16);
      await reporter.leave();
      expect(web(), ['0', '16', '16']);
      expect(official(), isEmpty);
    });
  });

  group('the log', () {
    String everything() => [
      for (final event in logs.events)
        '${event.msg} ${[for (final MapEntry(:key, :value) in event.f.entries) '$key=${value.toJson()}'].join(' ')}',
    ].join('\n');

    test('one line per report: its kind and ok, and an end\'s seconds played', () async {
      final reporter = make(source: () => recommended);
      emit(PlayerStatus.playing);
      playTo(8);
      await reporter.leave();
      expect(reportLines(), [
        {'kind': 'start', 'ok': true},
        {'kind': 'end', 'ok': true, 'played': 8},
        {'kind': 'history', 'ok': true},
      ]);
    });

    test('a failure says the error\'s type and Bilibili\'s code, never its text', () async {
      http.routes[mobilePath] = (200, '{"code":-400,"message":"请求错误","ttl":1}');
      http.errors[historyPath] = const SocketException('offline https://api.bilibili.com/x?access_key=ACCESS');
      final reporter = make(source: () => recommended);
      emit(PlayerStatus.playing);
      playTo(8);
      await reporter.leave();
      expect(reportLines(), [
        {'kind': 'start', 'error': 'BiliAPIError', 'code': -400},
        {'kind': 'end', 'error': 'BiliAPIError', 'code': -400, 'played': 8},
        {'kind': 'history', 'error': 'BiliNetworkError'},
      ]);
      expect(everything(), isNot(contains('请求错误')));
    });

    test('no token, track data, session or address reaches a line', () async {
      final outbox = HistoryOutbox.memory(logger: logger, now: () => wall);
      final reporter = make(outbox: outbox, source: () => recommended);
      emit(PlayerStatus.playing);
      playTo(16);
      emit(PlayerStatus.paused);
      http.errors[mobilePath] = const SocketException('offline https://api.bilibili.com/x?access_key=ACCESS');
      await reporter.leave();
      http.errors.remove(mobilePath);
      await flush(outbox);
      final session = beats().first['session']!;
      final text = everything();
      for (final secret in ['ACCESS', 'REFRESH', 'TRACK', 'flow_card_type', session, 'https://', 'access_key']) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(reportLines().map((line) => line['kind']), ['start', 'end', 'end', 'history']);
    });
  });

  group('the outbox', () {
    late Directory folder;
    late String path;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('watch-plays');
      addTearDown(() => folder.deleteSync(recursive: true));
      path = '${folder.path}${Platform.pathSeparator}history_outbox.json';
    });

    Future<HistoryOutbox> load() => HistoryOutbox.load(path, logger: logger, now: () => wall);

    Future<List<Map<String, Object?>>> saved(HistoryOutbox outbox) async {
      await outbox.settle();
      if (!File(path).existsSync()) return [];
      return (jsonDecode(File(path).readAsStringSync()) as List).cast<Map<String, Object?>>();
    }

    test('the running play is saved every 15 s of play and on pause, and nothing sends it while it runs', () async {
      final outbox = await load();
      final reporter = make(outbox: outbox, source: () => recommended);
      emit(PlayerStatus.playing);
      playTo(10);
      expect(await saved(outbox), isEmpty, reason: 'not 15 s in yet');
      playTo(16);
      expect((await saved(outbox)).single['played'], 16);
      playTo(17);
      playTo(30);
      expect((await saved(outbox)).single['played'], 16, reason: 'one save per 15 s of play');
      playTo(31);
      expect((await saved(outbox)).single['played'], 31);
      playTo(35);
      emit(PlayerStatus.paused);
      expect((await saved(outbox)).single['played'], 35, reason: 'a pause saves');

      expect(outbox.plays, isEmpty, reason: 'still running');
      expect(outbox.holds(bv, cid), isTrue);
      await flush(outbox);
      expect(official(), [mobilePath], reason: 'only the start report so far');

      await reporter.leave();
      expect(official(), [mobilePath, mobilePath, historyPath]);
      expect(await saved(outbox), isEmpty, reason: 'sent, it is dropped');
      expect(outbox.holds(bv, cid), isFalse);
    });

    test('a play the app was killed in goes out at the next launch\'s flush, from what was saved', () async {
      final outbox = await load();
      make(outbox: outbox, source: () => recommended);
      emit(PlayerStatus.playing);
      playTo(20);
      emit(PlayerStatus.paused);
      final entry = (await saved(outbox)).single;
      final text = File(path).readAsStringSync();
      for (final secret in ['ACCESS', 'REFRESH', 'access_key', 'appkey', 'sign']) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(entry.keys.toSet(), {
        'session', 'mid', 'aid', 'cid', 'duration', 'spmid', 'from', 'from_spmid', 'track_id', 'flow_data', //
        'start_ts', 'played', 'actual_played', 'total', 'paused', 'last', 'max', 'quality', 'auto_play', //
        'finished', 'reported', 'at',
      }, reason: 'the report\'s own numbers, ids and source, nothing else');

      // The app is killed: no leave. The next launch reads the file.
      wall = wall.add(const Duration(hours: 1));
      final next = await load();
      expect(next.plays.single.report.playedTime, 20);
      await flush(next);
      expect(official(), [mobilePath, mobilePath, historyPath]);
      final [start, end] = beats();
      expect(end['session'], start['session']);
      expect(times(end), ['20', '20', '20', '0', '20', '20'], reason: 'as it stood when saved');
      expect(end['track_id'], 'TRACK.1.2.3');
      expect(end['report_flow_data'], '{"flow_card_type":"av"}');
      expect(places().single['progress'], '20');
      expect(next.plays, isEmpty);
      expect(await saved(next), isEmpty);
    });

    test('an end report that gets no answer waits, the history report behind it, and both go at the next flush',
        () async {
      final outbox = await load();
      final reporter = make(outbox: outbox);
      emit(PlayerStatus.playing);
      playTo(8);
      http.errors[mobilePath] = const SocketException('offline');
      await reporter.leave();
      expect(official(), [mobilePath, mobilePath], reason: 'the end got no answer');
      expect(outbox.plays.single.report.playedTime, 8);
      expect(outbox.holds(bv, cid), isTrue);
      expect((await saved(outbox)).single['reported'], isFalse);

      http.errors.remove(mobilePath);
      await flush(outbox);
      expect(official(), [mobilePath, mobilePath, mobilePath, historyPath]);
      expect(places().single['progress'], '8');
      expect(outbox.plays, isEmpty);
    });

    test('logged out before the play ends, what was saved of it is dropped', () async {
      final outbox = await load();
      final reporter = make(outbox: outbox);
      emit(PlayerStatus.playing);
      playTo(16);
      expect(await saved(outbox), hasLength(1));
      loggedIn = false;
      await reporter.leave();
      expect(official(), [mobilePath]);
      expect(await saved(outbox), isEmpty);
    });
  });
}
