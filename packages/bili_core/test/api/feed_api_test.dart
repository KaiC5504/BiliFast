import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const navPath = '/x/web-interface/nav';
const feedPath = '/x/web-interface/wbi/index/top/feed/rcmd';
const historyPath = '/x/web-interface/history/cursor';

// The web feed names the aid `id` and carries no `dimension`; the vertical and rotated rows are invented to cover the shape rule.
const feed = r'''
{"code":0,"message":"OK","ttl":1,"data":{"item":[
{"id":0,"goto":"ad","bvid":"","cid":0,"title":"广告位","pic":"https://i0.hdslb.com/bfs/archive/ad-0001.jpg","owner":{"mid":0,"name":""},"stat":{"view":0,"danmaku":0}},
{"id":91000001,"bvid":"BV1AA411a1aA","cid":138000001,"goto":"av","uri":"https://www.bilibili.com/video/BV1AA411a1aA","pic":"http://i0.hdslb.com/bfs/archive/feed-0001.jpg","title":"推荐视频一","duration":79,"pubdate":1760000000,
"owner":{"mid":501,"name":"UP主甲","face":"https://i0.hdslb.com/bfs/face/face-0501.jpg"},"stat":{"view":347398,"like":19093,"danmaku":631,"vt":0},"is_followed":0,
"rcmd_reason":{"content":"2万点赞","reason_type":3},"track_id":"web_pegasus_0.test"},
{"id":5001,"goto":"live","bvid":"","title":"直播间","pic":"https://i0.hdslb.com/bfs/live/live-0001.jpg","owner":{"mid":502,"name":"主播"},"stat":{"view":10,"danmaku":0}},
{"id":91000002,"bvid":"BV1BB411b2bB","cid":138000002,"goto":"av","pic":"https://i0.hdslb.com/bfs/archive/feed-0002.jpg","title":"竖屏视频","duration":15,"pubdate":1760000100,
"owner":{"mid":503,"name":"UP主乙"},"stat":{"view":"--","danmaku":7},"rcmd_reason":{"reason_type":0},"dimension":{"width":1080,"height":1920,"rotate":0}},
{"id":91000003,"bvid":"BV1CC411c3cC","cid":138000003,"goto":"av","pic":"https://i0.hdslb.com/bfs/archive/feed-0003.jpg","title":"存成竖的横屏视频","duration":300,"pubdate":1760000200,
"owner":{"mid":504,"name":"UP主丙"},"stat":{"view":42,"danmaku":1},"rcmd_reason":null,"dimension":{"width":1080,"height":1920,"rotate":1}},
{"id":91000004,"bvid":"","goto":"av","pic":"","title":"没有BV号","owner":{"mid":1,"name":"x"},"stat":{"view":1,"danmaku":1}}
]}}''';

const firstHistoryPage = r'''
{"code":0,"message":"0","ttl":1,"data":{"cursor":{"max":90000003,"view_at":1760600000,"business":"archive","ps":20},"tab":[{"type":"archive","name":"视频"}],"list":[
{"title":"历史视频一","long_title":"","cover":"https://i0.hdslb.com/bfs/archive/his-0001.jpg","covers":null,"uri":"",
"history":{"oid":90000001,"epid":0,"bvid":"BV1HA411a1aA","page":2,"cid":137650101,"part":"第二集","business":"archive","dt":1},
"videos":2,"author_name":"UP主甲","author_face":"https://i0.hdslb.com/bfs/face/face-0511.jpg","author_mid":511,"view_at":1760700000,"progress":65,"badge":"","show_title":"","duration":212,"is_fav":0,"kid":90000001,"live_status":0},
{"title":"历史视频二","cover":"https://i0.hdslb.com/bfs/archive/his-0002.jpg",
"history":{"oid":90000002,"epid":0,"bvid":"BV1HB411b2bB","page":1,"cid":137650102,"part":"","business":"archive","dt":2},
"videos":1,"author_name":"UP主乙","author_mid":512,"view_at":1760690000,"progress":-1,"duration":600},
{"title":"某篇专栏","cover":"","covers":["https://i0.hdslb.com/bfs/article/art-0001.jpg"],
"history":{"oid":6470274,"epid":0,"bvid":"","page":0,"cid":0,"part":"","business":"article","dt":2},
"author_name":"作者","author_mid":513,"view_at":1760650000,"progress":0,"duration":0},
{"title":"历史视频三","cover":"https://i0.hdslb.com/bfs/archive/his-0003.jpg",
"history":{"oid":90000003,"epid":0,"bvid":"BV1HC411c3cC","page":1,"cid":0,"part":"","business":"archive","dt":33},
"videos":1,"author_name":"UP主丙","author_mid":514,"view_at":1760600000,"progress":0,"duration":90}]}}''';

