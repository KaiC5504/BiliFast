import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const _navPath = '/x/web-interface/nav';
const _followingsPath = '/x/relation/followings';
const _searchPath = '/x/relation/followings/search';
const _fansPath = '/x/relation/fans';
const _tagsPath = '/x/relation/tags';
const _tagUserPath = '/x/relation/tag/user';
const _addUsersPath = '/x/relation/tags/addUsers';

/// Made-up people: a 大会员 with a personal badge in 特别关注, a mutual with an organisation badge, one followed back
/// by nobody, and one whose mid won't decode.
const _page = '''
{"code":0,"message":"0","ttl":1,"data":{"list":[
  {"mid":20000901,"attribute":2,"special":1,"tag":[-10],"uname":"测试关注一","face":"https://i0.hdslb.com/bfs/face/a.jpg",
   "sign":"测试签名一","official_verify":{"type":0,"desc":"测试认证"},"vip":{"vipType":2,"vipStatus":1}},
  {"mid":"20000902","attribute":6,"special":0,"tag":null,"uname":"测试关注二","face":"",
   "sign":"","official_verify":{"type":1,"desc":""},"vip":{"vipType":0,"vipStatus":0}},
  {"mid":20000903,"attribute":0,"uname":"测试粉丝三","face":"","sign":"","official_verify":{"type":-1}},
  {"mid":"not a number","attribute":2,"uname":"坏数据"}
],"re_version":0,"total":45}}''';

const _empty = '{"code":0,"message":"0","ttl":1,"data":{"list":[],"re_version":0,"total":0}}';

const _tags = '''
{"code":0,"message":"0","ttl":1,"data":[
  {"tagid":-10,"name":"特别关注","count":1,"tip":"第一时间收到该分组下用户更新稿件的通知"},
  {"tagid":0,"name":"默认分组","count":13,"tip":""},
  {"tagid":3000001,"name":"测试分组","count":0,"tip":""}
]}''';

const _ok = '{"code":0,"message":"0","ttl":1,"data":null}';

