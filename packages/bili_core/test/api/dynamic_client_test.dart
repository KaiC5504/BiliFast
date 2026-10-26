import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const navPath = '/x/web-interface/nav';
const feedPath = '/x/polymer/web-dynamic/v1/feed/all';
const spacePath = '/x/polymer/web-dynamic/v1/feed/space';
const detailPath = '/x/polymer/web-dynamic/v1/detail';
const portalPath = '/x/polymer/web-dynamic/v1/portal';
const uplistPath = '/x/polymer/web-dynamic/v1/uplist';
const thumbPath = '/x/dynamic/feed/dyn/thumb';
const followingsPath = '/x/relation/followings';
const bangumiPath = '/x/space/bangumi/follow/list';

String fixture(String name) => File('test/fixtures/dynamic/$name.json').readAsStringSync();

void main() {
  late FakeHTTP http;
  late BiliClient client;
  late MemorySink sink;

  setUp(() {
    http = FakeHTTP();
    http.routes[navPath] = (200, Fixtures.navLoggedIn);
    sink = MemorySink();
    client = BiliClient(
      transport: http,
      cookies: CookieJar({'SESSDATA': 'MADE-UP-SESSION', 'bili_jct': 'MADE-UP-CSRF', 'buvid3': 'b3', 'buvid4': 'b4'}),
      now: () => testNow,
      logger: Logger(session: 'test')..add(sink),
    );
  });

  group('👍', () {
    setUp(() => http.routes['POST $thumbPath'] = (200, '{"code":0,"message":"0","ttl":1,"data":{}}'));

    test('posts JSON with the id and up 1, csrf in the query, from t.bilibili.com', () async {
      await client.likeDynamic('1100000000000000001', on: true);
      final request = http.requestsTo(thumbPath).single;
      expect(request.method, 'POST');
      expect(request.url.host, 'api.bilibili.com');
      expect(http.query(request), {'csrf': 'MADE-UP-CSRF'});
      expect(jsonDecode(http.bodyText(request)), {
        'dyn_id_str': '1100000000000000001',
        'up': 1,
        'spmid': '333.1365.0.0',
      });
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(request.headers['Referer'], 'https://t.bilibili.com/');
      expect(request.headers['Origin'], 'https://www.bilibili.com');
      expect(request.headers['Cookie'], contains('SESSDATA=MADE-UP-SESSION'));
    });

    test('taking it back sends up 2', () async {
      await client.likeDynamic('1100000000000000001', on: false);
      final body = jsonDecode(http.bodyText(http.requestsTo(thumbPath).single)) as Map<String, Object?>;
      expect(body['up'], 2);
    });

    test('a refusal throws its code', () async {
      http.routes['POST $thumbPath'] = (200, '{"code":4128014,"message":"测试拒绝","ttl":1}');
      await expectLater(
        client.likeDynamic('1100000000000000001', on: true),
        throwsA(const BiliError.api(code: 4128014, message: '测试拒绝')),
      );
    });

    test('logged out it asks for the login and sends nothing', () async {
      client.cookies.remove('bili_jct');
      await expectLater(
        client.likeDynamic('1100000000000000001', on: true),
        throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)),
      );
      expect(http.requestsTo(thumbPath), isEmpty);
    });

    test('the csrf token never reaches the log', () async {
      await client.likeDynamic('1100000000000000001', on: true);
      final log = sink.events.map((event) => event.encode()).join('\n');
      expect(log, contains(thumbPath));
      expect(log, isNot(contains('MADE-UP-CSRF')));
    });
  });

  test('关注 asks feed/all with its type and the last offset', () async {
    http.routes[feedPath] = (200, fixture('feed_all'));
    final first = await client.dynamicFeed(type: DynamicFeedType.all);
    expect(first.items, hasLength(6));
    expect(first.skipped, {'DYNAMIC_TYPE_DRAW': 1, 'DYNAMIC_TYPE_AV': 1, 'unknown': 1});
    await client.dynamicFeed(type: DynamicFeedType.video, offset: first.offset);
    final [firstAsk, nextAsk] = http.requestsTo(feedPath);
    expect(http.query(firstAsk)['type'], 'all');
    expect(http.query(firstAsk).containsKey('offset'), isFalse);
    expect(http.query(firstAsk)['features'], contains('itemOpusStyle'));
    expect(http.query(nextAsk)['type'], 'video');
    expect(http.query(nextAsk)['offset'], '1100000000000000099');
  });

  test('a space feed is signed and sends the website fingerprint fields', () async {
    http.routes[spacePath] = (200, fixture('feed_space'));
    final page = await client.spaceDynamics(mid: 20000201);
    expect(page.items.single.pinned, isTrue);
    final query = http.query(http.requestsTo(spacePath).single);
    expect(query['host_mid'], '20000201');
    expect(query['dm_img_list'], '[]');
    expect(query['dm_img_str'], isNotEmpty);
    expect(query['dm_cover_img_str'], isNotEmpty);
    expect(query['dm_img_inter'], '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}');
    expect(query['w_rid'], hasLength(32));
    expect(query['wts'], isNotEmpty);
    expect(http.requestsTo(spacePath).single.headers['Referer'], 'https://space.bilibili.com/20000201/dynamic');
  });

  test('a post asks the detail by its id', () async {
    http.routes[detailPath] = (200, fixture('detail'));
    final item = await client.dynamicDetail('1100000000000000301');
    expect(item.author.location, 'IP属地：浙江');
    expect(http.query(http.requestsTo(detailPath).single)['id'], '1100000000000000301');
  });

  test('最常访问: the portal first, then uplist with its offset', () async {
    http.routes[portalPath] = (200, fixture('portal'));
    http.routes[uplistPath] = (200, fixture('uplist'));
    final first = await client.dynamicUps();
    expect(first.ups, hasLength(2));
    final next = await client.dynamicUps(offset: first.offset);
    expect(next.ups.single.name, '测试常看三');
    expect(http.query(http.requestsTo(uplistPath).single)['offset'], 'fake-offset-portal-0001');
    expect(http.requestsTo(portalPath), hasLength(1));
  });

  test('我的关注 pages by pn against the total', () async {
    http.routes[followingsPath] = (200, fixture('followings'));
    final first = await client.followingList(mid: 20000900, order: FollowingOrder.mostVisited, page: 1);
    expect(first.users, hasLength(3));
    expect(first.hasMore, isTrue);
    final last = await client.followingList(mid: 20000900, order: FollowingOrder.recent, page: 3);
    expect(last.hasMore, isFalse);
    final [firstAsk, lastAsk] = http.requestsTo(followingsPath);
    expect(http.query(firstAsk)['order_type'], 'attention');
    expect(http.query(lastAsk)['pn'], '3');
    expect(http.query(lastAsk)['order_type'], '');
  });

  test('我的追番 pages by pn against the total', () async {
    http.routes[bangumiPath] = (200, fixture('bangumi'));
    final page = await client.followedBangumi(mid: 20000900, page: 1);
    expect(page.items.first.progress, '全23话');
    expect(page.hasMore, isTrue);
    expect(http.query(http.requestsTo(bangumiPath).single)['ps'], '15');
  });
}