void main() {
  late FakeHTTP fakeHTTP;
  late BiliClient client;

  setUp(() {
    fakeHTTP = FakeHTTP();
    fakeHTTP.routes[navPath] = (200, Fixtures.navLoggedIn);
    client = makeTestClient(fakeHTTP, cookies: {'SESSDATA': 's', 'bili_jct': 'T', 'buvid3': 'b3', 'buvid4': 'b4'});
  });

  test('the feed keeps only videos and reads reason and shape', () async {
    fakeHTTP.routes[feedPath] = (200, feed);
    final cards = await client.recommendFeed(index: 1);
    expect(cards.map((card) => card.bvid), ['BV1AA411a1aA', 'BV1BB411b2bB', 'BV1CC411c3cC']);
    expect(
        cards[0],
        const FeedCard(
            aid: 91000001,
            bvid: 'BV1AA411a1aA',
            cid: 138000001,
            title: '推荐视频一',
            cover: 'http://i0.hdslb.com/bfs/archive/feed-0001.jpg',
            duration: 79,
            views: 347398,
            danmaku: 631,
            ownerName: 'UP主甲',
            ownerMid: 501,
            reason: '2万点赞',
            isVertical: false));
    expect(cards[0].id, 'BV1AA411a1aA');
    expect(cards[1].reason, isNull);
    expect(cards[2].reason, isNull);
    expect(cards.map((card) => card.isVertical), [false, true, false]);
    expect(cards[1].views, 0);
    expect(cards[1].ownerMid, 503);
  });

  test('feed query', () async {
    fakeHTTP.routes[feedPath] = (200, feed);
    await client.recommendFeed(index: 3);
    final query = fakeHTTP.query(fakeHTTP.requestsTo(feedPath).first);
    expect(query['fresh_type'], '4');
    expect(query['ps'], '12');
    expect(query['fresh_idx'], '3');
    expect(query['fresh_idx_1h'], '3');
    expect(query['brush'], '3');
    expect(query['feed_version'], 'V8');
    expect(query['w_rid'], isNotNull);
    expect(query['wts'], isNotNull);
  });

  test('a feed without items is empty', () async {
    fakeHTTP.routes[feedPath] = (200, '{"code":0,"message":"OK","ttl":1,"data":{"item":null}}');
    expect(await client.recommendFeed(index: 1), isEmpty);
    fakeHTTP.routes[feedPath] = (200, '{"code":0,"message":"OK","ttl":1,"data":null}');
    expect(await client.recommendFeed(index: 2), isEmpty);
  });

  test('history pages with the cursor', () async {
    fakeHTTP.routes[historyPath] = (200, firstHistoryPage);
    final first = await client.history();
    expect(first.items.map((item) => item.bvid), ['BV1HA411a1aA', 'BV1HB411b2bB', 'BV1HC411c3cC']);
    expect(
        first.items[0],
        const HistoryItem(
            aid: 90000001,
            bvid: 'BV1HA411a1aA',
            cid: 137650101,
            title: '历史视频一',
            cover: 'https://i0.hdslb.com/bfs/archive/his-0001.jpg',
            ownerName: 'UP主甲',
            progress: 65,
            duration: 212,
            viewAt: 1760700000,
            device: 1,
            part: '第二集'));
    expect(first.items[1].aid, 90000002, reason: 'without a kid, the aid comes from history.oid');
    expect(first.items[1].progress, -1);
    expect(first.items[1].part, isNull);
    expect(first.items.map((item) => item.device), [1, 2, 33]);
    expect(first.items.map((item) => item.id).toSet().length, 3);
    expect(first.next, const HistoryCursor(max: 90000003, viewAt: 1760600000));

    final firstQuery = fakeHTTP.query(fakeHTTP.requestsTo(historyPath).last);
    expect(firstQuery['max'], '0');
    expect(firstQuery['view_at'], '0');
    expect(firstQuery['business'], 'archive');
    expect(firstQuery['type'], 'archive');
    expect(firstQuery['ps'], '20');
    expect(firstQuery['w_rid'], isNull);

    await client.history(after: first.next);
    final secondQuery = fakeHTTP.query(fakeHTTP.requestsTo(historyPath).last);
    expect(secondQuery['max'], '90000003');
    expect(secondQuery['view_at'], '1760600000');
    expect(fakeHTTP.requestsTo(historyPath).length, 2);
  });

  test('an empty history page ends paging', () async {
    fakeHTTP.routes[historyPath] =
        (200, '{"code":0,"message":"0","ttl":1,"data":{"cursor":{"max":0,"view_at":0,"business":"","ps":20},"tab":[],"list":[]}}');
    final empty = await client.history(after: const HistoryCursor(max: 1, viewAt: 2));
    expect(empty.items, isEmpty);
    expect(empty.next, isNull);

    fakeHTTP.routes[historyPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{"cursor":{"max":5,"view_at":6},"list":null}}');
    final nullList = await client.history();
    expect(nullList.items, isEmpty);
    expect(nullList.next, isNull);
  });

  test('a zero history cursor with rows ends paging instead of restarting', () async {
    // max=0 and view_at=0 means "from the top" to the server, so passing it back would loop forever.
    final zero = firstHistoryPage.replaceAll('"cursor":{"max":90000003,"view_at":1760600000', '"cursor":{"max":0,"view_at":0');
    fakeHTTP.routes[historyPath] = (200, zero);
    final page = await client.history();
    expect(page.items.length, 3);
    expect(page.next, isNull);
  });

  test('a history page of only unplayable rows still advances', () async {
    const articleOnly = r'''
{"code":0,"message":"0","ttl":1,"data":{"cursor":{"max":6470274,"view_at":1760650000,"business":"archive","ps":20},"list":[
{"title":"某篇专栏","cover":"","history":{"oid":6470274,"bvid":"","page":0,"cid":0,"part":"","business":"article","dt":2},"author_name":"作者","view_at":1760650000,"progress":0,"duration":0}]}}''';
    fakeHTTP.routes[historyPath] = (200, articleOnly);
    final page = await client.history();
    expect(page.items, isEmpty);
    expect(page.next, const HistoryCursor(max: 6470274, viewAt: 1760650000));
  });

  test('history needs a login', () async {
    fakeHTTP.routes[historyPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
    await expectLater(client.history(), throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)));
  });

  test('deleting a history row posts its archive kid with the csrf', () async {
    const deletePath = '/x/v2/history/delete';
    fakeHTTP.routes[deletePath] = (200, '{"code":0,"message":"0","ttl":1}');
    await client.deleteHistory(aid: 90000001);
    final request = fakeHTTP.requestsTo(deletePath).single;
    expect(request.method, 'POST');
    expect(formFields(fakeHTTP.bodyText(request)), {'kid': 'archive_90000001', 'jsonp': 'jsonp', 'csrf': 'T'});

    fakeHTTP.routes[deletePath] = (200, '{"code":-111,"message":"csrf 校验失败","ttl":1}');
    await expectLater(client.deleteHistory(aid: 1), throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -111)));
  });

  test('device kind follows the dt code', () {
    HistoryDeviceKind kind(int dt) => HistoryItem(
            aid: 1,
            bvid: 'BV1',
            cid: 0,
            title: '',
            cover: '',
            ownerName: '',
            progress: 0,
            duration: 0,
            viewAt: 0,
            device: dt,
            part: null)
        .deviceKind;
    expect([1, 3, 5, 7].map(kind), List.filled(4, HistoryDeviceKind.phone));
    expect([2, 33].map(kind), [HistoryDeviceKind.pc, HistoryDeviceKind.pc]);
    expect([0, 4, 6, 9, 100].map(kind), List.filled(5, HistoryDeviceKind.padOrTV));
  });
}
