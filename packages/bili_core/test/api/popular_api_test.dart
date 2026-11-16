import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

const _popularPath = '/x/web-interface/popular';

/// Made-up rows: one with a reason tag, one without a publish time, and one with no bvid.
const _page = r'''
{"code":0,"message":"0","ttl":1,"data":{"list":[
 {"aid":90000001,"bvid":"BV1EF411e9oF","cid":137650001,"pic":"https://i0.hdslb.com/bfs/archive/hot1.jpg","title":"测试热门一",
  "pubdate":1760000000,"duration":605,"owner":{"mid":77,"name":"测试UP","face":"https://i0.hdslb.com/bfs/face/up.jpg"},
  "stat":{"view":1831000,"danmaku":120,"reply":9,"like":1500},"rcmd_reason":{"content":"百万播放","corner_mark":0}},
 {"aid":90000002,"bvid":"BV1GH411f0pG","title":"测试热门二","pubdate":0,"owner":{"mid":78,"name":"测试UP二"},"stat":{"view":1},
  "rcmd_reason":{"content":""}},
 {"aid":90000003,"title":"没有 bvid"}
],"no_more":false}}''';

void main() {
  late FakeHTTP http;
  late BiliClient client;

  setUp(() {
    http = FakeHTTP();
    client = makeTestClient(http);
  });

  test('asks pn and 20 a page, unsigned', () async {
    http.routes[_popularPath] = (200, _page);
    await client.popular(page: 3);
    final request = http.requestsTo(_popularPath).single;
    expect((request.method, request.url.host), ('GET', 'api.bilibili.com'));
    expect(http.query(request), {'pn': '3', 'ps': '20'});
  });

  test('each row is a video card with its publish time and reason; one that won\'t decode costs only itself', () async {
    http.routes[_popularPath] = (200, _page);
    final page = await client.popular(page: 1);
    expect((page.page, page.hasMore), (1, true));
    final [first, second] = page.videos;
    expect(
      (first.card.bvid, first.card.title, first.card.ownerName, first.card.views),
      ('BV1EF411e9oF', '测试热门一', '测试UP', 1831000),
    );
    expect(first.card.duration, 605);
    expect(first.published?.millisecondsSinceEpoch, 1760000000000);
    expect(first.reason, '百万播放');
    expect((second.card.bvid, second.published, second.reason), ('BV1GH411f0pG', null, ''));
  });

  test('no_more, or an empty page, ends the list', () {
    expect(
      PopularDecode.page({
        'list': [
          {'bvid': 'BV1EF411e9oF'},
        ],
        'no_more': true,
      }, page: 9).hasMore,
      isFalse,
    );
    expect(PopularDecode.page({'list': <Object?>[], 'no_more': false}, page: 9).hasMore, isFalse);
    expect(PopularDecode.page(<String, Object?>{}, page: 9).videos, isEmpty);
  });

  test('a refusal throws its code', () async {
    http.routes[_popularPath] = (200, '{"code":-352,"message":"测试风控","ttl":1}');
    await expectLater(client.popular(page: 1), throwsA(const BiliError.api(code: -352, message: '测试风控')));
  });
}
