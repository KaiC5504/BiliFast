import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const authCodePath = '/x/passport-tv-login/qrcode/auth_code';
const pollPath = '/x/passport-tv-login/qrcode/poll';
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

/// The Android HD key's signature over [sent] without its own sign, so a test sees the sign covers what was sent.
String androidSign(Map<String, String> sent) {
  final unsigned = Map.of(sent)..remove('sign')..remove('appkey')..remove('ts');
  return AppSigner.android.signed(unsigned, ts: int.parse(sent['ts']!))['sign']!;
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

  test('TV auth code posts the Android HD key\'s signed form without csrf or cookies', () async {
    final http = FakeHTTP();
    http.routes[authCodePath] = (
      200,
      '{"code":0,"message":"0","ttl":1,"data":{"url":"https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QR1","auth_code":"AUTH1"}}'
    );
    final code = await makeClient(http).tvAuthCode();
    expect(code.url, 'https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QR1');
    expect(code.authCode, 'AUTH1');
    final request = http.requestsTo(authCodePath).first;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://passport.bilibili.com$authCodePath');
    final form = formFields(http.bodyText(request));
    expect(form, {
      'local_id': '0',
      'platform': 'android',
      'mobi_app': 'android_hd',
      'appkey': 'dfca71928277209b',
      'ts': ts,
      'sign': androidSign(form),
    });
    expect(request.headers['Cookie'], isNull);
    expect(request.headers['Origin'], isNull);
    expect(request.headers['Content-Type'], 'application/x-www-form-urlencoded; charset=UTF-8');
  });

  test('TV auth code error throws', () async {
    final http = FakeHTTP();
    http.routes[authCodePath] = (200, '{"code":-400,"message":"请求错误"}');
    await expectLater(makeClient(http).tvAuthCode(), throwsA(const BiliError.api(code: -400, message: '请求错误')));
  });

  test('TV poll signs the auth code with the same key', () async {
    final http = FakeHTTP();
    http.routes[pollPath] = (200, '{"code":86039,"message":"二维码尚未确认","ttl":1,"data":null}');
    await makeClient(http).tvPoll('AUTH1');
    final request = http.requestsTo(pollPath).first;
    expect(request.url.toString(), 'https://passport.bilibili.com$pollPath');
    final form = formFields(http.bodyText(request));
    expect(form, {
      'auth_code': 'AUTH1',
      'local_id': '0',
      'appkey': 'dfca71928277209b',
      'ts': ts,
      'sign': androidSign(form),
    });
    expect(request.headers['Cookie'], isNull);
  });

  test('TV poll states', () async {
    final http = FakeHTTP();
    final client = makeClient(http);
    Future<TVLoginState> poll(String reply) {
      http.routes[pollPath] = (200, reply);
      return client.tvPoll('AUTH1');
    }

    expect(await poll('{"code":86039,"message":"二维码尚未确认","data":null}'), TVLoginState.waiting);
    expect(await poll('{"code":86090,"message":"二维码已扫码未确认","data":null}'), TVLoginState.waiting);
    expect(await poll('{"code":86038,"message":"二维码已失效","data":null}'), TVLoginState.expired);
  });

  test('TV poll other codes and a tokenless success throw', () async {
    final http = FakeHTTP();
    final client = makeClient(http);
    http.routes[pollPath] = (200, '{"code":-3,"message":"API校验密匙错误","data":null}');
    await expectLater(client.tvPoll('AUTH1'), throwsA(const BiliError.api(code: -3, message: 'API校验密匙错误')));
    for (final reply in [
      '{"code":0,"message":"0","data":null}',
      '{"code":0,"message":"0","data":{"mid":1}}',
      '{"code":0,"message":"0","data":{"access_token":"","refresh_token":"R","expires_in":1,"mid":1}}',
      '{"code":0,"message":"0","data":{"access_token":"A","refresh_token":"R","mid":1}}',
    ]) {
      http.routes[pollPath] = (200, reply);
      await expectLater(client.tvPoll('AUTH1'), throwsA(isA<BiliDecodingError>()), reason: reply);
    }
  });

  test('a cookie-less request is not retried on a risk 412', () async {
    final http = FakeHTTP()..routes = {authCodePath: (412, ''), spiPath: (200, Fixtures.spi)};
    await expectLater(makeClient(http).tvAuthCode(), throwsA(const BiliError.http(412)));
    expect(http.requestsTo(authCodePath).length, 1);
    expect(http.requestsTo(spiPath), isEmpty);
  });
}
