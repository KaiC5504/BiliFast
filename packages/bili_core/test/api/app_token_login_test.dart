import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'app_signer_test.dart' show androidSign, makeClient, pollPath;
import 'fake_http.dart';

const renewPath = '/x/passport-login/oauth2/refresh_token';

// Every value is made up.
final held = AppToken(accessToken: 'OLD-ACCESS', refreshToken: 'OLD-REFRESH', mid: 7, expiresAt: DateTime.utc(2024, 1));

void main() {
  group('poll', () {
    Future<TVLoginState> poll(String data) {
      final http = FakeHTTP();
      http.routes[pollPath] = (200, '{"code":0,"message":"0","ttl":1,"data":$data}');
      return makeClient(http).tvPoll('AUTH1');
    }

    final expected = TVLoginState.confirmed(
      AppToken(
        accessToken: 'ACCESS',
        refreshToken: 'REFRESH',
        mid: 12345,
        expiresAt: testNow.add(const Duration(seconds: 15552000)),
      ),
    );

    test('a flat answer gives the token, its expiry counted from now', () async {
      expect(
        await poll('{"mid":12345,"access_token":"ACCESS","refresh_token":"REFRESH","expires_in":15552000}'),
        expected,
      );
    });

    test('an answer under token_info gives the same, and cookie_info is ignored', () async {
      expect(
        await poll(
          '{"is_new":false,"token_info":{"mid":12345,"access_token":"ACCESS","refresh_token":"REFRESH",'
          '"expires_in":15552000},"cookie_info":{"cookies":[{"name":"SESSDATA","value":"OTHER"}]},"sso":[]}',
        ),
        expected,
      );
    });

    test('both shapes at once read the flat one', () async {
      expect(
        await poll(
          '{"mid":12345,"access_token":"ACCESS","refresh_token":"REFRESH","expires_in":15552000,'
          '"token_info":{"mid":12345,"access_token":"ACCESS","refresh_token":"REFRESH","expires_in":15552000},'
          '"cookie_info":{"cookies":[]}}',
        ),
        expected,
      );
    });

    test('the confirmed state prints neither token', () async {
      final state = await poll('{"mid":12345,"access_token":"ACCESS","refresh_token":"REFRESH","expires_in":1}');
      expect('$state', isNot(contains('ACCESS')));
      expect('$state', isNot(contains('REFRESH')));
    });
  });

  group('renewal', () {
    test('sends the refresh token and the held token, signed, without cookies', () async {
      final http = FakeHTTP();
      http.routes[renewPath] = (
        200,
        '{"code":0,"message":"0","ttl":1,"data":{"status":0,"token_info":{"mid":7,"access_token":"NEW-ACCESS",'
            '"refresh_token":"NEW-REFRESH","expires_in":15552000},"cookie_info":{"cookies":[]}}}',
      );
      final client = makeClient(http)..appToken = held;
      final renewed = await client.renewAppToken();
      expect(
        renewed,
        AppToken(
          accessToken: 'NEW-ACCESS',
          refreshToken: 'NEW-REFRESH',
          mid: 7,
          expiresAt: testNow.add(const Duration(seconds: 15552000)),
        ),
      );
      final request = http.requestsTo(renewPath).single;
      expect(request.url.toString(), 'https://passport.bilibili.com$renewPath');
      final form = formFields(http.bodyText(request));
      expect(form['refresh_token'], 'OLD-REFRESH');
      expect(form['access_key'], 'OLD-ACCESS');
      expect(form['appkey'], 'dfca71928277209b');
      expect(form['sign'], androidSign(form));
      expect(form.containsKey('csrf'), isFalse);
      expect(request.headers['Cookie'], isNull);
    });

    test('an answer without mid keeps the account\'s', () async {
      final http = FakeHTTP();
      http.routes[renewPath] = (
        200,
        '{"code":0,"message":"0","data":{"token_info":{"access_token":"A","refresh_token":"R","expires_in":60}}}',
      );
      final client = makeClient(http)..appToken = held;
      expect((await client.renewAppToken()).mid, 7);
    });

    test('a rejected token is reported and the renewal throws', () async {
      final http = FakeHTTP();
      http.routes[renewPath] = (200, '{"code":-101,"message":"账号未登录"}');
      final rejected = <String>[];
      final client = makeClient(http)
        ..appToken = held
        ..onAppTokenRejected = rejected.add;
      await expectLater(client.renewAppToken(), throwsA(const BiliError.api(code: -101, message: '账号未登录')));
      expect(rejected, ['OLD-ACCESS']);
    });

    test('without a token nothing is sent', () async {
      final http = FakeHTTP();
      await expectLater(makeClient(http).renewAppToken(), throwsA(BiliError.noAppToken));
      expect(http.requests, isEmpty);
    });
  });
}
