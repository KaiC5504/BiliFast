import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/video/page_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';

const _webLike = '/x/web-interface/archive/like';
const _webCoin = '/x/web-interface/coin/add';
const _officialLike = '/x/v2/view/like';
const _officialCoin = '/x/v2/view/coin/add';
const _officialDislike = '/x/v2/view/dislike';
const _ok = '{"code":0,"message":"0","ttl":1}';

/// Made up; never a real token.
final _token = AppToken(accessToken: 'TESTACCESS', refreshToken: 'TESTREFRESH', mid: 7, expiresAt: DateTime.utc(2027));

void main() {
  late CannedHttp http;
  late BiliClient client;
  late ClientPageApi api;

  setUp(() {
    http = CannedHttp();
    for (final path in [_webLike, _webCoin, _officialLike, _officialCoin, _officialDislike]) {
      http.routes[path] = (200, _ok);
    }
    client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: Logger(session: 'test'));
    api = ClientPageApi(client);
  });

  Map<String, String> form(HTTPRequest request) => Uri.splitQueryString(utf8.decode(request.body!));

  group('without the app token', () {
    test('点赞 and 投币 go to the web with the cookies, as before', () async {
      await api.like(aid: 3, bvid: 'BV1test00001', on: true);
      await api.coin(aid: 3, bvid: 'BV1test00001', multiply: 2, alsoLike: true);
      expect(http.paths, [_webLike, _webCoin]);
      for (final request in http.requests) {
        expect(request.url.host, 'api.bilibili.com');
        expect(request.headers['Cookie'], isNotNull);
      }
      expect(form(http.to(_webLike).single)['like'], '1');
      expect(form(http.to(_webCoin).single), allOf(containsPair('multiply', '2'), containsPair('select_like', '1')));
    });

    test('不喜欢 sends nothing and says there is no token', () async {
      await expectLater(api.dislike(aid: 3, on: true), throwsA(BiliError.noAppToken));
      expect(http.requests, isEmpty);
    });
  });

  group('with the app token', () {
    setUp(() => client.appToken = _token);

    test('点赞, 投币 and 不喜欢 go to the official app\'s calls with the token, never the cookies', () async {
      await api.like(aid: 3, bvid: 'BV1test00001', on: true);
      await api.coin(aid: 3, bvid: 'BV1test00001', multiply: 1, alsoLike: false);
      await api.dislike(aid: 3, on: true);
      expect(http.paths, [_officialLike, _officialCoin, _officialDislike]);
      for (final request in http.requests) {
        expect(request.url.host, 'app.bilibili.com');
        expect(request.headers['Cookie'], isNull);
        expect(form(request)['access_key'], 'TESTACCESS');
        expect(form(request)['aid'], '3');
      }
      expect(form(http.to(_officialCoin).single), allOf(containsPair('multiply', '1'), containsPair('select_like', '0')));
      expect(form(http.to(_officialDislike).single)['dislike'], '0');
    });

    test('三连 stays on the web, as in PiliPlus', () async {
      http.routes['/x/web-interface/archive/like/triple'] =
          (200, '{"code":0,"message":"0","ttl":1,"data":{"like":true,"coin":true,"fav":true,"multiply":2}}');
      await api.triple(aid: 3, bvid: 'BV1test00001');
      expect(http.requests.single.url.host, 'api.bilibili.com');
    });

    test('a token Bilibili turns down is reported, and the 点赞 or 投币 goes out once on the web instead', () async {
      var rejected = 0;
      client.onAppTokenRejected = () => rejected += 1;
      http.routes[_officialLike] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
      http.routes[_officialCoin] = (200, '{"code":-2,"message":"Access Key错误","ttl":1}');
      await api.like(aid: 3, bvid: 'BV1test00001', on: true);
      await api.coin(aid: 3, bvid: 'BV1test00001', multiply: 1, alsoLike: false);
      expect(http.paths, [_officialLike, _webLike, _officialCoin, _webCoin]);
      expect(rejected, 2);
    });

    test('any other refusal is the answer: nothing goes to the web', () async {
      http.routes[_officialLike] = (200, '{"code":65006,"message":"已赞过","ttl":1}');
      await expectLater(
        api.like(aid: 3, bvid: 'BV1test00001', on: true),
        throwsA(const BiliError.api(code: 65006, message: '已赞过')),
      );
      expect(http.paths, [_officialLike]);
    });
  });
}
