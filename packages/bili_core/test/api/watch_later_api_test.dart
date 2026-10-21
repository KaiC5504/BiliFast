import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const _navPath = '/x/web-interface/nav';
const _listPath = '/x/v2/history/toview/web';

// Every id, name and title is made up; the shape follows PiliPlus's LaterItemModel.
const _firstPage = r'''
{"code":0,"message":"0","ttl":1,"data":{"count":42,"list":[
{"aid":80000001,"videos":1,"tid":17,"pic":"https://i0.hdslb.com/bfs/archive/later-0001.jpg","title":"稍后视频一","pubdate":1760000000,"duration":412,
"owner":{"mid":601,"name":"UP主甲","face":"https://i0.hdslb.com/bfs/face/face-0601.jpg"},"stat":{"aid":80000001,"view":104000,"danmaku":175,"reply":9},
"cid":139000001,"progress":1,"add_at":1760100000,"bvid":"BV1WL411a1aA","is_pgc":false,"pgc_label":"","is_pugv":false},
{"aid":80000002,"pic":"https://i0.hdslb.com/bfs/archive/later-0002.jpg","title":"番剧一集","duration":1420,"owner":{"mid":602,"name":"番剧"},
"stat":{"view":5,"danmaku":1},"cid":139000002,"progress":0,"bvid":"BV1WL411b2bB","is_pgc":true,"pgc_label":"番剧"},
{"aid":80000003,"pic":"https://i0.hdslb.com/bfs/archive/later-0003.jpg","title":"看完的视频","duration":90,"owner":{"mid":603,"name":"UP主乙"},
"stat":{"view":"--","danmaku":2},"cid":139000003,"progress":-1,"bvid":"BV1WL411c3cC"},
{"aid":0,"title":"没有BV号","bvid":""}]}}''';

