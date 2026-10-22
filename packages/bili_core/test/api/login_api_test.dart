import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

final class _Events implements LogSink {
  final List<LogEvent> events = [];

  @override
  void receive(LogEvent event) => events.add(event);

  String get text => events.map((event) => event.encode()).join('\n');
}

const generatePath = '/x/passport-login/web/qrcode/generate';
const pollPath = '/x/passport-login/web/qrcode/poll';
const logoutPath = '/login/exit/v2';

// Made up, in the shapes the website's login answers with.
const generated =
    '{"code":0,"message":"0","ttl":1,"data":{"url":"https://account.bilibili.com/h5/account-h5/auth/scan-web?navhide=1&callback=close&qrcode_key=KEY1&from=","qrcode_key":"KEY1"}}';

String poll(int code, {String message = '', String url = ''}) =>
    '{"code":0,"message":"0","ttl":1,"data":{"url":"$url","refresh_token":"${url.isEmpty ? '' : 'REFRESH'}",'
    '"timestamp":1702204169000,"code":$code,"message":"$message"}}';

const crossDomain =
    'https://passport.biligame.com/x/passport-login/web/crossDomain?DedeUserID=12345&DedeUserID__ckMd5=abcdef0123456789'
    '&Expires=1717756169&SESSDATA=1a2b3c4d%2C1717756169%2C5e6f7%2A81&bili_jct=0123456789abcdef0123456789abcdef'
    '&gourl=https%3A%2F%2Fwww.bilibili.com%2F';

