import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'app_signer_test.dart' show fields, makeClient;
import 'fake_http.dart';

const likePath = '/x/v2/view/like';
final token = AppToken(
  accessToken: 'ACCESS',
  refreshToken: 'REFRESH',
  mid: 7,
  expiresAt: DateTime.utc(2027, 4, 1),
);

void main() {
  group('AppToken', () {
    test('keeps its fields through JSON and prints neither token', () {
      expect(AppToken.fromJson(token.toJson()), token);
      expect('$token', isNot(contains('ACCESS')));
      expect('$token', isNot(contains('REFRESH')));
    });

    test('an issued token counts expires_in from now', () {
      final issued = AppToken.issued(
        {'access_token': 'A', 'refresh_token': 'R', 'mid': 7, 'expires_in': 86400},
        now: DateTime.utc(2026, 10, 22),
      );
      expect(issued.expiresAt, DateTime.utc(2026, 10, 23));
    });

    test('renewal is due only within its last 30 days', () {
      expect(token.dueForRenewal(DateTime.utc(2027, 3, 1)), isFalse);
      expect(token.dueForRenewal(DateTime.utc(2027, 3, 3)), isTrue);
      expect(token.expired(DateTime.utc(2027, 3, 31)), isFalse);
      expect(token.expired(DateTime.utc(2027, 4, 1)), isTrue);
    });

    test('an empty token does not decode', () {
      expect(
        () => AppToken.fromJson({'access_token': '', 'refresh_token': 'R', 'mid': 7, 'expires_at': 1}),
        throwsA(isA<DecodeError>()),
      );
    });
  });

  group('official account calls', () {
    test('without a token nothing is sent', () async {
      final http = FakeHTTP();
      await expectLater(makeClient(http).officialLike(aid: 1, on: true), throwsA(BiliError.noAppToken));
      expect(http.requestsTo(likePath), isEmpty);
    });

    test('carry the token and the signature, never the cookies or csrf', () async {
      final http = FakeHTTP();
      http.routes[likePath] = (200, '{"code":0,"message":"0","ttl":1,"data":{"toast":"点赞收到！"}}');
      final client = makeClient(http)
        ..appToken = token
        ..appBuvid = 'XYDEVICE';
      await client.officialLike(aid: 1, on: true);
      final request = http.requestsTo(likePath).single;
      expect(request.url.toString(), 'https://app.bilibili.com$likePath');
      final form = fields(request, http);
      expect(form['access_key'], 'ACCESS');
      expect(form['aid'], '1');
      expect(form['like'], '0');
      expect(form['sign'], isNotNull);
      expect(form.containsKey('csrf'), isFalse);
      expect(request.headers['Cookie'], isNull);
      expect(request.headers['buvid'], 'XYDEVICE');
    });

    test('a rejected token is reported, then the call throws', () async {
      final http = FakeHTTP();
      http.routes[likePath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
      var rejected = 0;
      final client = makeClient(http)
        ..appToken = token
        ..onAppTokenRejected = () => rejected++;
      await expectLater(client.officialLike(aid: 1, on: true), throwsA(const BiliError.api(code: -101, message: '账号未登录')));
      expect(rejected, 1);
    });

    test('any other refusal leaves the token alone', () async {
      final http = FakeHTTP();
      http.routes[likePath] = (200, '{"code":65006,"message":"已赞过","ttl":1}');
      var rejected = 0;
      final client = makeClient(http)
        ..appToken = token
        ..onAppTokenRejected = () => rejected++;
      await expectLater(client.officialLike(aid: 1, on: true), throwsA(isA<BiliAPIError>()));
      expect(rejected, 0);
    });
  });
}
