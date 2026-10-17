import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const authCodePath = '/x/passport-tv-login/qrcode/auth_code';
const pollPath = '/x/passport-tv-login/qrcode/poll';
const dislikePath = '/x/v2/view/dislike';
const spiPath = '/x/frontend/finger/spi';
const signer = AppSigner(appKey: 'testkey', appSecret: 'testsecret');
// The clock makeTestClient fixes.
const ts = '1702204169';

BiliClient makeClient(FakeHTTP http) =>
    makeTestClient(http, cookies: {'SESSDATA': 'sess', 'bili_jct': 'TOKEN', 'buvid3': 'b3'});

/// The raw (still percent-encoded) form fields.
Map<String, String> fields(HTTPRequest request, FakeHTTP http) {
  final result = <String, String>{};
  for (final pair in http.bodyText(request).split('&')) {
    final equals = pair.indexOf('=');
    result.putIfAbsent(equals < 0 ? pair : pair.substring(0, equals), () => equals < 0 ? '' : pair.substring(equals + 1));
  }
  return result;
}

void main() {
  test('signer matches the documented algorithm', () {
    final signed = const AppSigner(appKey: 'testkey', appSecret: 'testsecret').signed({'b': '你好', 'a': '1'}, ts: 100);
    // md5("a=1&appkey=testkey&b=%E4%BD%A0%E5%A5%BD&ts=100" + "testsecret")
    expect(signed['sign'], 'a650ecac0ce853a58e81f3366d428dbb');
    expect(signed['appkey'], 'testkey');
    expect(signed['ts'], '100');
  });

  test("signer keeps the caller's fields and is deterministic", () {
    final signed = signer.signed({'aid': '1'}, ts: 5);
    expect(signed['aid'], '1');
    expect(signed.keys.toSet(), {'aid', 'appkey', 'ts', 'sign'});
    expect(signer.signed({'aid': '1'}, ts: 5), signed);
    expect(signer.signed({'aid': '1'}, ts: 6)['sign'], isNot(signed['sign']));
  });

  test('TV auth code posts a signed form without csrf or cookies', () async {
    final http = FakeHTTP();
    http.routes[authCodePath] = (
      200,
      '{"code":0,"message":"0","ttl":1,"data":{"url":"https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QR1","auth_code":"AUTH1"}}'
    );
    final code = await makeClient(http).tvAuthCode(signer: signer);
    expect(code.url, 'https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QR1');
    expect(code.authCode, 'AUTH1');
    final request = http.requestsTo(authCodePath).first;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://passport.bilibili.com$authCodePath');
    expect(http.bodyText(request), 'appkey=testkey&local_id=0&sign=0e70305826df54da099eb970792b17cd&ts=$ts');
    expect(request.headers['Cookie'], isNull);
    expect(request.headers['Content-Type'], 'application/x-www-form-urlencoded; charset=UTF-8');
  });

  test('TV auth code error throws', () async {
    final http = FakeHTTP();
    http.routes[authCodePath] = (200, '{"code":-400,"message":"请求错误"}');
    await expectLater(
        makeClient(http).tvAuthCode(signer: signer), throwsA(const BiliError.api(code: -400, message: '请求错误')));
  });

  test('TV poll signs the auth code', () async {
    final http = FakeHTTP();
    http.routes[pollPath] = (200, '{"code":86039,"message":"二维码尚未确认","ttl":1,"data":null}');
    await makeClient(http).tvPoll(signer: signer, authCode: 'AUTH1');
    final request = http.requestsTo(pollPath).first;
    expect(request.url.toString(), 'https://passport.bilibili.com$pollPath');
    expect(http.bodyText(request),
        'appkey=testkey&auth_code=AUTH1&local_id=0&sign=7f3e83052d4dd9bf44e1a52cde734a9c&ts=$ts');
    expect(request.headers['Cookie'], isNull);
  });

  test('TV poll states', () async {
    final http = FakeHTTP();
    final client = makeClient(http);
    Future<TVLoginState> poll(String reply) {
      http.routes[pollPath] = (200, reply);
      return client.tvPoll(signer: signer, authCode: 'AUTH1');
    }

    expect(await poll('{"code":86039,"message":"二维码尚未确认","data":null}'), TVLoginState.waiting);
    expect(await poll('{"code":86090,"message":"二维码已扫码未确认","data":null}'), TVLoginState.waiting);
    expect(await poll('{"code":86038,"message":"二维码已失效","data":null}'), TVLoginState.expired);
    final confirmed = await poll('{"code":0,"message":"0","ttl":1,"data":{"mid":12345,"access_token":"ACCESS-TOKEN",'
        '"refresh_token":"REFRESH","expires_in":15551999,"cookie_info":{"cookies":[]},"sso":[]}}');
    expect(confirmed, const TVLoginState.confirmed(accessToken: 'ACCESS-TOKEN', mid: 12345));
  });

  test('TV poll other codes and a tokenless success throw', () async {
    final http = FakeHTTP();
    final client = makeClient(http);
    http.routes[pollPath] = (200, '{"code":-3,"message":"API校验密匙错误","data":null}');
    await expectLater(client.tvPoll(signer: signer, authCode: 'AUTH1'),
        throwsA(const BiliError.api(code: -3, message: 'API校验密匙错误')));
    for (final reply in [
      '{"code":0,"message":"0","data":null}',
      '{"code":0,"message":"0","data":{"mid":1}}',
      '{"code":0,"message":"0","data":{"access_token":"","mid":1}}',
    ]) {
      http.routes[pollPath] = (200, reply);
      await expectLater(client.tvPoll(signer: signer, authCode: 'AUTH1'), throwsA(isA<BiliDecodingError>()),
          reason: reply);
    }
  });

  test('dislike sends no cookies and no csrf', () async {
    final http = FakeHTTP();
    http.routes[dislikePath] = (200, '{"code":0,"message":"0","ttl":1,"data":null}');
    final client = makeClient(http);
    await client.dislike(aid: 80433022, on: true, accessToken: 'tok/en', signer: signer);
    final request = http.requestsTo(dislikePath).first;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://app.bilibili.com$dislikePath');
    expect(request.headers['Cookie'], isNull);
    expect(request.headers['Origin'], isNull);
    final body = http.bodyText(request);
    expect(body,
        'access_key=tok%2Fen&aid=80433022&appkey=testkey&dislike=0&sign=a31c3355ac92c79564a32c276628db02&ts=$ts');
    expect(body.contains('csrf'), isFalse);
    expect(body.contains('TOKEN'), isFalse);

    await client.dislike(aid: 80433022, on: false, accessToken: 'tok/en', signer: signer);
    final undo = http.requestsTo(dislikePath).last;
    expect(fields(undo, http)['dislike'], '1');
    expect(fields(undo, http)['sign'], '4dbe03ff280d7bd7726a96a72092f02f');
  });

  test('dislike failures throw', () async {
    final http = FakeHTTP();
    final client = makeClient(http);
    http.routes[dislikePath] = (200, '{"code":-101,"message":"账号未登录"}');
    await expectLater(client.dislike(aid: 1, on: true, accessToken: 't', signer: signer),
        throwsA(const BiliError.api(code: -101, message: '账号未登录')));
    http.routes[dislikePath] = (200, '<html>nope</html>');
    await expectLater(
        client.dislike(aid: 1, on: true, accessToken: 't', signer: signer), throwsA(isA<BiliDecodingError>()));
  });

  test('a cookie-less request is not retried on a risk 412', () async {
    final http = FakeHTTP()..routes = {dislikePath: (412, ''), spiPath: (200, Fixtures.spi)};
    await expectLater(makeClient(http).dislike(aid: 1, on: true, accessToken: 't', signer: signer),
        throwsA(const BiliError.http(412)));
    expect(http.requestsTo(dislikePath).length, 1);
    expect(http.requestsTo(spiPath), isEmpty);
  });
}
