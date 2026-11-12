import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'app_signer_test.dart' show makeClient, ts;
import 'fake_http.dart';

const heartbeatPath = '/x/report/heartbeat/mobile';
const historyPath = '/x/v2/history/report';
const ok = '{"code":0,"message":"0","ttl":1}';
const session = '0123456789abcdef0123456789abcdef';
const idfv = '6F1C2D3E-0000-4000-8000-123456789ABC';

AppToken tokenOf(OfficialIdentity identity) => AppToken(
  accessToken: 'ACCESS',
  refreshToken: 'REFRESH',
  mid: 7,
  expiresAt: DateTime.utc(2027, 4, 1),
  identity: identity,
);

const recommended = PlaySource(
  fromSpmid: 'tm.recommend.0.0',
  from: '7',
  trackId: 'TRACK.1.2.3',
  flowData: '{"flow_card_type":"av"}',
);

WatchReport report({PlaySource source = recommended, bool end = false, int autoPlay = 0}) => WatchReport(
  aid: 80433022,
  cid: 137649199,
  duration: 10,
  session: session,
  source: source,
  spmid: 'united.player-video-detail.0.0',
  quality: 80,
  autoPlay: autoPlay,
  startTs: end ? 1702204161 : 0,
  playedTime: end ? 8 : 0,
  actualPlayedTime: end ? 8 : 0,
  totalTime: end ? 9 : 0,
  pausedTime: end ? 1 : 0,
  lastProgress: end ? 7 : 0,
  maxProgress: end ? 7 : 0,
);

