import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const plainPath = '/x/v2/dm/web/seg.so';
const wbiPath = '/x/v2/dm/wbi/web/seg.so';
const navPath = '/x/web-interface/nav';
const spiPath = '/x/frontend/finger/spi';
const rulesPath = '/x/dm/filter/user';
const addPath = '/x/dm/filter/user/add';
const delPath = '/x/dm/filter/user/del';
const postPath = '/x/v2/dm/post';

List<int> varint(int value) {
  final bytes = <int>[];
  var v = value;
  while (v >= 0x80) {
    bytes.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  bytes.add(v);
  return bytes;
}

List<int> field(int number, List<int> bytes) => [...varint(number << 3 | 2), ...varint(bytes.length), ...bytes];

Uint8List segmentBytes(List<String> texts, {bool closed = false}) {
  final out = <int>[];
  for (final (i, text) in texts.indexed) {
    final elem = [...varint(2 << 3), ...varint(1000 * (i + 1)), ...field(7, utf8.encode(text))];
    out.addAll(field(1, elem));
  }
  if (closed) out.addAll([...varint(2 << 3), ...varint(1)]);
  return Uint8List.fromList(out);
}

Map<String, String> form(HTTPRequest request) => formFields(utf8.decode(request.body ?? Uint8List(0)));

DanmakuDraft draft({bool gradient = false, String text = '前方高能'}) => DanmakuDraft(
    cid: 2,
    bvid: 'BV1GJ411x7h7',
    text: text,
    mode: 1,
    fontSize: 25,
    color: 0xFE0302,
    gradient: gradient,
    progressMs: 61500);

void main() {
  test('segment fetch sends an unsigned query and decodes', () async {
    final http = FakeHTTP();
    http.dataRoutes[plainPath] = (200, segmentBytes(['甲', '乙', '丙']));
    final client = makeTestClient(http, cookies: {'SESSDATA': 's', 'buvid3': 'b3', 'buvid4': 'b4'});
    final segment = await client.danmakuSegment(cid: 137649199, index: 2);
    expect(segment.elems.map((elem) => elem.content), ['甲', '乙', '丙']);
    expect(segment.closed, isFalse);
    final request = http.requestsTo(plainPath).first;
    expect(http.query(request), {'type': '1', 'oid': '137649199', 'segment_index': '2'});
    expect(request.method, 'GET');
    expect(request.headers['Referer'], BiliClient.referer);
    expect(http.requestsTo(wbiPath), isEmpty);
    expect(http.requestsTo(navPath), isEmpty);
  });

  test('segment fetch query and WBI fallback', () async {
    final http = FakeHTTP()
      ..routes = {plainPath: (412, ''), spiPath: (200, Fixtures.spi), navPath: (200, Fixtures.navLoggedOut)};
    http.dataRoutes[wbiPath] = (200, segmentBytes(['甲', '乙']));
    final client = makeTestClient(http);
    final segment = await client.danmakuSegment(cid: 55, index: 1);
    expect(segment.elems.length, 2);
    final query = http.query(http.requestsTo(wbiPath).first);
    expect(query['oid'], '55');
    expect(query['segment_index'], '1');
    expect(query['type'], '1');
    expect(query['wts'], '1702204169');
    expect(query['w_rid']?.length, 32);
    expect(http.query(http.requestsTo(plainPath).first)['w_rid'], isNull);
  });

  test('segment fetch falls back on 403 too', () async {
    final http = FakeHTTP()..routes = {plainPath: (403, ''), navPath: (200, Fixtures.navLoggedOut)};
    http.dataRoutes[wbiPath] = (200, segmentBytes([], closed: true));
    final segment = await makeTestClient(http).danmakuSegment(cid: 1, index: 1);
    expect(segment.closed, isTrue);
    expect(segment.elems, isEmpty);
  });

  test('other HTTP errors are not retried on the signed path', () async {
    final http = FakeHTTP()..routes = {plainPath: (500, '')};
    await expectLater(makeTestClient(http).danmakuSegment(cid: 1, index: 1), throwsA(const BiliError.http(500)));
    expect(http.requestsTo(wbiPath), isEmpty);
  });

  test('a fallback failure is reported', () async {
    final http = FakeHTTP()
      ..routes = {plainPath: (403, ''), wbiPath: (403, ''), navPath: (200, Fixtures.navLoggedOut)};
    await expectLater(makeTestClient(http).danmakuSegment(cid: 1, index: 1), throwsA(const BiliError.http(403)));
  });

  test('an empty reply is an empty segment', () async {
    final http = FakeHTTP();
    http.dataRoutes[plainPath] = (200, Uint8List(0));
    final segment =
        await makeTestClient(http, cookies: {'buvid3': 'b', 'buvid4': 'b'}).danmakuSegment(cid: 1, index: 1);
    expect(segment.elems, isEmpty);
    expect(segment.closed, isFalse);
  });

  test('an unreadable reply becomes a decoding error', () async {
    final http = FakeHTTP()..routes = {plainPath: (200, '{"code":-400,"message":"请求错误"}')};
    await expectLater(makeTestClient(http, cookies: {'buvid3': 'b', 'buvid4': 'b'}).danmakuSegment(cid: 1, index: 1),
        throwsA(isA<BiliDecodingError>()));
  });

  test('block rules decode kinds', () async {
    final http = FakeHTTP();
    http.routes[rulesPath] = (
      200,
      r'''
{"code":0,"message":"0","ttl":1,"data":{"rule":[
{"id":11,"type":0,"filter":"剧透","ctime":"2026-01-01 00:00:00"},
{"id":12,"type":1,"filter":"/spoil.*/"},
{"id":13,"type":2,"filter":"cbf53a1c"},
{"id":14,"type":9,"filter":"future kind"},
{"id":15,"type":0}],"toast":"","valid":1,"ver":3}}'''
    );
    final rules =
        await makeTestClient(http, cookies: {'SESSDATA': 's', 'buvid3': 'b', 'buvid4': 'b'}).danmakuBlockRules();
    expect(rules, const [
      BlockRule(id: 11, kind: BlockRuleKind.keyword, filter: '剧透'),
      BlockRule(id: 12, kind: BlockRuleKind.regex, filter: '/spoil.*/'),
      BlockRule(id: 13, kind: BlockRuleKind.user, filter: 'cbf53a1c'),
    ]);
    expect(http.requestsTo(rulesPath).first.method, 'GET');
  });

  test('a null block rule list is empty', () async {
    final http = FakeHTTP();
    http.routes[rulesPath] = (200, '{"code":0,"message":"0","data":{"rule":null,"valid":0}}');
    final rules = await makeTestClient(http, cookies: {'buvid3': 'b', 'buvid4': 'b'}).danmakuBlockRules();
    expect(rules, isEmpty);
  });

  test('block rules logged out throw needsLogin', () async {
    final http = FakeHTTP();
    http.routes[rulesPath] = (200, '{"code":-101,"message":"账号未登录"}');
    await expectLater(makeTestClient(http, cookies: {'buvid3': 'b', 'buvid4': 'b'}).danmakuBlockRules(),
        throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)));
  });

  test('add and delete block rule forms', () async {
    final http = FakeHTTP();
    http.routes[addPath] = (200, '{"code":0,"message":"0","data":{"id":9,"type":0,"filter":"剧透"}}');
    http.routes[delPath] = (200, '{"code":0,"message":"0","data":null}');
    final client = makeTestClient(http, cookies: {'bili_jct': 'T'});
    final added = await client.addBlockRule(BlockRuleKind.keyword, filter: '剧透');
    expect(added, const BlockRule(id: 9, kind: BlockRuleKind.keyword, filter: '剧透'));
    await client.deleteBlockRule(id: 9);
    final add = http.requestsTo(addPath).first;
    expect(add.method, 'POST');
    expect(http.bodyText(add), 'csrf=T&filter=%E5%89%A7%E9%80%8F&type=0');
    expect(http.bodyText(http.requestsTo(delPath).first), 'csrf=T&ids=9');
  });

  test("addBlockRule sends the kind's raw value and tolerates a sparse reply", () async {
    final http = FakeHTTP();
    http.routes[addPath] = (200, '{"code":0,"message":"0","data":{"id":21}}');
    final added = await makeTestClient(http, cookies: {'bili_jct': 'T'}).addBlockRule(BlockRuleKind.user, filter: 'cbf53a1c');
    expect(added, const BlockRule(id: 21, kind: BlockRuleKind.user, filter: 'cbf53a1c'));
    expect(form(http.requestsTo(addPath).first)['type'], '2');
  });

  test('block rule writes need login without sending', () async {
    final http = FakeHTTP();
    final client = makeTestClient(http, cookies: {'SESSDATA': 's'});
    await expectLater(client.addBlockRule(BlockRuleKind.keyword, filter: 'x'),
        throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)));
    expect(http.requests, isEmpty);
  });

  test('postDanmaku form', () async {
    final http = FakeHTTP();
    http.routes[postPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{"action":"","dmid":777,"dmid_str":"777"}}');
    final client = makeTestClient(http, cookies: {'bili_jct': 'T', 'SESSDATA': 's'});
    final id = await client.postDanmaku(draft());
    expect(id, 777);
    final request = http.requestsTo(postPath).first;
    final body = http.bodyText(request);
    for (final part in [
      'color=16646914',
      'fontsize=25',
      'mode=1',
      'oid=2',
      'pool=0',
      'progress=61500',
      'type=1',
      'rnd=1702204169000000',
      'bvid=BV1GJ411x7h7',
      'csrf=T',
    ]) {
      expect(body.contains(part), isTrue, reason: '$part missing from $body');
    }
    expect(body.contains('colorful'), isFalse);
    expect(form(request)['msg'], '前方高能');
    expect(request.method, 'POST');
    expect(request.headers['Referer'], 'https://www.bilibili.com/video/BV1GJ411x7h7');
  });

  test('a gradient danmaku adds colorful', () async {
    final http = FakeHTTP();
    http.routes[postPath] = (200, '{"code":0,"data":{"dmid":5}}');
    await makeTestClient(http, cookies: {'bili_jct': 'T'}).postDanmaku(draft(gradient: true));
    expect(form(http.requestsTo(postPath).first)['colorful'], '60001');
  });

  test('postDanmaku keeps reserved characters and emoji', () async {
    final http = FakeHTTP();
    http.routes[postPath] = (200, '{"code":0,"data":{"dmid":5}}');
    const text = "a&b=c+d !'()* 😀 前方";
    await makeTestClient(http, cookies: {'bili_jct': 'T'}).postDanmaku(draft(text: text));
    expect(form(http.requestsTo(postPath).first)['msg'], text);
  });

  test('postDanmaku large ids and missing ids', () async {
    final http = FakeHTTP();
    http.routes[postPath] = (200, '{"code":0,"data":{"dmid":1702204169000000001}}');
    final client = makeTestClient(http, cookies: {'bili_jct': 'T'});
    expect(await client.postDanmaku(draft()), 1702204169000000001);
    http.routes[postPath] = (200, '{"code":0,"data":{}}');
    expect(await client.postDanmaku(draft()), 0);
  });

  test('a server refusal of postDanmaku carries the message', () async {
    final http = FakeHTTP();
    http.routes[postPath] = (200, '{"code":36703,"message":"发送过于频繁"}');
    await expectLater(makeTestClient(http, cookies: {'bili_jct': 'T'}).postDanmaku(draft()),
        throwsA(const BiliError.api(code: 36703, message: '发送过于频繁')));
  });

  test('postDanmaku without login sends nothing', () async {
    final http = FakeHTTP();
    await expectLater(makeTestClient(http).postDanmaku(draft()),
        throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)));
    expect(http.requests, isEmpty);
  });
}
