import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/src/api/form_encoding.dart';
import 'package:bili_core/src/api/json.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const togglePath = '/x/v2/history/toview/add';
const spiPath = '/x/frontend/finger/spi';
const okEmpty = '{"code":0,"message":"0","data":null}';

int decodeN(Object? json) => JsonObject.from(json).required(JsonObject.from(json).integer('n'), 'n');

void main() {
  test('post sends a form with csrf and browser headers', () async {
    final http = FakeHTTP();
    http.routes[togglePath] = (200, okEmpty);
    final client = makeTestClient(http, cookies: {'bili_jct': 'TOKEN', 'SESSDATA': 's'});
    await client.postVoid(togglePath, form: {'aid': '1'}, referer: 'https://www.bilibili.com/video/BV1');
    final request = http.requestsTo(togglePath).first;
    expect(request.method, 'POST');
    expect(http.bodyText(request), 'aid=1&csrf=TOKEN');
    expect(request.headers['Origin'], 'https://www.bilibili.com');
    expect(request.headers['Referer'], 'https://www.bilibili.com/video/BV1');
    expect(request.headers['Content-Type'], 'application/x-www-form-urlencoded; charset=UTF-8');
    expect(request.headers['User-Agent'], BiliClient.userAgent);
    expect(request.headers['Cookie'], 'SESSDATA=s; bili_jct=TOKEN');
    expect(request.url.toString(), 'https://api.bilibili.com$togglePath');
  });

  test('post referer defaults to the site root', () async {
    final http = FakeHTTP();
    http.routes[togglePath] = (200, okEmpty);
    await makeTestClient(http, cookies: {'bili_jct': 'T'}).postVoid(togglePath);
    expect(http.requestsTo(togglePath).first.headers['Referer'], BiliClient.referer);
  });

  test('post overrides a caller-supplied csrf', () async {
    final http = FakeHTTP();
    http.routes[togglePath] = (200, okEmpty);
    await makeTestClient(http, cookies: {'bili_jct': 'REAL'}).postVoid(togglePath, form: {'csrf': 'forged', 'aid': '1'});
    expect(http.bodyText(http.requestsTo(togglePath).first), 'aid=1&csrf=REAL');
  });

  test('post without a csrf cookie throws without sending', () async {
    final http = FakeHTTP();
    final client = makeTestClient(http, cookies: {'SESSDATA': 's'});
    try {
      await client.postVoid(togglePath, form: {'aid': '1'});
      fail('expected -101');
    } on BiliError catch (error) {
      expect(error.needsLogin, isTrue);
      expect(error, const BiliError.api(code: -101, message: '账号未登录'));
    }
    expect(http.requests, isEmpty);
  });

  test('risk control codes read as too frequent', () {
    expect(const BiliError.api(code: -352, message: '').userMessage, '请求过于频繁，请稍后再试');
    expect(const BiliError.api(code: -412, message: '').userMessage, '请求过于频繁，请稍后再试');
    expect(const BiliError.api(code: -101, message: '').userMessage, '需要登录');
  });

  test('needsLogin is only for code -101', () {
    expect(const BiliError.api(code: -101, message: 'x').needsLogin, isTrue);
    expect(const BiliError.api(code: -352, message: 'x').needsLogin, isFalse);
    expect(const BiliError.http(401).needsLogin, isFalse);
  });

  test('post error code throws the server message', () async {
    final http = FakeHTTP();
    http.routes[togglePath] = (200, '{"code":34002,"message":"不能给自己点赞"}');
    final client = makeTestClient(http, cookies: {'bili_jct': 'T'});
    await expectLater(client.postVoid(togglePath), throwsA(const BiliError.api(code: 34002, message: '不能给自己点赞')));
  });

  test('post decodes the data on success', () async {
    final http = FakeHTTP();
    http.routes['POST /x/web-interface/archive/like'] = (200, '{"code":0,"message":"0","data":{"like":true}}');
    final client = makeTestClient(http, cookies: {'bili_jct': 'T'});
    final like = await client.post('/x/web-interface/archive/like',
        form: {'bvid': 'BV1'}, decode: (json) => JsonObject.from(json).required(JsonObject.from(json).boolean('like'), 'like'));
    expect(like, isTrue);
  });

  test('a post that expects data throws when success carries none', () async {
    final http = FakeHTTP();
    http.routes[togglePath] = (200, okEmpty);
    final client = makeTestClient(http, cookies: {'bili_jct': 'T'});
    await expectLater(client.post(togglePath, decode: (json) => JsonObject.from(json).boolean('like')),
        throwsA(const BiliError.api(code: 0, message: '0')));
  });

  test('post HTTP failure throws', () async {
    final http = FakeHTTP();
    http.routes[togglePath] = (500, '');
    final client = makeTestClient(http, cookies: {'bili_jct': 'T'});
    await expectLater(client.postVoid(togglePath), throwsA(const BiliError.http(500)));
  });

  test('a post risk 412 is retried once with the same form', () async {
    final http = FakeHTTP()..routes = {togglePath: (412, ''), spiPath: (200, Fixtures.spi)};
    final client = makeTestClient(http, cookies: {'bili_jct': 'T', 'buvid3': 'old', 'buvid4': 'old'});
    await expectLater(client.postVoid(togglePath, form: {'aid': '1'}), throwsA(const BiliError.http(412)));
    final sent = http.requestsTo(togglePath);
    expect(sent.length, 2);
    expect(sent.map(http.bodyText), ['aid=1&csrf=T', 'aid=1&csrf=T']);
    expect(sent.last.headers['Cookie']?.contains('buvid3=B3-VALUE-infoc'), isTrue);
  });

  test('routes can answer one method only', () async {
    final http = FakeHTTP();
    http.routes['POST /p'] = (200, '{"code":0,"data":{"v":"post"}}');
    http.routes['/p'] = (200, '{"code":0,"data":{"v":"any"}}');
    final client = makeTestClient(http, cookies: {'bili_jct': 'T'});
    String decodeV(Object? json) => JsonObject.from(json).required(JsonObject.from(json).string('v'), 'v');
    final posted = await client.post('/p', decode: decodeV);
    final fetched = await client.get('/p', signed: false, decode: decodeV);
    expect(posted, 'post');
    expect(fetched, 'any');
  });

  test('form encoding keeps reserved characters and emoji', () {
    final body = utf8.decode(FormEncoding.encode({'message': "a&b=c+d !'()* 你好😀", 'b': '1'}));
    expect(body, 'b=1&message=a%26b%3Dc%2Bd%20%21%27%28%29%2A%20%E4%BD%A0%E5%A5%BD%F0%9F%98%80');
  });

  test('form encoding encodes keys and handles an empty form', () {
    expect(utf8.decode(FormEncoding.encode({})), '');
    expect(utf8.decode(FormEncoding.encode({'a b': '~-._'})), 'a%20b=~-._');
  });

  test('getData returns the raw body and the host can change', () async {
    final http = FakeHTTP();
    http.dataRoutes['/x/v2/dm/web/seg.so'] = (200, Uint8List.fromList([0x08, 0x01, 0xff, 0x80]));
    final client = makeTestClient(http, cookies: {'SESSDATA': 's'});
    final data = await client.getData('/x/v2/dm/web/seg.so', query: {'oid': '1', 'type': '1'}, signed: false);
    expect(data, [0x08, 0x01, 0xff, 0x80]);
    final request = http.requestsTo('/x/v2/dm/web/seg.so').first;
    expect(request.method, 'GET');
    expect(request.body, isNull);
    expect(http.query(request), {'oid': '1', 'type': '1'});

    http.routes['/ok'] = (200, '{"code":0,"data":{"n":1}}');
    await client.get('/ok', signed: false, host: 'https://account.bilibili.com', decode: decodeN);
    expect(http.requestsTo('/ok').first.url.host, 'account.bilibili.com');
  });

  test('getData HTTP failure throws', () async {
    final http = FakeHTTP();
    await expectLater(makeTestClient(http).getData('/missing', signed: false), throwsA(const BiliError.http(404)));
  });

  test('getData risk 412 is retried once', () async {
    final http = FakeHTTP()..routes = {'/seg': (412, ''), spiPath: (200, Fixtures.spi)};
    await expectLater(makeTestClient(http).getData('/seg', signed: false), throwsA(const BiliError.http(412)));
    expect(http.requestsTo('/seg').length, 2);
  });

  test('cookies are not sent to a non-Bilibili host', () async {
    final http = FakeHTTP();
    http.routes['/ok'] = (200, '{"code":0,"data":{"n":1}}');
    final client = makeTestClient(http, cookies: {'SESSDATA': 's', 'bili_jct': 'T'});
    await client.get('/ok', signed: false, host: 'https://evil.example', decode: decodeN);
    expect(http.requestsTo('/ok').first.headers['Cookie'], isNull);
  });

  test('a post to a non-Bilibili host is refused without sending', () async {
    final http = FakeHTTP();
    final client = makeTestClient(http, cookies: {'bili_jct': 'T'});
    await expectLater(client.postVoid('/ok', host: 'https://evil.example'), throwsA(BiliError.invalidLink));
    expect(http.requests, isEmpty);
  });
}
