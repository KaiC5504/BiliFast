import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';
import 'search_fixtures.dart';

const navPath = '/x/web-interface/nav';
const defaultPath = '/x/web-interface/wbi/search/default';
const trendingPath = '/x/v2/search/trending/ranking';
const recommendPath = '/x/v2/search/recommend';
const suggestPath = '/x/web-interface/suggest';
const allPath = '/x/web-interface/wbi/search/all/v2';
const typePath = '/x/web-interface/wbi/search/type';

DateTime local(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

void main() {
  late FakeHTTP fakeHTTP;
  late BiliClient client;

  setUp(() {
    fakeHTTP = FakeHTTP();
    fakeHTTP.routes[navPath] = (200, Fixtures.navLoggedOut);
    client = makeTestClient(fakeHTTP, cookies: {'buvid3': 'b3', 'buvid4': 'b4'});
  });

  HTTPRequest only(String path) {
    final requests = fakeHTTP.requestsTo(path);
    expect(requests, hasLength(1));
    return requests.single;
  }

  group('default word', () {
    test('is signed and prefers show_name', () async {
      fakeHTTP.routes[defaultPath] = (200, SearchFixtures.defaultWord);
      expect(await client.searchDefaultWord(), '测试默认词');
      final request = only(defaultPath);
      expect(request.url.host, 'api.bilibili.com');
      final query = fakeHTTP.query(request);
      expect(query['web_location'], '333.1365');
      expect(query['w_rid'], isNotNull);
      expect(query['wts'], isNotNull);
    });

    test('falls back to name, and is null when both are empty or there is no data', () async {
      fakeHTTP.routes[defaultPath] = (200, SearchFixtures.defaultWordNameOnly);
      expect(await client.searchDefaultWord(), '只有名字');
      fakeHTTP.routes[defaultPath] = (200, SearchFixtures.defaultWordEmpty);
      expect(await client.searchDefaultWord(), isNull);
      fakeHTTP.routes[defaultPath] = (200, '{"code":0,"message":"0","ttl":1,"data":null}');
      expect(await client.searchDefaultWord(), isNull);
    });
  });

  group('hot words', () {
    test('ask for ten, unsigned, from the api host', () async {
      fakeHTTP.routes[trendingPath] = (200, SearchFixtures.trending);
      await client.hotWords();
      final request = only(trendingPath);
      expect(request.url.host, 'api.bilibili.com');
      expect(fakeHTTP.query(request), {'limit': '10'});
      expect(fakeHTTP.requestsTo(navPath), isEmpty, reason: 'unsigned calls need no WBI keys');
    });

    test('decode keyword, show name and badge, drop a row without a keyword, and keep ten', () async {
      fakeHTTP.routes[trendingPath] = (200, SearchFixtures.trending);
      final words = await client.hotWords();
      expect(words, hasLength(10));
      expect(words.first, const HotWord(keyword: '热搜词一', showName: '热搜词一'));
      expect(
        words[1],
        const HotWord(
          keyword: '热搜词二',
          showName: '热搜词二',
          icon: 'https://i0.hdslb.com/bfs/activity-plat/static/made-up/hot-badge.png',
        ),
      );
      expect(
        words[2],
        const HotWord(
          keyword: '热搜词三',
          showName: '热搜词三展示',
          icon: 'https://i0.hdslb.com/bfs/activity-plat/static/made-up/new-badge.png',
        ),
      );
      expect(
        words[3],
        const HotWord(keyword: '热搜词四', showName: '热搜词四'),
        reason: 'no show_name, "" icon',
      );
      expect(
        words[4],
        const HotWord(keyword: '热搜词六', showName: '热搜词六'),
        reason: 'empty show_name',
      );
      expect(words[6].icon, 'https://i0.hdslb.com/bfs/activity-plat/static/made-up/hot-badge.png');
      expect(words.map((word) => word.keyword), isNot(contains('没有关键词')));
      expect(words.last.keyword, '热搜词十一');
    });

    test('an answer without a list is empty', () async {
      fakeHTTP.routes[trendingPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{"trackid":"1","list":null}}');
      expect(await client.hotWords(), isEmpty);
      fakeHTTP.routes[trendingPath] = (200, '{"code":0,"message":"0","ttl":1,"data":null}');
      expect(await client.hotWords(), isEmpty);
    });
  });

  group('discovery words', () {
    test('go to the app host with exactly the Android parameters, unsigned', () async {
      fakeHTTP.routes[recommendPath] = (200, SearchFixtures.recommend);
      await client.discoveryWords();
      final request = only(recommendPath);
      expect(request.url.host, 'app.bilibili.com');
      expect(fakeHTTP.query(request), {
        'build': '8430300',
        'channel': 'master',
        'version': '8.43.0',
        'c_locale': 'zh_CN',
        'mobi_app': 'android',
        'platform': 'android',
        's_locale': 'zh_CN',
        'from': '2',
      });
    });

    test('go without the web session cookies, as every app-host call does', () async {
      final loggedIn = makeTestClient(fakeHTTP, cookies: {'SESSDATA': 'made-up-session', 'bili_jct': 'made-up-jct'});
      fakeHTTP.routes[recommendPath] = (200, SearchFixtures.recommend);
      fakeHTTP.routes[trendingPath] = (200, SearchFixtures.trending);
      await loggedIn.discoveryWords();
      await loggedIn.hotWords();
      expect(only(recommendPath).headers.keys.map((name) => name.toLowerCase()), isNot(contains('cookie')));
      expect(only(trendingPath).headers['Cookie'], contains('SESSDATA'), reason: 'the web host still gets them');
    });

    test('decode keyword, show name and the grey suffix, dropping a row without a keyword', () async {
      fakeHTTP.routes[recommendPath] = (200, SearchFixtures.recommend);
      expect(await client.discoveryWords(), const [
        DiscoveryWord(keyword: '发现词一', showName: '发现词一'),
        DiscoveryWord(keyword: '发现词二', showName: '发现词二展示', suffix: '昨天更新'),
        DiscoveryWord(keyword: '发现词四', showName: '发现词四', suffix: '3天前'),
      ]);
    });

    test('an error code throws', () async {
      fakeHTTP.routes[recommendPath] = (200, '{"code":-400,"message":"请求错误","ttl":1}');
      await expectLater(client.discoveryWords(), throwsA(const BiliError.api(code: -400, message: '请求错误')));
    });
  });

  group('suggestions', () {
    test('send the term, signed', () async {
      fakeHTTP.routes[suggestPath] = (200, SearchFixtures.suggest);
      await client.searchSuggestions('KIWI');
      final query = fakeHTTP.query(only(suggestPath));
      expect(query['term'], 'KIWI');
      expect(query['highlight'], '0');
      expect(query['spmid'], '333.1365');
      expect(query['web_location'], '333.1365');
      expect(query['w_rid'], isNotNull);
      expect(query['wts'], isNotNull);
    });

    test('read result.tag beside code, marking the typed term whatever its case', () async {
      fakeHTTP.routes[suggestPath] = (200, SearchFixtures.suggest);
      final suggestions = await client.searchSuggestions('KIWI');
      expect(suggestions.map((suggestion) => suggestion.keyword), ['kiwijam联动', '测试KIWI大全', '无关测试', 'kiwi标记']);
      expect(suggestions[0].text.runs, const [HighlightRun('kiwi', highlighted: true), HighlightRun('jam联动')]);
      expect(suggestions[1].text.runs, const [
        HighlightRun('测试'),
        HighlightRun('KIWI', highlighted: true),
        HighlightRun('大全'),
      ]);
      expect(suggestions[2].text.runs, const [HighlightRun('无关测试')]);
    });

    test('a name with its own marks is drawn as marked', () async {
      fakeHTTP.routes[suggestPath] = (200, SearchFixtures.suggest);
      final suggestions = await client.searchSuggestions('s');
      expect(suggestions.last.keyword, 'kiwi标记');
      expect(suggestions.last.text.runs, const [HighlightRun('kiwi', highlighted: true), HighlightRun('标记')]);
    });

    test('also read data.result', () async {
      fakeHTTP.routes[suggestPath] = (200, SearchFixtures.suggestUnderData);
      final suggestions = await client.searchSuggestions('kiwi');
      expect(suggestions, [
        const SearchSuggestion(
          keyword: 'kiwi测试',
          text: HighlightedText([HighlightRun('kiwi', highlighted: true), HighlightRun('测试')]),
        ),
      ]);
    });

    test('an empty or missing result is no suggestions', () async {
      fakeHTTP.routes[suggestPath] = (200, SearchFixtures.suggestEmpty);
      expect(await client.searchSuggestions('kiwi'), isEmpty);
      fakeHTTP.routes[suggestPath] = (200, SearchFixtures.suggestNoResult);
      expect(await client.searchSuggestions('kiwi'), isEmpty);
      fakeHTTP.routes[suggestPath] = (200, '{"code":0,"result":{"tag":null}}');
      expect(await client.searchSuggestions('kiwi'), isEmpty);
    });

    test('a blank term asks nothing', () async {
      expect(await client.searchSuggestions('  '), isEmpty);
      expect(fakeHTTP.requests, isEmpty);
    });

    test('an error code throws and bad JSON is a decoding error', () async {
      fakeHTTP.routes[suggestPath] = (200, '{"code":-412,"message":"请求被拦截"}');
      await expectLater(client.searchSuggestions('kiwi'), throwsA(const BiliError.api(code: -412, message: '请求被拦截')));
      fakeHTTP.routes[suggestPath] = (200, 'not json');
      await expectLater(client.searchSuggestions('kiwi'), throwsA(isA<BiliDecodingError>()));
    });
  });

  group('综合', () {
    test('is signed, sends the search page parameters and the search referer', () async {
      fakeHTTP.routes[allPath] = (200, SearchFixtures.all);
      await client.searchAll(keyword: '星星 测试', page: 1);
      final request = only(allPath);
      final query = fakeHTTP.query(request);
      expect(query['search_type'], 'all');
      expect(query['keyword'], '星星 测试');
      expect(query['page'], '1');
      expect(query['page_size'], '20');
      expect(query['platform'], 'pc');
      expect(query['web_location'], '1430654');
      expect(query['w_rid'], isNotNull);
      expect(query['wts'], isNotNull);
      expect(
        request.headers['Referer'],
        'https://search.bilibili.com/all?keyword=%E6%98%9F%E6%98%9F%20%E6%B5%8B%E8%AF%95',
      );
    });

    test('keeps only the video group\'s videos, dropping live rooms and rows that fail', () async {
      fakeHTTP.routes[allPath] = (200, SearchFixtures.all);
      final result = await client.searchAll(keyword: '星星');
      expect(result.items.map((video) => video.bvid), ['BV1Te4y1s7aA', 'BV1Te4y1s7aC', 'BV1Te4y1s7aE']);
      expect(
        result.items.first,
        SearchVideo(
          aid: 113000000000101,
          bvid: 'BV1Te4y1s7aA',
          title: const HighlightedText([
            HighlightRun('【测试】'),
            HighlightRun('星星', highlighted: true),
            HighlightRun('的视频 & 更多'),
            HighlightRun('星星', highlighted: true),
          ]),
          author: '测试UP甲',
          mid: 7000001,
          cover: 'https://i1.hdslb.com/bfs/archive/made-up-cover-0101.jpg',
          play: 12345,
          danmaku: 67,
          duration: 187,
          published: local(1760000000),
        ),
      );
      final second = result.items[1];
      expect(second.title, HighlightedText.plain('无高亮的标题'));
      expect(second.cover, 'https://i2.hdslb.com/bfs/archive/made-up-cover-0103.jpg');
      expect(second.play, 4321, reason: 'play as a string');
      expect(second.danmaku, 21, reason: 'video_review as a string');
      expect(second.duration, 13 * 60 + 14);
      final third = result.items[2];
      expect(third.duration, 3723);
      expect(third.danmaku, 5, reason: 'danmaku when video_review is missing');
      expect(third.published, isNull);
      expect(result.page, 1);
      expect(result.pages, 50);
      expect(result.hasMore, isTrue);
    });

    test('takes the page count from pageinfo when numPages is missing', () async {
      fakeHTTP.routes[allPath] = (
        200,
        '{"code":0,"data":{"page":3,"pageinfo":{"video":{"numResults":60,"pages":3}},'
            '"result":[{"result_type":"video","data":[{"type":"video","bvid":"BV1Te4y1s7dA","aid":1,"duration":"0:01"}]}]}}',
      );
      final result = await client.searchAll(keyword: '星星', page: 3);
      expect(result.items.single.bvid, 'BV1Te4y1s7dA');
      expect(result.page, 3);
      expect(result.pages, 3);
      expect(result.hasMore, isFalse);
    });

    test('an answer without a video group ends the search', () async {
      fakeHTTP.routes[allPath] = (
        200,
        '{"code":0,"data":{"page":1,"numPages":50,"result":[{"result_type":"tips","data":[]}]}}',
      );
      final result = await client.searchAll(keyword: '星星');
      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse);
    });
  });

  group('综合 with 筛选', () {
    test('sends the defaults without order and with duration 0', () async {
      fakeHTTP.routes[typePath] = (200, SearchFixtures.video);
      await client.searchVideos(keyword: '星星', page: 2);
      final request = only(typePath);
      final query = fakeHTTP.query(request);
      expect(query['search_type'], 'video');
      expect(query['keyword'], '星星');
      expect(query['page'], '2');
      expect(query.containsKey('order'), isFalse);
      expect(query['duration'], '0');
      expect(query.containsKey('pubtime_begin_s'), isFalse);
      expect(query.containsKey('pubtime_end_s'), isFalse);
      expect(query['page_size'], '20');
      expect(query['platform'], 'pc');
      expect(query['web_location'], '1430654');
      expect(query['w_rid'], isNotNull);
      expect(request.headers['Referer'], 'https://search.bilibili.com/video?keyword=%E6%98%9F%E6%98%9F');
    });

    test('sends order, duration and the publish window in unix seconds', () async {
      fakeHTTP.routes[typePath] = (200, SearchFixtures.video);
      final from = DateTime.utc(2026, 10, 1);
      final to = DateTime.utc(2026, 10, 21, 23, 59, 59);
      await client.searchVideos(
        keyword: '星星',
        order: SearchOrder.pubdate,
        duration: SearchDuration.from10to30,
        publishedFrom: from,
        publishedTo: to,
      );
      final query = fakeHTTP.query(only(typePath));
      expect(query['order'], 'pubdate');
      expect(query['duration'], '2');
      expect(query['pubtime_begin_s'], '${from.millisecondsSinceEpoch ~/ 1000}');
      expect(query['pubtime_end_s'], '${to.millisecondsSinceEpoch ~/ 1000}');
      expect(query['page'], '1');
    });

    test('every order and duration goes by name and index', () async {
      fakeHTTP.routes[typePath] = (200, SearchFixtures.video);
      for (final order in SearchOrder.values.skip(1)) {
        await client.searchVideos(keyword: 'k', order: order, duration: SearchDuration.over60);
        final query = fakeHTTP.query(fakeHTTP.requestsTo(typePath).last);
        expect(query['order'], order.name);
        expect(query['duration'], '4');
      }
      expect(SearchOrder.values.map((order) => order.name), ['totalrank', 'pubdate', 'click', 'dm']);
    });

    test('decodes the rows and the page', () async {
      fakeHTTP.routes[typePath] = (200, SearchFixtures.video);
      final result = await client.searchVideos(keyword: '星星', page: 2);
      expect(result.page, 2);
      expect(result.pages, 50);
      expect(result.items, hasLength(2));
      final first = result.items.first;
      expect(first.title.text, '测试剧情合集四期（<更新> "主线" \'一\' ❤）');
      expect(first.title.runs, hasLength(1));
      expect(first.duration, 1234 * 60 + 56);
      expect(first.cover, 'https://i1.hdslb.com/bfs/archive/made-up-cover-0201.jpg');
      expect(first.published, local(1750000000));
      expect(first.aid, 113000000000201);
      expect(first.mid, 7000011);
      expect(first.author, '测试合集UP');
      final second = result.items[1];
      expect(second.duration, 125, reason: 'an integer duration is seconds');
      expect(second.play, 0, reason: 'a hidden count');
      expect(second.danmaku, 12);
    });

    test('an empty page ends the search', () async {
      fakeHTTP.routes[typePath] = (200, SearchFixtures.emptySearch);
      final result = await client.searchVideos(keyword: '星星');
      expect(result.items, isEmpty);
      expect(result.page, 1);
      expect(result.hasMore, isFalse);
    });
  });

  group('用户', () {
    test('searches bili_user with the user tab referer', () async {
      fakeHTTP.routes[typePath] = (200, SearchFixtures.user);
      await client.searchUsers(keyword: '测试', page: 1);
      final request = only(typePath);
      final query = fakeHTTP.query(request);
      expect(query['search_type'], 'bili_user');
      expect(query['keyword'], '测试');
      expect(query['page'], '1');
      expect(query['page_size'], '20');
      expect(query['platform'], 'pc');
      expect(query['web_location'], '1430654');
      expect(query['w_rid'], isNotNull);
      expect(request.headers['Referer'], 'https://search.bilibili.com/upuser?keyword=%E6%B5%8B%E8%AF%95');
    });

    test('decodes the rows, verification and following', () async {
      fakeHTTP.routes[typePath] = (200, SearchFixtures.user);
      final result = await client.searchUsers(keyword: '测试');
      expect(result.page, 1);
      expect(result.pages, 3);
      expect(result.items.map((user) => user.mid), [9000001, 9000002, 9000003, 9000004, 9000005]);
      expect(
        result.items[0],
        const SearchUser(
          mid: 9000001,
          name: '测试用户甲',
          face: 'https://i2.hdslb.com/bfs/face/made-up-face-0301.jpg',
          fans: 8,
          videos: 0,
          level: 2,
          sign: '签名&符号',
        ),
      );
      expect(
        result.items[1],
        const SearchUser(
          mid: 9000002,
          name: '测试知名UP',
          face: 'https://i1.hdslb.com/bfs/face/made-up-face-0302.jpg',
          fans: 23456,
          videos: 87,
          level: 6,
          sign: '知名UP的签名',
          officialType: 0,
          officialDesc: 'bilibili 测试知名UP主',
        ),
      );
      final organisation = result.items[2];
      expect(organisation.officialType, 1);
      expect(organisation.officialDesc, '测试机构官方账号');
      expect(organisation.fans, 2100, reason: 'fans as a string');
      expect(organisation.face, 'https://i0.hdslb.com/bfs/face/made-up-face-0303.jpg');
      expect(organisation.following, isTrue);
      expect(result.items[3].officialType, isNull, reason: 'no official_verify');
      expect(result.items[4].officialType, isNull, reason: 'type -1');
      expect(result.items.where((user) => user.following), hasLength(1));
    });
  });

  group('risk control', () {
    final calls = <String, Future<Object> Function(BiliClient client)>{
      '综合': (client) => client.searchAll(keyword: '星星'),
      '筛选': (client) => client.searchVideos(keyword: '星星', order: SearchOrder.click),
      '用户': (client) => client.searchUsers(keyword: '星星'),
    };

    for (final MapEntry(key: name, value: call) in calls.entries) {
      test('a v_voucher in $name\'s answer is a too-many-searches error', () async {
        fakeHTTP.routes[allPath] = (200, SearchFixtures.captcha);
        fakeHTTP.routes[typePath] = (200, SearchFixtures.captcha);
        await expectLater(
          call(client),
          throwsA(
            isA<BiliAPIError>()
                .having((error) => error.code, 'code', -352)
                .having((error) => error.userMessage, 'userMessage', '请求过于频繁，请稍后再试')
                .having((error) => error.needsLogin, 'needsLogin', isFalse),
          ),
        );
      });
    }

    test('a v_voucher with -352 is the same error', () async {
      fakeHTTP.routes[typePath] = (200, SearchFixtures.captchaRefused);
      await expectLater(
        client.searchUsers(keyword: '星星'),
        throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -352)),
      );
    });

    test('an empty v_voucher is not a captcha', () async {
      fakeHTTP.routes[typePath] = (200, '{"code":0,"data":{"v_voucher":"","page":1,"numPages":1,"result":[]}}');
      expect((await client.searchUsers(keyword: '星星')).items, isEmpty);
    });

    test('412 is still retried once with fresh fingerprint cookies', () async {
      fakeHTTP.routes[typePath] = (412, '');
      fakeHTTP.routes['/x/frontend/finger/spi'] = (200, Fixtures.spi);
      await expectLater(client.searchUsers(keyword: '星星'), throwsA(const BiliError.http(412)));
      expect(fakeHTTP.requestsTo(typePath), hasLength(2));
      expect(fakeHTTP.requestsTo('/x/frontend/finger/spi'), hasLength(1));
      expect(fakeHTTP.requestsTo(typePath).last.headers['Referer'], startsWith('https://search.bilibili.com/upuser'));
    });
  });
}