void main() {
  test('generate is a GET to the passport and reads the url and key', () async {
    final http = FakeHTTP()..routes[generatePath] = (200, generated);
    final qr = await makeTestClient(http).webLoginQr();
    expect(qr.url, contains('qrcode_key=KEY1'));
    expect(qr.key, 'KEY1');
    final request = http.requestsTo(generatePath).single;
    expect(request.method, 'GET');
    expect(request.url.toString(), 'https://passport.bilibili.com$generatePath');
    expect(request.body, isNull);
  });

  test('generate without a key or with an error throws', () async {
    final http = FakeHTTP();
    final client = makeTestClient(http);
    http.routes[generatePath] = (200, '{"code":0,"message":"0","data":{"url":"https://x","qrcode_key":""}}');
    await expectLater(client.webLoginQr(), throwsA(isA<BiliDecodingError>()));
    http.routes[generatePath] = (200, '{"code":-412,"message":"请求被拦截"}');
    await expectLater(client.webLoginQr(), throwsA(const BiliError.api(code: -412, message: '请求被拦截')));
  });

  test('poll asks about the key with a GET to the passport', () async {
    final http = FakeHTTP()..routes[pollPath] = (200, poll(86101, message: '未扫码'));
    await makeTestClient(http).webLoginPoll('KEY1');
    final request = http.requestsTo(pollPath).single;
    expect(request.method, 'GET');
    expect(request.url.host, 'passport.bilibili.com');
    expect(http.query(request), {'qrcode_key': 'KEY1'});
  });

  test('poll states', () async {
    final http = FakeHTTP();
    final client = makeTestClient(http);
    Future<WebLoginPoll> answer(String reply) {
      http.routes[pollPath] = (200, reply);
      return client.webLoginPoll('KEY1');
    }

    expect(await answer(poll(86101, message: '未扫码')), const WebLoginWaiting(scanned: false));
    expect(await answer(poll(86090, message: '二维码已扫码未确认')), const WebLoginWaiting(scanned: true));
    expect(await answer(poll(86038, message: '二维码已失效')), const WebLoginExpired());
  });

  test('a login keeps only the session cookies, decoded and escaped as Bilibili sets them', () async {
    final http = FakeHTTP()..routes[pollPath] = (200, poll(0, url: crossDomain));
    final done = await makeTestClient(http).webLoginPoll('KEY1');
    expect(done, isA<WebLoginDone>());
    expect((done as WebLoginDone).cookies, {
      'DedeUserID': '12345',
      'DedeUserID__ckMd5': 'abcdef0123456789',
      'SESSDATA': '1a2b3c4d%2C1717756169%2C5e6f7%2A81',
      'bili_jct': '0123456789abcdef0123456789abcdef',
    });
    expect('$done', isNot(contains('1a2b3c4d')), reason: 'the session never prints');
  });

  test('cookie values are percent-decoded: plain characters come back plain, the rest in one form', () async {
    final http = FakeHTTP()
      ..routes[pollPath] = (
        200,
        poll(0, url: 'https://passport.biligame.com/x?SESSDATA=a%2cb,c*d&bili_jct=%61%62&DedeUserID=%31&sid=s1#top'),
      );
    final done = await makeTestClient(http).webLoginPoll('KEY1') as WebLoginDone;
    expect(done.cookies, {'SESSDATA': 'a%2Cb%2Cc%2Ad', 'bili_jct': 'ab', 'DedeUserID': '1', 'sid': 's1'});
  });

  test("a login takes the session from the Set-Cookie headers package:http joined with commas", () async {
    // As the phone's login answered on 2026-10-22: the session only in the headers, the url without it.
    final http = FakeHTTP()
      ..routes[pollPath] = (200, poll(0, url: 'https://www.bilibili.com/'))
      ..routeHeaders[pollPath] = {
        'set-cookie':
            'SESSDATA=1a2b3c4d%2C1792648400%2Cab12c%2A21; Path=/; Domain=bilibili.com; '
            'Expires=Tue, 20 Apr 2027 04:00:00 GMT; HttpOnly; Secure,'
            'bili_jct=0123456789abcdef; Path=/; Domain=bilibili.com; Expires=Tue, 20 Apr 2027 04:00:00 GMT,'
            'DedeUserID=12345; Path=/; Domain=bilibili.com,'
            'DedeUserID__ckMd5=abcdef0123456789; Path=/; Domain=bilibili.com,'
            'sid=s1; Path=/; Domain=bilibili.com,'
            'other=x; Path=/',
      };
    final done = await makeTestClient(http).webLoginPoll('KEY1') as WebLoginDone;
    expect(done.cookies, {
      'SESSDATA': '1a2b3c4d%2C1792648400%2Cab12c%2A21',
      'bili_jct': '0123456789abcdef',
      'DedeUserID': '12345',
      'DedeUserID__ckMd5': 'abcdef0123456789',
      'sid': 's1',
    });
  });

  test("a login with no session anywhere names what the answer held, never a value", () async {
    final http = FakeHTTP()
      ..routes[pollPath] = (200, poll(0, url: 'https://www.bilibili.com/?gourl=SECRETGO'))
      ..routeHeaders[pollPath] = {'set-cookie': 'buvid=SECRETBUVID; Path=/'};
    final thrown = await makeTestClient(http).webLoginPoll('KEY1').then<Object?>((_) => null, onError: (Object e) => e);
    expect('$thrown', contains('headers: buvid; url names: gourl'));
    expect('$thrown', isNot(contains('SECRET')));
  });

  test('a login without SESSDATA or bili_jct throws without quoting the answer', () async {
    final http = FakeHTTP();
    final client = makeTestClient(http);
    for (final url in [
      '',
      'https://passport.biligame.com/x/passport-login/web/crossDomain?DedeUserID=1&bili_jct=SECRETJCT',
      'https://passport.biligame.com/x/passport-login/web/crossDomain?SESSDATA=SECRETSESS&DedeUserID=1',
      'https://passport.biligame.com/x/passport-login/web/crossDomain?SESSDATA=&bili_jct=SECRETJCT',
      'https://passport.biligame.com/x/passport-login/web/crossDomain?SESSDATA=%E0%A4%A&bili_jct=SECRETJCT',
    ]) {
      http.routes[pollPath] = (200, poll(0, url: url));
      Object? thrown;
      try {
        await client.webLoginPoll('KEY1');
      } catch (error) {
        thrown = error;
      }
      expect(thrown, isA<BiliDecodingError>(), reason: url);
      expect('$thrown', isNot(contains('SECRET')), reason: url);
    }
  });

  test('the log never carries the key, the link or a cookie', () async {
    final log = _Events();
    final http = FakeHTTP()
      ..routes[generatePath] = (200, generated)
      ..routes[pollPath] = (200, poll(0, url: crossDomain));
    final client = BiliClient(
      transport: http,
      cookies: CookieJar(),
      now: () => testNow,
      logger: Logger(session: 'test')..add(log),
    );
    await client.webLoginQr();
    await client.webLoginPoll('KEY1');
    http.routes[pollPath] = (200, '{"code":0,"data":{"code":0,"url":"https://x?SESSDATA=1a2b3c4d"}');
    await expectLater(client.webLoginPoll('KEY1'), throwsA(isA<BiliDecodingError>()));
    expect(log.events, isNotEmpty);
    for (final secret in ['KEY1', '1a2b3c4d', '0123456789abcdef', 'REFRESH', 'crossDomain']) {
      expect(log.text, isNot(contains(secret)), reason: secret);
    }
  });

  test('an unknown state throws its code and message', () async {
    final http = FakeHTTP()..routes[pollPath] = (200, poll(86039, message: '其他'));
    await expectLater(
      makeTestClient(http).webLoginPoll('KEY1'),
      throwsA(const BiliError.api(code: 86039, message: '其他')),
    );
  });

  test('an envelope error throws its code', () async {
    final http = FakeHTTP()..routes[pollPath] = (200, '{"code":-400,"message":"请求错误"}');
    await expectLater(
      makeTestClient(http).webLoginPoll('KEY1'),
      throwsA(const BiliError.api(code: -400, message: '请求错误')),
    );
  });

  test('logout posts biliCSRF to the passport\'s /login/exit/v2', () async {
    final http = FakeHTTP()
      ..routes['POST $logoutPath'] = (
        200,
        '{"code":0,"status":true,"ts":1702204169,"data":{"redirectUrl":"https://www.bilibili.com/"}}',
      );
    await makeTestClient(http, cookies: {'SESSDATA': 'sess', 'bili_jct': 'JCT'}).webLogout();
    final request = http.requestsTo(logoutPath).single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://passport.bilibili.com$logoutPath');
    expect(formFields(http.bodyText(request)), {'biliCSRF': 'JCT', 'csrf': 'JCT'});
    expect(request.headers['Referer'], 'https://www.bilibili.com/');
    expect(request.headers['Cookie'], contains('SESSDATA=sess'));
  });

  test('a refused logout throws, and none is sent without bili_jct', () async {
    final http = FakeHTTP()..routes['POST $logoutPath'] = (200, '{"code":2202,"status":false,"message":"csrf 请求非法"}');
    await expectLater(
      makeTestClient(http, cookies: {'SESSDATA': 'sess', 'bili_jct': 'JCT'}).webLogout(),
      throwsA(const BiliError.api(code: 2202, message: 'csrf 请求非法')),
    );
    await expectLater(
      makeTestClient(http, cookies: {'SESSDATA': 'sess'}).webLogout(),
      throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -101)),
    );
    expect(http.requestsTo(logoutPath), hasLength(1));
  });
}
