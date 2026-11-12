import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'app_signer_test.dart' show iphoneKey, pollPath, signedBy;
import 'app_token_login_test.dart' show renewAnswer, renewPath;
import 'fake_http.dart';
import 'official_api_test.dart' show likePath;
import 'own_space_fixtures.dart';
import 'skin_test.dart' show skinPath;
import 'space_api_test.dart' show androidKey, androidParams, androidUserAgent, spacePath;

const iphoneParams = {
  'actionKey': 'appkey',
  'build': '91800100',
  'c_locale': 'zh-Hans_CN',
  'device': 'phone',
  'disable_rcmd': '0',
  'mobi_app': 'iphone',
  'platform': 'ios',
  's_locale': 'zh-Hans_CN',
  'statistics': '{"appId":1,"version":"9.18.0","abtest":"","platform":1}',
};
const iphoneUserAgent =
    'bili-universal/91800100 CFNetwork/1.0 Darwin/27.2.0 os/ios model/iPhone 17 Pro Max mobi_app/iphone '
    'build/91800100 osVer/27.2 network/2 channel/pink_overseas';

const likeAnswer = '{"code":0,"message":"0","ttl":1}';

// Every value is made up.
AppToken tokenOf(OfficialIdentity identity) => AppToken(
  accessToken: 'MADE-UP-ACCESS',
  refreshToken: 'MADE-UP-REFRESH',
  mid: 7,
  expiresAt: DateTime.utc(2027, 4, 1),
  identity: identity,
);

