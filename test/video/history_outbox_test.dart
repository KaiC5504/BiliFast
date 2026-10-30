import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/video/history_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';

const heartbeatPath = '/x/click-interface/web/heartbeat';
const ok = '{"code":0,"message":"0"}';

/// Watch reports with no answer wait for the network, one per part, for 30 days; a flush sends them one at a time.
void main() {
  late CannedHttp http;
  late BiliClient client;
  late MemorySink logs;
  late Logger logger;
  late DateTime now;
  late HistoryOutbox outbox;

  setUp(() {
    http = Canned.http()..routes[heartbeatPath] = (200, ok);
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: logger);
    now = DateTime(2026, 10, 30, 12);
    outbox = HistoryOutbox.memory(logger: logger, now: () => now);
  });

  /// A page's report through [outbox], as WatchReporter sends it; its error, if any.
  Future<Object?> report(String bvid, int cid, int played, {BiliClient? over}) async {
    try {
      await outbox.send(bvid, cid, played, () => (over ?? client).heartbeat(bvid: bvid, cid: cid, playedTime: played));
      return null;
    } catch (error) {
      return error;
    }
  }

  List<(String, int, int)> waiting() => [for (final each in outbox.reports) (each.bvid, each.cid, each.played)];

  List<Map<String, Object>> outboxLines() => [
    for (final event in logs.events)
      if (event.msg == 'history outbox') {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
  ];

  void offline() => http.errors[heartbeatPath] = const SocketException('offline');

  void online([(int, String) answer = (200, ok)]) {
    http.errors.remove(heartbeatPath);
    http.routes[heartbeatPath] = answer;
  }

  test('a report that gets no answer waits, the latest one per part', () async {
    offline();
    expect(await report('BV1a', 1, 10), isA<BiliNetworkError>());
    now = now.add(const Duration(seconds: 15));
    await report('BV1a', 1, 25);
    await report('BV1b', 2, -1);
    expect(waiting(), [('BV1a', 1, 25), ('BV1b', 2, -1)]);
    expect(outbox.holds('BV1a', 1), isTrue);
    expect(outbox.holds('BV1a', 3), isFalse);
    expect(outboxLines(), [
      {'queued': 1, 'held': 1},
      {'queued': 1, 'held': 2},
    ], reason: 'a newer report of a waiting part replaces it quietly');
  });

  test('a later report of the part that goes through clears it; refusals neither clear nor queue', () async {
    offline();
    await report('BV1a', 1, 10);
    online((200, '{"code":-400,"message":"请求错误"}'));
    expect(await report('BV1a', 1, 30), isA<BiliAPIError>());
    expect(await report('BV1b', 2, 7), isA<BiliAPIError>());
    online((412, ''));
    expect(await report('BV1b', 2, 8), isA<BiliHTTPError>());
    expect(waiting(), [('BV1a', 1, 10)], reason: 'answers, not the network: nothing queued, nothing cleared');

    online();
    await report('BV1b', 2, 9);
    expect(waiting(), [('BV1a', 1, 10)], reason: 'another part goes through and leaves it');
    await report('BV1a', 1, 40);
    expect(waiting(), isEmpty);
  });

  test('the Windows guard\'s refusal is never queued', () async {
    final guarded = BiliClient(
      transport: GuardedTransport(http, logger: logger),
      cookies: CookieJar(Canned.cookies),
      logger: logger,
    );
    final error = await report('BV1a', 1, 10, over: guarded);
    expect(error, isA<BiliAPIError>().having((error) => error.code, 'code', GuardedTransport.readOnlyCode));
    expect(waiting(), isEmpty);
    expect(http.to(heartbeatPath), isEmpty);
  });

  group('flush', () {
    late List<(String, int, int)> sent;
    late Map<String, Object> failures;
    Completer<void>? gate;

    Future<void> heartbeat({required String bvid, required int cid, required int playedTime}) async {
      sent.add((bvid, cid, playedTime));
      await gate?.future;
      final failure = failures[bvid];
      if (failure != null) throw failure;
    }

    setUp(() {
      sent = [];
      failures = {};
      gate = null;
    });

    Future<void> queue(List<(String, int, int)> reports) async {
      offline();
      for (final (bvid, cid, played) in reports) {
        await report(bvid, cid, played);
        now = now.add(const Duration(minutes: 1));
      }
      online();
    }

    test('sends what waits oldest first, one at a time, and stops at the first that gets no answer', () async {
      await queue([('BV1a', 1, 10), ('BV1b', 2, 20), ('BV1c', 3, 30)]);
      // The oldest is reported again later, so it goes last.
      offline();
      await report('BV1a', 1, 15);
      online();
      failures['BV1c'] = const BiliNetworkError('SocketException');
      gate = Completer();
      final flushing = outbox.flush(heartbeat);
      await pumpEventQueue();
      expect(sent, [('BV1b', 2, 20)], reason: 'one at a time');
      expect(identical(outbox.flush(heartbeat), flushing), isTrue, reason: 'a flush already running answers');
      gate!.complete();
      await flushing;
      expect(sent, [('BV1b', 2, 20), ('BV1c', 3, 30)], reason: 'BV1a waits behind the failure');
      expect(waiting(), [('BV1c', 3, 30), ('BV1a', 1, 15)]);
      expect(outboxLines().last, {'sent': 1, 'dropped': 0, 'failed': 1, 'held': 2});

      failures.clear();
      await outbox.flush(heartbeat);
      expect(sent.skip(2), [('BV1c', 3, 30), ('BV1a', 1, 15)]);
      expect(waiting(), isEmpty);
      expect(outboxLines().last, {'sent': 2, 'dropped': 0, 'failed': 0, 'held': 0});
    });

    test('drops a report Bilibili refuses outright; a refused login or risk control keeps it', () async {
      await queue([('BV1a', 1, 10), ('BV1b', 2, 20), ('BV1c', 3, 30)]);
      failures['BV1a'] = const BiliAPIError(code: -404, message: '啥都木有');
      failures['BV1b'] = const BiliAPIError(code: -101, message: '账号未登录');
      await outbox.flush(heartbeat);
      expect(sent.map((each) => each.$1), ['BV1a', 'BV1b']);
      expect(waiting(), [('BV1b', 2, 20), ('BV1c', 3, 30)]);
      expect(outboxLines().last, {'sent': 0, 'dropped': 1, 'failed': 1, 'held': 2});

      failures
        ..clear()
        ..['BV1b'] = const BiliHTTPError(412);
      await outbox.flush(heartbeat);
      expect(waiting(), hasLength(2));
      failures['BV1b'] = const BiliAPIError(code: GuardedTransport.readOnlyCode, message: 'PC 只读，未发送');
      await outbox.flush(heartbeat);
      expect(waiting(), hasLength(2));
    });

    test('a page\'s report and a flush never cross: the newer place lands last', () async {
      await queue([('BV1a', 1, 10), ('BV1b', 2, 20)]);
      gate = Completer();
      final flushing = outbox.flush(heartbeat);
      await pumpEventQueue();
      expect(sent, [('BV1a', 1, 10)]);
      // The page reports BV1a again (and BV1b) while the flush's report of it is still out.
      final pages = [
        outbox.send('BV1a', 1, 40, () => heartbeat(bvid: 'BV1a', cid: 1, playedTime: 40)),
        outbox.send('BV1b', 2, 50, () => heartbeat(bvid: 'BV1b', cid: 2, playedTime: 50)),
      ];
      await pumpEventQueue();
      expect(sent, [('BV1a', 1, 10)], reason: 'it waits its turn');
      gate!.complete();
      await Future.wait([flushing, ...pages]);
      expect(sent, [
        ('BV1a', 1, 10),
        ('BV1a', 1, 40),
        ('BV1b', 2, 50),
      ], reason: 'BV1b\'s waiting report was settled by the page\'s, so the flush skips it');
      expect(waiting(), isEmpty);
    });

    test('nothing waiting sends and logs nothing', () async {
      await outbox.flush(heartbeat);
      expect(sent, isEmpty);
      expect(outboxLines(), isEmpty);
    });
  });

  group('30 days', () {
    test('an older report no longer counts, and the next flush drops it unsent', () async {
      offline();
      await report('BV1a', 1, 10);
      now = now.add(const Duration(days: 30));
      expect(outbox.holds('BV1a', 1), isTrue, reason: '30 days to the minute still counts');
      now = now.add(const Duration(minutes: 1));
      expect(outbox.holds('BV1a', 1), isFalse);
      online();
      await outbox.flush(client.heartbeat);
      expect(http.to(heartbeatPath), hasLength(1), reason: 'only the first report\'s try');
      expect(waiting(), isEmpty);
      expect(outboxLines().last, {'sent': 0, 'dropped': 1, 'failed': 0, 'held': 0});
    });
  });

  group('history_outbox.json', () {
    late Directory folder;
    late String path;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('history-outbox');
      addTearDown(() => folder.deleteSync(recursive: true));
      path = '${folder.path}${Platform.pathSeparator}history_outbox.json';
    });

    test('what waits is kept across launches, older than 30 days dropped at load', () async {
      outbox = await HistoryOutbox.load(path, logger: logger, now: () => now);
      offline();
      await report('BV1a', 1, 10);
      now = now.add(const Duration(days: 20));
      await report('BV1b', 2, -1);
      await outbox.settle();

      final again = await HistoryOutbox.load(path, logger: logger, now: () => now);
      expect(
        [for (final each in again.reports) (each.bvid, each.cid, each.played)],
        [('BV1a', 1, 10), ('BV1b', 2, -1)],
      );
      expect(again.reports.first.at, DateTime(2026, 10, 30, 12));

      now = now.add(const Duration(days: 15));
      final later = await HistoryOutbox.load(path, logger: logger, now: () => now);
      expect([for (final each in later.reports) each.bvid], ['BV1b']);
      expect(outboxLines().last, {'held': 1, 'dropped': 1});
      await later.settle();
      expect(jsonDecode(File(path).readAsStringSync()), hasLength(1), reason: 'the drop is saved');
    });

    test('an unreadable file starts empty, and entries that don\'t decode are skipped', () async {
      File(path).writeAsStringSync('{not json');
      expect((await HistoryOutbox.load(path, logger: logger, now: () => now)).reports, isEmpty);

      File(path).writeAsStringSync(
        jsonEncode([
          {'bvid': 'BV1a', 'cid': 1, 'played': 10, 'at': now.millisecondsSinceEpoch},
          {'bvid': 'BV1b', 'cid': '2'},
        ]),
      );
      final loaded = await HistoryOutbox.load(path, logger: logger, now: () => now);
      expect([for (final each in loaded.reports) each.bvid], ['BV1a']);
      expect(logs.events.map((event) => event.msg), contains('history outbox entries skipped'));
    });

    test('no file and nothing waiting: nothing is written or logged', () async {
      final empty = await HistoryOutbox.load(path, logger: logger, now: () => now);
      await empty.settle();
      expect(File(path).existsSync(), isFalse);
      expect(outboxLines(), isEmpty);
    });
  });
}
