import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/video/history_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

/// The official iPhone reports' plays in the outbox: kept while they run, sent once over, each once and oldest
/// first, under the rules its web heartbeats wait by.
void main() {
  late MemorySink logs;
  late Logger logger;
  late DateTime now;
  late HistoryOutbox outbox;

  /// What the sender was asked for, in order: `end a`, `history a`.
  late List<String> calls;
  late Map<String, Object> failures;
  late List<(String, int, int)> beats;
  late int reads;
  late List<HistoryItem> watched;

  setUp(() {
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    now = DateTime(2026, 11, 12, 12);
    outbox = HistoryOutbox.memory(logger: logger, now: () => now);
    calls = [];
    failures = {};
    beats = [];
    reads = 0;
    watched = [];
  });

  PendingPlay play(String session, {int aid = 1, int cid = 11, int mid = 7, bool finished = false}) => PendingPlay(
    mid: mid,
    report: WatchReport(
      aid: aid,
      cid: cid,
      duration: 100,
      session: session,
      source: const PlaySource(fromSpmid: 'tm.recommend.0.0', from: '7', trackId: 'TRACK', flowData: '{"k":1}'),
      spmid: 'united.player-video-detail.0.0',
      startTs: 5,
      playedTime: 8,
      actualPlayedTime: 9,
      totalTime: 12,
      pausedTime: 3,
      lastProgress: 7,
      maxProgress: 10,
      quality: 80,
      autoPlay: 99,
    ),
    finished: finished,
    at: now,
  );

  /// A play that is over, made now; the clock then moves a minute on.
  void over(PendingPlay play) {
    outbox
      ..keepPlay(play)
      ..endPlay(play.report.session);
    now = now.add(const Duration(minutes: 1));
  }

  PlaySender sender({int mid = 7}) {
    Future<void> call(String what) async {
      calls.add(what);
      final failure = failures[what];
      if (failure != null) throw failure;
    }

    return PlaySender(
      mid: mid,
      end: (play) => call('end ${play.report.session}'),
      history: (play) => call('history ${play.report.session}'),
    );
  }

  Future<void> heartbeat({required String bvid, required int cid, required int playedTime}) async {
    beats.add((bvid, cid, playedTime));
    final failure = failures[bvid];
    if (failure != null) throw failure;
  }

  Future<HistoryPage> recent() async {
    reads++;
    return HistoryPage(items: watched, next: null);
  }

  Future<void> flush({PlaySender? plays, bool noSender = false}) =>
      outbox.flush(heartbeat, recent: recent, plays: noSender ? null : plays ?? sender());

  List<String> waiting() => [for (final play in outbox.plays) play.report.session];

  List<Map<String, Object>> outboxLines() => [
    for (final event in logs.events)
      if (event.msg == 'history outbox') {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
  ];

  const offline = BiliNetworkError('SocketException');

  test('a play still running is kept and held but never sent; over, its end report goes, then its place', () async {
    outbox.keepPlay(play('a'));
    expect(waiting(), isEmpty);
    expect(outbox.holds('BV1a', 11), isTrue, reason: 'what this phone saw of the part is newer than Bilibili\'s');
    expect(outbox.holds('BV1a', 12), isFalse);
    await flush();
    await outbox.sendPlays(sender(), recent: recent);
    expect(calls, isEmpty);

    outbox.endPlay('a');
    expect(waiting(), ['a']);
    await flush();
    expect(calls, ['end a', 'history a']);
    expect(waiting(), isEmpty);
    expect(outbox.holds('BV1a', 11), isFalse);
    expect(outboxLines().last, {'sent': 1, 'dropped': 0, 'stale': 0, 'failed': 0, 'held': 0});

    await flush();
    expect(calls, hasLength(2), reason: 'each play once');
  });

  test('oldest first, and the first that gets no answer stops the rest', () async {
    over(play('a'));
    over(play('b'));
    over(play('c'));
    failures['end b'] = offline;
    await flush();
    expect(calls, ['end a', 'history a', 'end b']);
    expect(waiting(), ['b', 'c']);
    expect(outboxLines().last, {'sent': 1, 'dropped': 0, 'stale': 0, 'failed': 1, 'held': 2});

    failures.clear();
    await flush();
    expect(calls.skip(3), ['end b', 'history b', 'end c', 'history c']);
    expect(waiting(), isEmpty);
  });

  test('the end report taken and its place unanswered: only the place goes again', () async {
    over(play('a'));
    failures['history a'] = offline;
    await flush();
    expect(calls, ['end a', 'history a']);
    expect(outbox.plays.single.reported, isTrue);
    failures.clear();
    await flush();
    expect(calls, ['end a', 'history a', 'history a'], reason: 'the play\'s time is never counted twice');
    expect(waiting(), isEmpty);
  });

  test('a call Bilibili refuses outright is given up, the other still goes', () async {
    over(play('a'));
    over(play('b'));
    failures['end a'] = const BiliAPIError(code: -400, message: '请求错误');
    failures['history b'] = const BiliAPIError(code: -404, message: '啥都木有');
    await flush();
    expect(calls, ['end a', 'history a', 'end b', 'history b']);
    expect(waiting(), isEmpty);
    expect(outboxLines().last, {'sent': 0, 'dropped': 2, 'stale': 0, 'failed': 0, 'held': 0});
  });

  test('a refused login, a missing token or risk control keeps the play and stops the flush', () async {
    over(play('a'));
    over(play('b'));
    for (final refusal in <Object>[
      const BiliAPIError(code: -101, message: '账号未登录'),
      const BiliAPIError(code: -2, message: 'Access Key错误'),
      const BiliAPIError(code: -352, message: '风控校验失败'),
      const BiliHTTPError(412),
      BiliError.noAppToken,
    ]) {
      calls.clear();
      failures['end a'] = refusal;
      await flush();
      expect(calls, ['end a'], reason: '$refusal');
      expect(waiting(), ['a', 'b'], reason: '$refusal');
    }
  });

  List<LogEvent> reportEvents() => [
    for (final event in logs.events)
      if (event.msg == 'watch report') event,
  ];

  test('a play whose own call faults is stepped past, and given up at the fifth flush it faults in', () async {
    over(play('a'));
    over(play('b'));
    failures['end a'] = const BiliHTTPError(500);
    await flush();
    expect(calls, ['end a', 'end b', 'history b'], reason: 'the newer play does not wait behind it');
    expect(waiting(), ['a']);
    expect(outbox.plays.single.strikes, 1);
    expect(outboxLines().last, {'sent': 1, 'dropped': 0, 'stale': 0, 'failed': 1, 'held': 1});

    for (var strikes = 2; strikes < HistoryOutbox.maxStrikes; strikes++) {
      await flush();
      expect(outbox.plays.single.strikes, strikes);
    }
    expect(reportEvents(), isEmpty);

    await flush();
    expect(calls.where((call) => call == 'end a'), hasLength(5));
    expect(calls, isNot(contains('history a')));
    expect(waiting(), isEmpty);
    expect(outbox.holds('BV1a', 11), isFalse);
    final line = reportEvents().single;
    expect(line.level, LogLevel.warn);
    expect(
      {for (final MapEntry(:key, :value) in line.f.entries) key: value.toJson()},
      {'kind': 'given up', 'strikes': 5, 'error': 'BiliHTTPError', 'code': 500},
    );
    expect(outboxLines().last, {'sent': 0, 'dropped': 1, 'stale': 0, 'failed': 0, 'held': 0});

    await flush();
    expect(calls.where((call) => call == 'end a'), hasLength(5), reason: 'given up, it is not sent again');
  });

  test('what strikes a play: an HTTP error status, an answer that does not decode, a StateError, a passing code',
      () async {
    for (final fault in <Object>[
      const BiliHTTPError(502),
      const BiliDecodingError('not JSON'),
      StateError('watch reports are only known for the iPhone identity'),
      for (final code in [-500, -503, -509, -799]) BiliAPIError(code: code, message: '服务调用失败'),
    ]) {
      outbox = HistoryOutbox.memory(logger: logger, now: () => now);
      calls.clear();
      failures.clear();
      over(play('a'));
      over(play('b'));
      failures['history a'] = fault;
      await flush();
      expect(calls, ['end a', 'history a', 'end b', 'history b'], reason: '$fault');
      expect(outbox.plays.single.strikes, 1, reason: '$fault');
      expect(outbox.plays.single.reported, isTrue, reason: 'its end report is not sent again');

      failures.clear();
      await flush();
      expect(calls.skip(4), ['history a'], reason: '$fault');
      expect(waiting(), isEmpty, reason: '$fault');
    }
  });

  test('what holds the whole queue costs a play no strike, however often', () async {
    over(play('a'));
    over(play('b'));
    failures['end a'] = const BiliAPIError(code: -101, message: '账号未登录');
    for (var i = 0; i <= HistoryOutbox.maxStrikes; i++) {
      await flush();
    }
    expect(calls, List.filled(HistoryOutbox.maxStrikes + 1, 'end a'), reason: 'the pass stops there every time');
    expect(waiting(), ['a', 'b']);
    expect(outbox.plays.map((play) => play.strikes), [0, 0]);
    expect(reportEvents(), isEmpty);
  });

  test('the summary counts as sent only a play Bilibili took, a refused one as dropped, a struck one as failed',
      () async {
    over(play('a'));
    over(play('b'));
    over(play('c'));
    failures['end a'] = const BiliAPIError(code: -400, message: '请求错误');
    failures['end c'] = const BiliHTTPError(500);
    await flush();
    expect(calls, ['end a', 'history a', 'end b', 'history b', 'end c']);
    expect(waiting(), ['c']);
    expect(outboxLines().last, {'sent': 1, 'dropped': 1, 'stale': 0, 'failed': 1, 'held': 1});
  });

  test('a pass sends 5 plays at most, oldest first; the rest wait for the next flush', () async {
    final sessions = [for (var i = 0; i < 12; i++) 'p${i.toString().padLeft(2, '0')}'];
    for (final session in sessions) {
      over(play(session));
    }
    await flush();
    expect(calls, [for (final session in sessions.take(5)) ...['end $session', 'history $session']]);
    expect(waiting(), sessions.skip(5));
    expect(outboxLines().last, {'sent': 5, 'dropped': 0, 'stale': 0, 'failed': 0, 'held': 7});

    calls.clear();
    await flush();
    expect(calls, [for (final session in sessions.skip(5).take(5)) ...['end $session', 'history $session']]);
    expect(outboxLines().last, {'sent': 5, 'dropped': 0, 'stale': 0, 'failed': 0, 'held': 2});

    calls.clear();
    await flush();
    expect(calls, ['end p10', 'history p10', 'end p11', 'history p11']);
    expect(waiting(), isEmpty);
    expect(outboxLines().last, {'sent': 2, 'dropped': 0, 'stale': 0, 'failed': 0, 'held': 0});
  });

  test('a call that finds another account\'s token held sends nothing, and its play is dropped', () async {
    over(play('a'));
    over(play('b'));
    failures['end a'] = const AnotherAccountsPlay();
    failures['history b'] = const AnotherAccountsPlay();
    await flush();
    expect(calls, ['end a', 'end b', 'history b']);
    expect(waiting(), isEmpty);
    expect(outboxLines().last, {'sent': 0, 'dropped': 2, 'stale': 0, 'failed': 0, 'held': 0});
  });

  test('a play watched as another account is dropped unsent', () async {
    over(play('a', mid: 7));
    over(play('b', mid: 8));
    await flush(plays: sender(mid: 8));
    expect(calls, ['end b', 'history b']);
    expect(waiting(), isEmpty);
    expect(outboxLines().last, {'sent': 1, 'dropped': 1, 'stale': 0, 'failed': 0, 'held': 0});
  });

  test('with no iPhone token now the plays wait, and the web heartbeats still go', () async {
    try {
      await outbox.send('BV1w', 3, 42, () async => throw offline);
    } on BiliNetworkError {
      // Kept for the flush.
    }
    over(play('a'));
    await flush(noSender: true);
    expect(beats, [('BV1w', 3, 42)]);
    expect(calls, isEmpty);
    expect(waiting(), ['a']);
    expect(outboxLines().last, {'sent': 1, 'dropped': 0, 'stale': 0, 'failed': 0, 'held': 1});
  });

  test('the web heartbeats go first; one that gets no answer stops the plays too', () async {
    try {
      await outbox.send('BV1w', 3, 42, () async => throw offline);
    } on BiliNetworkError {
      // Kept for the flush.
    }
    over(play('a'));
    failures['BV1w'] = offline;
    await flush();
    expect(calls, isEmpty);
    failures.clear();
    await flush();
    expect(beats, [('BV1w', 3, 42), ('BV1w', 3, 42)]);
    expect(calls, ['end a', 'history a']);
  });

  HistoryItem seen(int aid, DateTime at) => HistoryItem(
    aid: aid,
    bvid: 'BV$aid',
    cid: 1,
    title: '',
    cover: '',
    ownerName: '',
    progress: 0,
    duration: 0,
    viewAt: at.millisecondsSinceEpoch ~/ 1000,
    device: 0,
    part: null,
  );

  test('older than 5 minutes, a play whose video the account has watched since sends its end report only', () async {
    final made = now;
    over(play('a', aid: 1));
    over(play('b', aid: 2));
    now = made.add(const Duration(hours: 2));
    watched = [
      // Watched on another device after this phone's play: its place is the account's now.
      seen(1, made.add(const Duration(minutes: 30))),
      seen(2, made.subtract(const Duration(minutes: 1))),
    ];
    await flush();
    expect(reads, 1);
    expect(calls, ['end a', 'end b', 'history b']);
    expect(waiting(), isEmpty);
  });

  test('sendPlays sends what is over without a flush, and reads the history only for an old one', () async {
    over(play('a'));
    await outbox.sendPlays(sender(), recent: recent);
    expect(calls, ['end a', 'history a']);
    expect(reads, 0);
    expect(outboxLines(), isEmpty, reason: 'the reports log themselves');

    over(play('b'));
    now = now.add(const Duration(minutes: 10));
    watched = [seen(1, now)];
    await outbox.sendPlays(sender(), recent: recent);
    expect(reads, 1);
    expect(calls.skip(2), ['end b']);
    expect(waiting(), isEmpty);
  });

  test('a play sent by one pass is gone for another waiting behind it', () async {
    over(play('a'));
    final both = [flush(), outbox.sendPlays(sender(), recent: recent)];
    await Future.wait(both);
    expect(calls, ['end a', 'history a']);
  });

  test('logging out drops the plays, the running one too; ended after, it stays dropped', () async {
    over(play('a'));
    outbox.keepPlay(play('b'));
    outbox.clear();
    expect(outboxLines().last, {'dropped': 2, 'held': 0});
    outbox.endPlay('b');
    await flush();
    expect(calls, isEmpty);
    expect(outbox.holds('BV1a', 11), isFalse);
  });

  test('a play ended with nothing to report is dropped', () {
    outbox.keepPlay(play('a'));
    outbox.dropPlay('a');
    outbox.endPlay('a');
    expect(waiting(), isEmpty);
    expect(outbox.holds('BV1a', 11), isFalse);
  });

  test('after 30 days a play no longer counts, and the next flush drops it unsent', () async {
    over(play('a'));
    now = now.add(const Duration(days: 31));
    expect(outbox.holds('BV1a', 11), isFalse);
    await flush();
    expect(calls, isEmpty);
    expect(reads, 0);
    expect(waiting(), isEmpty);
    expect(outboxLines().last, {'sent': 0, 'dropped': 1, 'stale': 0, 'failed': 0, 'held': 0});
  });

  group('history_outbox.json', () {
    late Directory folder;
    late String path;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('history-outbox-plays');
      addTearDown(() => folder.deleteSync(recursive: true));
      path = '${folder.path}${Platform.pathSeparator}history_outbox.json';
    });

    Future<HistoryOutbox> load() => HistoryOutbox.load(path, logger: logger, now: () => now);

    test('plays and web heartbeats share the file; a play read back is over, whatever it was', () async {
      outbox = await load();
      try {
        await outbox.send('BV1w', 3, 42, () async => throw offline);
      } on BiliNetworkError {
        // Kept for the flush.
      }
      outbox.keepPlay(play('a', finished: true));
      now = now.add(const Duration(minutes: 1));
      over(play('b'));
      await outbox.settle();

      final again = await load();
      expect([for (final each in again.reports) (each.bvid, each.cid, each.played)], [('BV1w', 3, 42)]);
      expect([for (final each in again.plays) each.report.session], ['a', 'b']);
      final read = again.plays.first;
      expect(read.toJson(), play('a', finished: true).toJson()..['at'] = read.at.millisecondsSinceEpoch);
      expect(read.finished, isTrue);
      expect(read.report.source.trackId, 'TRACK');
      expect(read.report.source.flowData, '{"k":1}');
      expect(outboxLines().last, {'held': 3, 'dropped': 0});
    });

    test('a play from nowhere known keeps no track data; one missing a field is skipped', () async {
      final nowhere = PendingPlay(
        mid: 7,
        report: const WatchReport(aid: 1, cid: 11, duration: 100, session: 'n', source: PlaySource.unknown, spmid: 's'),
        finished: false,
        at: now,
      );
      final broken = nowhere.toJson()
        ..['session'] = 'x'
        ..remove('played');
      File(path).writeAsStringSync(jsonEncode([nowhere.toJson(), broken]));
      expect(nowhere.toJson().containsKey('track_id'), isFalse);
      expect(nowhere.toJson().containsKey('flow_data'), isFalse);
      final loaded = await load();
      final read = loaded.plays.single;
      expect(read.report.session, 'n');
      expect(read.report.source.trackId, isNull);
      expect(read.report.source.flowData, isNull);
      expect(logs.events.map((event) => event.msg), contains('history outbox entries skipped'));
    });

    test('the place left unanswered is saved as such, so the next launch sends only it', () async {
      outbox = await load();
      over(play('a'));
      failures['history a'] = offline;
      await flush();
      await outbox.settle();
      failures.clear();
      calls.clear();

      outbox = await load();
      await flush();
      expect(calls, ['history a']);
      await outbox.settle();
      expect(jsonDecode(File(path).readAsStringSync()), isEmpty);
    });

    test('the end report taken, the play is on disk as settled before its place is asked for', () async {
      outbox = await load();
      over(play('a'));
      await outbox.settle();
      expect((jsonDecode(File(path).readAsStringSync()) as List).single, containsPair('reported', false));

      // A kill during the history call leaves the file as that call finds it.
      Object? found;
      final reading = PlaySender(
        mid: 7,
        end: (_) async {},
        history: (_) async {
          found = jsonDecode(File(path).readAsStringSync());
        },
      );
      await flush(plays: reading);
      expect((found! as List).single, containsPair('reported', true));
    });

    test('a play\'s strikes are kept in the file, and a play saved without any reads as none', () async {
      outbox = await load();
      over(play('a'));
      over(play('b'));
      failures['end a'] = const BiliHTTPError(500);
      failures['end b'] = offline;
      await flush();
      await flush();
      await outbox.settle();
      final entries = (jsonDecode(File(path).readAsStringSync()) as List).cast<Map<String, Object?>>();
      expect({for (final entry in entries) entry['session']: entry['strikes']}, {'a': 2, 'b': null});

      outbox = await load();
      expect({for (final each in outbox.plays) each.report.session: each.strikes}, {'a': 2, 'b': 0});
      failures.clear();
      calls.clear();
      await flush();
      expect(calls, ['end a', 'history a', 'end b', 'history b']);
    });
  });
}