void main() {
  late FakeHTTP http;
  late MemorySink sink;

  setUp(() {
    http = FakeHTTP();
    sink = MemorySink();
    http.routes[likePath] = (200, likeAnswer);
    http.routes[spacePath] = (200, OwnSpaceFixtures.space);
    http.routes[skinPath] = (200, OwnSpaceFixtures.skin);
    http.routes[renewPath] = (200, renewAnswer);
  });

  /// A client whose new logins are [login]'s, holding a token of [token] if one is named.
  BiliClient makeClient({OfficialIdentity login = OfficialIdentity.android, OfficialIdentity? token}) {
    final client =
        BiliClient(
            transport: http,
            cookies: CookieJar({'SESSDATA': 'MADE-UP-SESSION', 'bili_jct': 'MADE-UP-CSRF', 'buvid3': 'b3'}),
            now: () => testNow,
            logger: Logger(session: 'test')..add(sink),
          )
          ..loginIdentity = login
          ..appBuvid = 'DEVICE';
    if (token != null) client.appToken = tokenOf(token);
    return client;
  }

  /// A GET's query or a POST's form, percent-decoded.
  Map<String, String> sent(HTTPRequest request) =>
      request.method == 'GET' ? http.query(request) : formFields(http.bodyText(request));

  Map<String, String> unsigned(HTTPRequest request) =>
      sent(request)..removeWhere((key, _) => key == 'appkey' || key == 'ts' || key == 'sign');

  /// One of each kind, in this order: a write, a read, the skin's own envelope, the renewal, and a call without the
  /// account.
  Future<void> callEach(BiliClient client) async {
    await client.officialLike(aid: 1, on: true);
    await client.ownSpace(mid: 7);
    await client.skin();
    await client.renewAppToken();
    await client.space(mid: 8);
  }

  test("an Android token's calls stay the Android app's where new logins are the iPhone app's", () async {
    await callEach(makeClient(login: OfficialIdentity.iphone, token: OfficialIdentity.android));
    expect(http.requests, hasLength(5));
    for (final request in http.requests) {
      final fields = sent(request);
      final path = request.url.path;
      expect(fields['appkey'], androidKey, reason: path);
      expect(fields['sign'], signedBy(AppSigner.android, fields), reason: path);
      expect(request.headers['User-Agent'], androidUserAgent, reason: path);
      expect(request.headers['bili-http-engine'], 'cronet', reason: path);
      expect(request.headers['buvid'], 'DEVICE', reason: path);
      for (final name in ['app-key', 'env', 'session_id', 'Cookie']) {
        expect(request.headers.containsKey(name), isFalse, reason: '$path $name');
      }
    }
    final [like, own, skin, renew, guest] = http.requests;
    expect(unsigned(like), {...androidParams, 'aid': '1', 'like': '0', 'access_key': 'MADE-UP-ACCESS'});
    expect(unsigned(own), {...androidParams, 'vmid': '7', 'access_key': 'MADE-UP-ACCESS'});
    expect(unsigned(skin), {...androidParams, 'is_free_theme': '0', 'access_key': 'MADE-UP-ACCESS'});
    expect(unsigned(renew), {...androidParams, 'refresh_token': 'MADE-UP-REFRESH', 'access_key': 'MADE-UP-ACCESS'});
    expect(unsigned(guest), {...androidParams, 'vmid': '8'}, reason: "the held token's identity, without the token");
  });

  test("an iPhone token's calls carry the iPhone app's key, labels and headers, signed with its pair", () async {
    final client = makeClient(token: OfficialIdentity.iphone);
    expect(client.loginIdentity, OfficialIdentity.android);
    await callEach(client);
    expect(http.requests, hasLength(5));
    expect(client.appSessionId, matches(RegExp(r'^[0-9a-f]{8}$')));
    for (final request in http.requests) {
      final fields = sent(request);
      final path = request.url.path;
      expect(fields['appkey'], iphoneKey, reason: path);
      expect(fields['sign'], signedBy(AppSigner.iphone, fields), reason: path);
      expect(fields['sign'], isNot(signedBy(AppSigner.android, fields)), reason: path);
      expect(request.headers['User-Agent'], iphoneUserAgent, reason: path);
      expect(request.headers['app-key'], 'iphone', reason: path);
      expect(request.headers['env'], 'prod', reason: path);
      expect(request.headers['buvid'], 'DEVICE', reason: path);
      expect(request.headers['session_id'], client.appSessionId, reason: path);
      for (final name in ['bili-http-engine', 'Cookie']) {
        expect(request.headers.containsKey(name), isFalse, reason: '$path $name');
      }
    }
    final [like, own, skin, renew, guest] = http.requests;
    expect(unsigned(like), {...iphoneParams, 'aid': '1', 'like': '0', 'access_key': 'MADE-UP-ACCESS'});
    expect(unsigned(own), {...iphoneParams, 'vmid': '7', 'access_key': 'MADE-UP-ACCESS'});
    expect(unsigned(skin), {...iphoneParams, 'is_free_theme': '0', 'access_key': 'MADE-UP-ACCESS'});
    expect(unsigned(renew), {...iphoneParams, 'refresh_token': 'MADE-UP-REFRESH', 'access_key': 'MADE-UP-ACCESS'});
    expect(unsigned(guest), {...iphoneParams, 'vmid': '8'}, reason: "the held token's identity, without the token");
  });

  test('with no token held, a call without the account goes out as the identity new logins are made under', () async {
    await makeClient().space(mid: 8);
    await makeClient(login: OfficialIdentity.iphone).space(mid: 8);
    final [android, iphone] = http.requestsTo(spacePath);
    expect(unsigned(android), {...androidParams, 'vmid': '8'});
    expect(sent(android)['appkey'], androidKey);
    expect(sent(android)['sign'], signedBy(AppSigner.android, sent(android)));
    expect(android.headers['User-Agent'], androidUserAgent);
    expect(android.headers.containsKey('app-key'), isFalse);

    expect(unsigned(iphone), {...iphoneParams, 'vmid': '8'});
    expect(sent(iphone)['appkey'], iphoneKey);
    expect(sent(iphone)['sign'], signedBy(AppSigner.iphone, sent(iphone)));
    expect(iphone.headers['User-Agent'], iphoneUserAgent);
    expect(iphone.headers['app-key'], 'iphone');
  });

  test('without a device id no buvid is sent, under either identity', () async {
    for (final identity in OfficialIdentity.values) {
      final client = makeClient(token: identity)..appBuvid = null;
      await client.officialLike(aid: 1, on: true);
      expect(http.requests.last.headers.containsKey('buvid'), isFalse, reason: identity.name);
    }
  });

  test('no log line names a token, a signature or a signed field, under either identity', () async {
    const issued = '"mid":7,"access_token":"NEW-ACCESS","refresh_token":"NEW-REFRESH"';
    for (final identity in OfficialIdentity.values) {
      final client = makeClient(login: identity, token: identity);
      await callEach(client);
      http.routes[pollPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{$issued,"expires_in":60}}');
      expect(await client.tvPoll('MADE-UP-CODE'), isA<TVLoginConfirmed>());
      http.routes[pollPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{$issued}}');
      await expectLater(client.tvPoll('MADE-UP-CODE'), throwsA(isA<BiliDecodingError>()));
      http.routes[likePath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
      await expectLater(client.officialLike(aid: 1, on: true), throwsA(isA<BiliAPIError>()));
      http.routes[likePath] = (200, likeAnswer);
    }
    final log = sink.events.map((event) => event.encode()).join('\n');
    expect(sink.events.where((event) => event.msg == 'app token rejected'), hasLength(2));
    expect(sink.events.where((event) => event.msg == '$pollPath decode failed'), hasLength(2));
    expect(sink.events.map((event) => event.msg), containsAll([likePath, spacePath, skinPath, renewPath, pollPath]));
    for (final leak in ['MADE-UP', 'NEW-', 'access_key', 'appkey', 'sign', androidKey, iphoneKey, '?']) {
      expect(log, isNot(contains(leak)), reason: leak);
    }
  });
}