/// The official iPhone app's watch reports (docs/reference/official-iphone-calls.md, "A play's reports").
void main() {
  late FakeHTTP http;
  late BiliClient client;

  setUp(() {
    http = FakeHTTP()..routes = {heartbeatPath: (200, ok), historyPath: (200, ok)};
    client = makeClient(http)
      ..appToken = tokenOf(OfficialIdentity.iphone)
      ..appIdfv = idfv;
  });

  Map<String, String> sent(String path, [int index = 0]) => formFields(http.bodyText(http.requestsTo(path)[index]));

  void expectFields(Map<String, String> form, Map<String, String> expected) {
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(form[key], value, reason: key);
    }
  }

  /// What every heartbeat says whatever the play.
  const fixed = {
    'aid': '80433022',
    'cid': '137649199',
    'mid': '7',
    'type': '3',
    'sub_type': '0',
    'epid': '0',
    'sid': '0',
    'epid_status': '0',
    'session': session,
    'sessionID': session,
    'list_play_time': '0',
    'miniplayer_play_time': '0',
    'video_duration': '10',
    'quality': '80',
    'play_type': '1',
    'play_mode': '1',
    'play_status': '0',
    'user_status': '0',
    'network_type': '1',
    'is_audio_play': '2',
    'is_auto_qn': '0',
    'cur_language': '',
    'perfer_type': '',
    'from': '7',
    'from_spmid': 'tm.recommend.0.0',
    'spmid': 'united.player-video-detail.0.0',
    'track_id': 'TRACK.1.2.3',
    'report_flow_data': '{"flow_card_type":"av"}',
    'extra': '{"player_report_json":"","material_no":""}',
    'idfa': '00000000-0000-0000-0000-000000000000',
    'idfv': idfv,
    'teenagers_age': '16',
    'statistics': '{"appId":1,"version":"9.18.0","abtest":"","platform":1}',
    'access_key': 'ACCESS',
  };

  group('the heartbeat', () {
    test('at the start: the play\'s ids and labels, every time 0', () async {
      await client.mobileHeartbeat(report());
      final request = http.requestsTo(heartbeatPath).single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.bilibili.com$heartbeatPath');
      expect(request.headers['Content-Type'], 'application/x-www-form-urlencoded; charset=UTF-8');
      final form = sent(heartbeatPath);
      expectFields(form, {
        ...fixed,
        'auto_play': '0',
        'start_ts': '0',
        'played_time': '0',
        'actual_played_time': '0',
        'total_time': '0',
        'paused_time': '0',
        'last_play_progress_time': '0',
        'max_play_progress_time': '0',
      });
      expect(form['sign'], hasLength(32));
      expect(form['ts'], ts);
    });

    test('at the end: when it began and what was watched', () async {
      await client.mobileHeartbeat(report(end: true, autoPlay: 99));
      expectFields(sent(heartbeatPath), {
        ...fixed,
        'auto_play': '99',
        'start_ts': '1702204161',
        'played_time': '8',
        'actual_played_time': '8',
        'total_time': '9',
        'paused_time': '1',
        'last_play_progress_time': '7',
        'max_play_progress_time': '7',
      });
    });

    test('a play from nowhere known: from and track_id empty, no report_flow_data; no idfv off iOS', () async {
      client.appIdfv = null;
      await client.mobileHeartbeat(report(source: PlaySource.unknown));
      final form = sent(heartbeatPath);
      expectFields(form, {'from': '', 'from_spmid': '', 'track_id': ''});
      expect(form.containsKey('report_flow_data'), isFalse);
      expect(form.containsKey('idfv'), isFalse);
    });

    test('polaris_action_id is 8 upper-case hex characters, new for each report', () async {
      for (var i = 0; i < 4; i++) {
        await client.mobileHeartbeat(report());
      }
      final ids = [for (var i = 0; i < 4; i++) sent(heartbeatPath, i)['polaris_action_id']!];
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[0-9A-F]{8}$')));
      }
      expect(ids.toSet(), hasLength(4));
    });
  });

  group('the history report', () {
    test('says where the play stopped, when it began and the time now, and names no source', () async {
      await client.historyReport(aid: 80433022, cid: 137649199, progress: 7, duration: 10, startTs: 1702204161);
      final request = http.requestsTo(historyPath).single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.bilibili.com$historyPath');
      final form = sent(historyPath);
      expectFields(form, {
        'aid': '80433022',
        'cid': '137649199',
        'type': '3',
        'sub_type': '0',
        'epid': '0',
        'sid': '0',
        'progress': '7',
        'duration': '10',
        'start_ts': '1702204161',
        'device_ts': ts,
        'scene': 'front',
        'teenagers_age': '16',
        'statistics': '{"appId":1,"version":"9.18.0","abtest":"","platform":1}',
        'access_key': 'ACCESS',
      });
      expect(form.containsKey('source'), isFalse);
      expect(form['sign'], hasLength(32));
    });

    test('a video watched to its end is -1', () async {
      await client.historyReport(aid: 1, cid: 2, progress: -1, duration: 10, startTs: 5);
      expect(sent(historyPath)['progress'], '-1');
    });
  });

  Future<void> expectBoth(Matcher throws) async {
    await expectLater(client.mobileHeartbeat(report()), throws);
    await expectLater(client.historyReport(aid: 1, cid: 2, progress: 3, duration: 10, startTs: 5), throws);
  }

  test('both go out as the app does: the token and a signature, never the cookies or csrf', () async {
    await client.mobileHeartbeat(report());
    await client.historyReport(aid: 1, cid: 2, progress: 3, duration: 10, startTs: 5);
    for (final request in http.requests) {
      expect(request.headers['Cookie'], isNull);
      expect(formFields(http.bodyText(request)).containsKey('csrf'), isFalse);
    }
  });

  test('without a token nothing is sent', () async {
    client.appToken = null;
    await expectBoth(throwsA(BiliError.noAppToken));
    expect(http.requests, isEmpty);
  });

  test('under an Android token nothing is sent: the reports are only known for the iPhone app', () async {
    client.appToken = tokenOf(OfficialIdentity.android);
    await expectBoth(throwsStateError);
    expect(http.requests, isEmpty);
  });

  test('a refusal throws Bilibili\'s code, and a refused token is reported', () async {
    http.routes[heartbeatPath] = (200, '{"code":-400,"message":"请求错误","ttl":1}');
    http.routes[historyPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
    final rejected = <String>[];
    client.onAppTokenRejected = rejected.add;
    await expectLater(client.mobileHeartbeat(report()), throwsA(const BiliError.api(code: -400, message: '请求错误')));
    expect(rejected, isEmpty);
    await expectLater(
      client.historyReport(aid: 1, cid: 2, progress: 3, duration: 10, startTs: 5),
      throwsA(const BiliError.api(code: -101, message: '账号未登录')),
    );
    expect(rejected, ['ACCESS']);
  });

  test('the log names the path and the answer, never the token, the track data or the device', () async {
    final logs = MemorySink();
    final logged = BiliClient(
      transport: http,
      cookies: CookieJar(const {}),
      now: () => testNow,
      logger: Logger(session: 'test')..add(logs),
    )
      ..appToken = tokenOf(OfficialIdentity.iphone)
      ..appIdfv = idfv;
    await logged.mobileHeartbeat(report(end: true));
    await logged.historyReport(aid: 80433022, cid: 137649199, progress: 7, duration: 10, startTs: 1702204161);
    http.routes[heartbeatPath] = (200, '{"code":-400,"message":"请求错误","ttl":1}');
    await expectLater(logged.mobileHeartbeat(report(end: true)), throwsA(isA<BiliAPIError>()));
    expect(logs.events.map((event) => event.msg).toSet(), {heartbeatPath, historyPath});
    final text = [
      for (final event in logs.events)
        '${event.msg} ${[for (final MapEntry(:key, :value) in event.f.entries) '$key=${value.toJson()}'].join(' ')}',
    ].join('\n');
    for (final secret in ['ACCESS', 'REFRESH', 'TRACK', 'flow_card_type', idfv, session, '80433022', 'https://']) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
  });
}