void main() {
  late FakeHTTP http;
  late BiliClient client;
  late MemorySink sink;

  setUp(() {
    http = FakeHTTP();
    http.routes[_navPath] = (200, Fixtures.navLoggedIn);
    sink = MemorySink();
    client = BiliClient(
      transport: http,
      cookies: CookieJar({'SESSDATA': 'MADE-UP-SESSION', 'bili_jct': 'MADE-UP-CSRF', 'buvid3': 'b3', 'buvid4': 'b4'}),
      now: () => testNow,
      logger: Logger(session: 'test')..add(sink),
    );
  });

  group('关注', () {
    test('最近关注 asks an empty order_type, 最近访问 attention', () async {
      http.routes[_followingsPath] = (200, _page);
      await client.relationFollowings(mid: 20000900, order: FollowingOrder.recent, page: 1);
      await client.relationFollowings(mid: 20000900, order: FollowingOrder.mostVisited, page: 2);
      final [recent, visited] = http.requestsTo(_followingsPath);
      expect(http.query(recent), {'vmid': '20000900', 'pn': '1', 'ps': '20', 'order': 'desc', 'order_type': ''});
      expect(http.query(visited)['order_type'], 'attention');
      expect(http.query(visited)['pn'], '2');
      expect(http.query(visited).containsKey('w_rid'), isFalse);
    });

    test('each row decodes with its relation, badge and 大会员 pink; one that won\'t decode costs only itself', () async {
      http.routes[_followingsPath] = (200, _page);
      final page = await client.relationFollowings(mid: 20000900, order: FollowingOrder.recent, page: 1);
      expect(page.total, 45);
      expect(page.hasMore, isTrue);
      final [first, second, third] = page.users;
      expect(first.mid, 20000901);
      expect(first.user.name, '测试关注一');
      expect(first.user.sign, '测试签名一');
      expect(first.user.verify, DynamicVerify.personal);
      expect(first.user.vipPink, isTrue);
      expect(first.special, isTrue);
      expect((first.following, first.mutual), (true, false));
      expect(second.mid, 20000902);
      expect(second.user.verify, DynamicVerify.organisation);
      expect(second.user.vipPink, isFalse);
      expect((second.following, second.mutual), (true, true));
      expect(third.user.verify, DynamicVerify.none);
      expect((third.following, third.mutual), (false, false));
    });

    test('the last page by the total says there is no more, and so does an empty one', () async {
      http.routes[_followingsPath] = (200, _page);
      final last = await client.relationFollowings(mid: 20000900, order: FollowingOrder.recent, page: 3);
      expect(last.hasMore, isFalse);
      http.routes[_followingsPath] = (200, _empty);
      final empty = await client.relationFollowings(mid: 20000900, order: FollowingOrder.recent, page: 1);
      expect(empty.users, isEmpty);
      expect(empty.hasMore, isFalse);
    });

    test('搜索我的关注 is signed and sends the name', () async {
      http.routes[_searchPath] = (200, _page);
      final page = await client.searchRelationFollowings(mid: 20000900, name: '测试', page: 1);
      expect(page.users, hasLength(3));
      final query = http.query(http.requestsTo(_searchPath).single);
      expect(query['vmid'], '20000900');
      expect(query['name'], '测试');
      expect(query['pn'], '1');
      expect(query['w_rid'], hasLength(32));
    });
  });

  group('粉丝', () {
    test('asks /x/relation/fans by pn, each row with whether it is followed back', () async {
      http.routes[_fansPath] = (200, _page);
      final page = await client.fans(mid: 20000900, page: 2);
      expect(http.query(http.requestsTo(_fansPath).single), {'vmid': '20000900', 'pn': '2', 'ps': '20', 'order': 'desc'});
      expect(page.users.map((user) => user.mutual), [false, true, false]);
      expect(page.hasMore, isTrue);
    });

    test('none at all is an empty last page', () async {
      http.routes[_fansPath] = (200, _empty);
      final page = await client.fans(mid: 20000900, page: 1);
      expect(page.users, isEmpty);
      expect(page.total, 0);
      expect(page.hasMore, isFalse);
    });
  });

  group('分组', () {
    test('the account\'s 分组 with their tips', () async {
      http.routes[_tagsPath] = (200, _tags);
      final tags = await client.relationTags();
      expect(tags.map((tag) => (tag.id, tag.name, tag.count)), [
        (RelationTag.special, '特别关注', 1),
        (RelationTag.defaultGroup, '默认分组', 13),
        (3000001, '测试分组', 0),
      ]);
      expect(tags.first.tip, '第一时间收到该分组下用户更新稿件的通知');
    });

    test('one person\'s 分组 by fid: the map\'s keys, empty for none or no data', () async {
      http.routes[_tagUserPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{"-10":"特别关注","3000001":"测试分组"}}');
      expect(await client.relationTagsOf(mid: 20000901), {-10, 3000001});
      expect(http.query(http.requestsTo(_tagUserPath).single), {'fid': '20000901'});
      http.routes[_tagUserPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{}}');
      expect(await client.relationTagsOf(mid: 20000901), isEmpty);
      http.routes[_tagUserPath] = (200, _ok);
      expect(await client.relationTagsOf(mid: 20000901), isEmpty);
    });

    test('saving posts fids and the sorted tagids with the csrf token, 0 for 默认分组', () async {
      http.routes['POST $_addUsersPath'] = (200, _ok);
      await client.setRelationTags(mid: 20000901, tags: {3000001, RelationTag.special});
      await client.setRelationTags(mid: 20000901, tags: {});
      final [chosen, none] = http.requestsTo(_addUsersPath);
      expect(chosen.method, 'POST');
      expect(formFields(http.bodyText(chosen)), {'fids': '20000901', 'tagids': '-10,3000001', 'csrf': 'MADE-UP-CSRF'});
      expect(chosen.headers['Content-Type'], startsWith('application/x-www-form-urlencoded'));
      expect(chosen.headers['Origin'], 'https://www.bilibili.com');
      expect(formFields(http.bodyText(none))['tagids'], '0');
    });

    test('a refusal throws its code, logged out nothing is sent, and the token never reaches the log', () async {
      http.routes['POST $_addUsersPath'] = (200, '{"code":22104,"message":"测试拒绝","ttl":1}');
      await expectLater(
        client.setRelationTags(mid: 20000901, tags: {RelationTag.special}),
        throwsA(const BiliError.api(code: 22104, message: '测试拒绝')),
      );
      final log = sink.events.map((event) => event.encode()).join('\n');
      expect(log, contains(_addUsersPath));
      expect(log, isNot(contains('MADE-UP-CSRF')));

      client.cookies.remove('bili_jct');
      await expectLater(
        client.setRelationTags(mid: 20000901, tags: {RelationTag.special}),
        throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)),
      );
      expect(http.requestsTo(_addUsersPath), hasLength(1));
    });
  });

  group('decoding on its own', () {
    test('a page without a list is empty, and tags that aren\'t a list are none', () {
      final page = RelationDecode.page({'total': 3}, page: 1, pageSize: 20);
      expect(page.users, isEmpty);
      expect(page.hasMore, isFalse);
      expect(RelationDecode.tags({'not': 'a list'}), isEmpty);
      expect(RelationDecode.tagsOf(const <Object?>[]), isEmpty);
      expect(RelationDecode.tagsOf({'oops': '?', '-10': '特别关注'}), {-10});
    });

    test('悄悄关注 counts as following; 拉黑 as neither', () {
      RelationUser one(int attribute) =>
          RelationDecode.page({
            'list': [
              {'mid': 1, 'attribute': attribute},
            ],
          }, page: 1, pageSize: 20).users.single;
      expect(one(RelationUser.whisper).following, isTrue);
      expect(one(128).following, isFalse);
      expect(one(128).mutual, isFalse);
    });
  });
}