void main() {
  late FakeHTTP http;
  late BiliClient client;

  setUp(() {
    http = FakeHTTP();
    http.routes[_navPath] = (200, Fixtures.navLoggedIn);
    client = makeTestClient(http, cookies: {'SESSDATA': 's', 'bili_jct': 'T', 'buvid3': 'b3', 'buvid4': 'b4'});
  });

  test('the list keeps plain videos and reads progress, owner and counts', () async {
    http.routes[_listPath] = (200, _firstPage);
    final page = await client.watchLater(filter: WatchLaterFilter.all, oldestFirst: false, page: 1);
    expect(page.items.map((item) => item.bvid), ['BV1WL411a1aA', 'BV1WL411c3cC']);
    expect(
      page.items.first,
      const WatchLaterItem(
        aid: 80000001,
        bvid: 'BV1WL411a1aA',
        cid: 139000001,
        title: '稍后视频一',
        cover: 'https://i0.hdslb.com/bfs/archive/later-0001.jpg',
        ownerMid: 601,
        ownerName: 'UP主甲',
        duration: 412,
        progress: 1,
        play: 104000,
        danmaku: 175,
      ),
    );
    expect(page.items.last.progress, -1);
    expect(page.items.last.play, 0, reason: 'a hidden count reads 0');
    expect(page.total, 42);
    expect(page.hasMore, isTrue);
  });

  test('the filter, the order and the page go out WBI-signed', () async {
    http.routes[_listPath] = (200, _firstPage);
    await client.watchLater(filter: WatchLaterFilter.unfinished, oldestFirst: true, page: 2);
    final query = http.query(http.requestsTo(_listPath).single);
    expect(query['pn'], '2');
    expect(query['ps'], '20');
    expect(query['viewed'], '2');
    expect(query['asc'], 'true');
    expect(query['key'], '');
    expect(query['need_split'], 'true');
    expect(query['web_location'], '333.881');
    expect(query['w_rid'], isNotNull);
    expect(query['wts'], isNotNull);

    await client.watchLater(filter: WatchLaterFilter.all, oldestFirst: false, page: 1);
    final second = http.query(http.requestsTo(_listPath).last);
    expect(second['viewed'], '0');
    expect(second['asc'], 'false');
  });

  test('the list ends once its pages cover the count, or on an empty page', () async {
    http.routes[_listPath] = (200, _firstPage);
    final third = await client.watchLater(filter: WatchLaterFilter.all, oldestFirst: false, page: 3);
    expect(third.hasMore, isFalse, reason: '3 × 20 covers 42');

    http.routes[_listPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{"count":42,"list":[]}}');
    final empty = await client.watchLater(filter: WatchLaterFilter.all, oldestFirst: false, page: 1);
    expect(empty.items, isEmpty);
    expect(empty.hasMore, isFalse);

    http.routes[_listPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{"count":0,"list":null}}');
    expect(
      await client.watchLater(filter: WatchLaterFilter.all, oldestFirst: false, page: 1),
      WatchLaterListPage.empty,
    );

    http.routes[_listPath] = (200, '{"code":0,"message":"0","ttl":1,"data":null}');
    expect(
      await client.watchLater(filter: WatchLaterFilter.all, oldestFirst: false, page: 1),
      WatchLaterListPage.empty,
    );
  });

  test('a page of rows that only play in the official app still pages on', () async {
    http.routes[_listPath] = (
      200,
      '{"code":0,"message":"0","ttl":1,"data":{"count":30,"list":[{"aid":5,"bvid":"BV1pgc","is_pgc":true},'
          '{"aid":6,"bvid":"BV1pugv","is_pugv":true}]}}',
    );
    final page = await client.watchLater(filter: WatchLaterFilter.all, oldestFirst: false, page: 1);
    expect(page.items, isEmpty);
    expect(page.hasMore, isTrue);
  });

  test('the list needs a login', () async {
    http.routes[_listPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
    await expectLater(
      client.watchLater(filter: WatchLaterFilter.all, oldestFirst: false, page: 1),
      throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)),
    );
  });

  test('removing posts the aids as resources with the csrf', () async {
    const path = '/x/v2/history/toview/v2/dels';
    http.routes[path] = (200, '{"code":0,"message":"0","ttl":1}');
    await client.removeFromWatchLater(aids: [80000001, 80000003]);
    final request = http.requestsTo(path).single;
    expect(request.method, 'POST');
    expect(formFields(http.bodyText(request)), {'resources': '80000001,80000003', 'csrf': 'T'});

    http.routes[path] = (200, '{"code":-111,"message":"csrf 校验失败","ttl":1}');
    await expectLater(
      client.removeFromWatchLater(aids: [1]),
      throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -111)),
    );
  });

  test('removing nothing, or a row without its aid, fails before posting', () async {
    await expectLater(client.removeFromWatchLater(aids: []), throwsA(isA<BiliError>()));
    await expectLater(client.removeFromWatchLater(aids: [0]), throwsA(isA<BiliError>()));
    await expectLater(client.moveWatchLater(aids: [], folderId: 1), throwsA(isA<BiliError>()));
    expect(http.requests.where((request) => request.method == 'POST'), isEmpty);
  });

  test('clearing names watched as 2 and invalid as 1', () async {
    const path = '/x/v2/history/toview/clear';
    http.routes[path] = (200, '{"code":0,"message":"0","ttl":1}');
    await client.clearWatchLater(WatchLaterClean.watched);
    await client.clearWatchLater(WatchLaterClean.invalid);
    final bodies = [for (final request in http.requestsTo(path)) formFields(http.bodyText(request))];
    expect(bodies, [
      {'clean_type': '2', 'csrf': 'T'},
      {'clean_type': '1', 'csrf': 'T'},
    ]);
  });

  test('copying names the folder and the account; moving only the folder', () async {
    const copy = '/x/v2/history/toview/copy';
    const move = '/x/v2/history/toview/move';
    http.routes[copy] = (200, '{"code":0,"message":"0","ttl":1}');
    http.routes[move] = (200, '{"code":0,"message":"0","ttl":1}');
    await client.copyWatchLater(aids: [11, 12], folderId: 900, mid: 77);
    await client.moveWatchLater(aids: [13], folderId: 901);
    expect(formFields(http.bodyText(http.requestsTo(copy).single)), {
      'tar_media_id': '900',
      'mid': '77',
      'resources': '11,12',
      'platform': 'web',
      'csrf': 'T',
    });
    expect(formFields(http.bodyText(http.requestsTo(move).single)), {
      'tar_media_id': '901',
      'resources': '13',
      'platform': 'web',
      'csrf': 'T',
    });
  });
}
