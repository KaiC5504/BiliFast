import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/src/api/md5.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'official_api_test.dart' show token;
import 'own_space_fixtures.dart';
import 'space_api_test.dart' show androidKey, androidParams, androidSecret, kept, signedLink, spacePath, ts;
import 'space_fixtures.dart';

const bangumiPath = '/x/v2/space/bangumi';

/// A fresh copy of [fixture]'s `data`, free to change.
Map<String, Object?> dataOf(String fixture) =>
    (jsonDecode(fixture) as Map<String, Object?>)['data']! as Map<String, Object?>;

Map<String, Object?> object(Object? value) => value! as Map<String, Object?>;

OwnSpace ownOf(Map<String, Object?> data) => SpaceProfile.fromJson(data, own: true).own!;

/// [data] with a made-up signed link on every object, as the real answers put one on rows and cards.
Object? withLinks(Object? node) => switch (node) {
  final Map<String, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries) key: withLinks(value),
    'uri': signedLink,
  },
  final List<Object?> list => [for (final item in list) withLinks(item)],
  _ => node,
};

String bangumiAnswer({Object? count, Object? hasNext, required List<Object?> rows}) => jsonEncode({
  'code': 0,
  'message': '0',
  'ttl': 1,
  'data': {'count': ?count, 'has_next': ?hasNext, 'item': rows},
});

List<Object?> bangumiRows(int length, {int from = 42000}) => [
  for (var index = 0; index < length; index++) {'param': '${from + index}', 'title': '番$index'},
];

void main() {
  late FakeHTTP http;
  late BiliClient client;
  late MemorySink sink;

  setUp(() {
    http = FakeHTTP();
    sink = MemorySink();
    client =
        BiliClient(
            transport: http,
            cookies: CookieJar({'SESSDATA': 'MADE-UP-SESSION', 'bili_jct': 'MADE-UP-CSRF', 'buvid3': 'b3'}),
            now: () => testNow,
            logger: Logger(session: 'test')..add(sink),
          )
          ..appToken = token
          ..appBuvid = 'XYDEVICE';
    http.routes[spacePath] = (200, OwnSpaceFixtures.space);
    http.routes[bangumiPath] = (200, OwnSpaceFixtures.bangumiLast);
  });

  group('requests', () {
    Map<String, String> sent(String path) {
      final query = http.query(http.requestsTo(path).single);
      return Map.of(query)..removeWhere((key, _) => key == 'appkey' || key == 'ts' || key == 'sign');
    }

    test('the own space and 追番 carry the app token with the Android parameters, signed', () async {
      await client.ownSpace(mid: 20000001);
      await client.spaceBangumi(mid: 20000001, page: 2);
      expect(sent(spacePath), {...androidParams, 'vmid': '20000001', 'access_key': 'ACCESS'});
      expect(sent(bangumiPath), {...androidParams, 'vmid': '20000001', 'pn': '2', 'ps': '20', 'access_key': 'ACCESS'});
      expect(http.requests, hasLength(2));
      for (final request in http.requests) {
        expect(request.method, 'GET');
        expect(request.url.scheme, 'https');
        expect(request.url.host, 'app.bilibili.com');
        final query = http.query(request);
        expect(query['appkey'], androidKey);
        expect(query['ts'], ts);
        final unsigned = request.url.query.split('&').where((pair) => !pair.startsWith('sign=')).join('&');
        expect(query['sign'], MD5.hex(unsigned + androidSecret), reason: request.url.path);
        expect(request.headers['buvid'], 'XYDEVICE');
      }
    });

    test("carry none of the account's cookies or csrf", () async {
      await client.ownSpace(mid: 20000001);
      await client.spaceBangumi(mid: 20000001, page: 1);
      for (final request in http.requests) {
        expect(request.headers.keys.map((name) => name.toLowerCase()), isNot(contains('cookie')));
        expect(http.query(request), isNot(contains('csrf')));
        expect(request.url.toString(), isNot(contains('MADE-UP')));
      }
    });

    test('without the app token nothing is sent', () async {
      client.appToken = null;
      await expectLater(client.ownSpace(mid: 20000001), throwsA(BiliError.noAppToken));
      await expectLater(client.spaceBangumi(mid: 20000001, page: 1), throwsA(BiliError.noAppToken));
      expect(http.requests, isEmpty);
    });

    test('a rejected token is reported, then the call throws', () async {
      http.routes[spacePath] = (200, OwnSpaceFixtures.notLoggedIn);
      http.routes[bangumiPath] = (200, OwnSpaceFixtures.notLoggedIn);
      final rejected = <String>[];
      client.onAppTokenRejected = rejected.add;
      const error = BiliError.api(code: -101, message: '账号未登录');
      await expectLater(client.ownSpace(mid: 20000001), throwsA(error));
      await expectLater(client.spaceBangumi(mid: 20000001, page: 1), throwsA(error));
      expect(rejected, ['ACCESS', 'ACCESS']);
    });

    test('the token never reaches the log', () async {
      await client.ownSpace(mid: 20000001);
      await client.spaceBangumi(mid: 20000001, page: 1);
      final log = sink.events.map((event) => event.encode()).join('\n');
      expect(sink.events, isNotEmpty);
      expect(log, isNot(contains('ACCESS')));
      expect(log, isNot(contains('access_key')));
    });
  });

  group('the own space', () {
    test('reads the level, the experience, the frame and the 大 badge', () async {
      final profile = await client.ownSpace(mid: 20000001);
      expect(profile.mid, 20000001);
      expect(profile.level, 5);
      final own = profile.own!;
      expect(own.exp, 14805);
      expect(own.nextExp, 28800);
      expect(own.pendant, 'https://i0.hdslb.com/bfs/garb/made-up/pendant.png');
      expect(own.vipBadge, isTrue);
    });

    test('next_exp reads "--" at the top level, which is 0', () {
      final data = dataOf(OwnSpaceFixtures.space);
      object(object(data['card'])['level_info'])['next_exp'] = '--';
      expect(ownOf(data).nextExp, 0);
      expect(ownOf(data).exp, 14805);
    });

    test('a vip without the badge, or without avatar_subscript, has no 大', () {
      for (final subscript in [0, 2, null]) {
        final data = dataOf(OwnSpaceFixtures.space);
        object(object(data['card'])['vip'])['avatar_subscript'] = subscript;
        expect(ownOf(data).vipBadge, isFalse, reason: '$subscript');
      }
    });

    test('the banner is the first collection item, its label the title over a number in the last colour', () async {
      final profile = await client.ownSpace(mid: 20000001);
      final own = profile.own!;
      expect(own.banner, 'https://i0.hdslb.com/bfs/garb/made-up/top.png');
      expect(profile.banner, 'https://i0.hdslb.com/bfs/space/made-up/plain-banner.png');
      final label = own.bannerLabel!;
      expect(label.title, '测试星座 金牛座');
      expect(label.subtitle, 'NO.000067');
      expect(label.subtitleColor, 0x80F5D4A6);
    });

    test("the banner falls back to the item's cover when it has no default image", () {
      final data = dataOf(OwnSpaceFixtures.space);
      final top = object(object(object(data['images'])['collection_top_simple'])['top']);
      final first = object((top['result']! as List<Object?>).first);
      object(object(first['item'])['image'])['default_image'] = '';
      expect(ownOf(data).banner, 'https://i0.hdslb.com/bfs/garb/made-up/top-cover.png');
      first.remove('item');
      expect(ownOf(data).banner, 'https://i0.hdslb.com/bfs/garb/made-up/top-cover.png');
    });

    test("the label's colour: #RRGGBB is opaque, a bad or missing one is white (null), the text stays", () {
      SpaceBannerLabel? labelWith(Object? colors) {
        final data = dataOf(OwnSpaceFixtures.space);
        final top = object(object(object(data['images'])['collection_top_simple'])['top']);
        final title = object(object((top['result']! as List<Object?>).first)['title']);
        title['sub_title_color_format'] = colors;
        return ownOf(data).bannerLabel;
      }

      expect(
        labelWith({
          'colors': ['#80F5D4A6', '#F5D4A6'],
        })!.subtitleColor,
        0xFFF5D4A6,
      );
      expect(
        labelWith({
          'colors': ['#F5D4A6', 'gold'],
        })!.subtitleColor,
        isNull,
      );
      expect(labelWith({'colors': <Object?>[]})!.subtitleColor, isNull);
      expect(labelWith({'colors': 'none'})!.subtitleColor, isNull);
      expect(labelWith(null)!.subtitleColor, isNull);
      expect(labelWith(null)!.title, '测试星座 金牛座');
      expect(labelWith(null)!.subtitle, 'NO.000067');
    });

    test('an item without a title has no label, but keeps its picture', () {
      final data = dataOf(OwnSpaceFixtures.space);
      final top = object(object(object(data['images'])['collection_top_simple'])['top']);
      object(object((top['result']! as List<Object?>).first)['title'])['title'] = '';
      expect(ownOf(data).bannerLabel, isNull);
      expect(ownOf(data).banner, 'https://i0.hdslb.com/bfs/garb/made-up/top.png');
    });

    test('without collection_top_simple, no banner and no label', () {
      final own = ownOf(dataOf(SpaceFixtures.profile));
      expect(own.banner, isNull);
      expect(own.bannerLabel, isNull);
      final empty = dataOf(OwnSpaceFixtures.space);
      object(object(object(empty['images'])['collection_top_simple'])['top'])['result'] = <Object?>[];
      expect(ownOf(empty).banner, isNull);
      expect(ownOf(empty).bannerLabel, isNull);
    });

    test('收藏: folders by media_id with count, cover and the private flag (is_public 1)', () async {
      final favourites = (await client.ownSpace(mid: 20000001)).own!.favourites;
      expect(favourites.count, 3);
      expect(
        favourites.items.map((folder) => (folder.id, folder.title, folder.cover, folder.count, folder.isPrivate)),
        [
          (3000001, '默认收藏夹', 'https://i0.hdslb.com/bfs/archive/made-up/fav1.jpg', 25, false),
          (3000002, '私密收藏夹', '', 2, true),
        ],
        reason: 'a folder without its media_id is dropped',
      );
    });

    test('追番: seasons by param, with the official progress line', () async {
      final bangumi = (await client.ownSpace(mid: 20000001)).own!.bangumi;
      expect(bangumi.count, 6);
      expect(bangumi.items.map((season) => (season.seasonId, season.title, season.progress)), [
        (40001, '完结番', '全12话'),
        (40002, '连载番', '更新至7话'),
        (40003, '特别篇', '更新至SP'),
        (40004, '刚开播', '连载中'),
        (40005, '未开播', '即将开播'),
      ], reason: 'a season without its param is dropped');
      expect(bangumi.items.map((season) => season.cover).take(2), [
        'https://i0.hdslb.com/bfs/bangumi/made-up/s1.jpg',
        'https://i0.hdslb.com/bfs/bangumi/made-up/s2.jpg',
      ]);
      expect(bangumi.items.last.cover, '');
    });

    test('a finished season counts its episodes as a number too, and without a count has no line', () {
      final data = dataOf(OwnSpaceFixtures.space);
      final rows = object(data['season'])['item']! as List<Object?>;
      object(rows[0])['total_count'] = 24;
      object(rows[1])
        ..['finish'] = 1
        ..remove('total_count');
      final items = ownOf(data).bangumi.items;
      expect(items[0].progress, '全24话');
      expect(items[1].progress, '');
    });

    test('最近投币 and 最近点赞: their counts and videos, a course dropped', () async {
      final own = (await client.ownSpace(mid: 20000001)).own!;
      expect(own.coins.count, 8);
      expect(own.coins.items.map((video) => (video.aid, video.bvid, video.title, video.cover)), [
        (100000000000501, 'BV1madeup0501', '投币视频', 'https://i0.hdslb.com/bfs/archive/made-up/coin1.jpg'),
      ]);
      expect(own.likes.count, 20);
      expect(own.likes.items.map((video) => video.aid), [100000000000601, 100000000000602]);
    });

    test('最近投币/点赞 previews without bvid or duration: the BV from the aid, the length as seconds; why one dropped', () {
      final data = dataOf(OwnSpaceFixtures.space)
        ..['coin_archive'] = {
          'count': 13,
          'item': [
            {'title': '没有BV', 'param': '170001', 'goto': 'av', 'length': '1:02:03'},
            {'title': '没有goto', 'aid': 170001, 'duration': 12},
            {'title': '课程', 'param': '170002', 'goto': 'cheese'},
          ],
        }
        ..['like_archive'] = {
          'count': 600,
          'item': [
            {'title': '没有编号'},
          ],
        };
      final own = ownOf(data);
      expect(own.coins.items.map((video) => (video.bvid, video.duration)), [('BV17x411w7KC', 3723), ('BV17x411w7KC', 12)]);
      expect(own.coins.dropped, 'not a video: cheese');
      expect(own.likes.items, isEmpty);
      expect(own.likes.dropped, 'missing param');
      expect(ownOf(dataOf(OwnSpaceFixtures.space)).likes.dropped, isNull);
    });

    test('拥有的个性装扮: at most 3 cards, each with its number and colours, and the total', () async {
      final own = (await client.ownSpace(mid: 20000001)).own!;
      expect(own.garbs.count, 4);
      expect(own.garbTotal, 7779);
      expect(
        own.garbs.items.map((card) => (card.title, card.image, card.fansNumber, card.numberColor, card.maskColor)),
        [
          ('测试装扮一', 'https://i0.hdslb.com/bfs/garb/made-up/dress1.png', '000067', 0xFFB0A07A, 0xFF5A4632),
          ('测试装扮二', 'https://i0.hdslb.com/bfs/garb/made-up/dress2.png', '12', null, null),
          ('测试装扮三', 'https://i0.hdslb.com/bfs/garb/made-up/dress3.png', '', null, null),
        ],
        reason: 'the card without a picture is dropped, the fourth past the three',
      );
    });

    test("a section is hidden when setting's flag is false or 0, shown when true or 1 or missing", () async {
      final own = (await client.ownSpace(mid: 20000001)).own!;
      expect(own.favourites.hidden, isTrue, reason: 'fav_video 0');
      expect(own.bangumi.hidden, isFalse, reason: 'bangumi true');
      expect(own.coins.hidden, isFalse, reason: 'coins_video 1');
      expect(own.likes.hidden, isTrue, reason: 'likes_video false');
      expect(own.garbs.hidden, isFalse, reason: 'dress_up 1');

      final data = dataOf(OwnSpaceFixtures.space)
        ..['setting'] = {'fav_video': true, 'bangumi': 0, 'coins_video': false};
      final changed = ownOf(data);
      expect(changed.favourites.hidden, isFalse);
      expect(changed.bangumi.hidden, isTrue);
      expect(changed.coins.hidden, isTrue);
      expect(changed.likes.hidden, isFalse, reason: 'missing');
      expect(changed.garbs.hidden, isFalse, reason: 'missing');

      final unset = ownOf(dataOf(OwnSpaceFixtures.space)..remove('setting'));
      expect(
        [unset.favourites, unset.bangumi, unset.coins, unset.likes, unset.garbs].map((section) => section.hidden),
        everyElement(isFalse),
      );
    });

    test('odd fields each cost only themselves', () {
      final profile = SpaceProfile.fromJson(dataOf(OwnSpaceFixtures.spaceOdd), own: true);
      expect(profile.name, '奇怪本人');
      expect(profile.level, 6);
      final own = profile.own!;
      expect(own.exp, 0);
      expect(own.nextExp, 0);
      expect(own.pendant, isNull, reason: 'an empty image is no frame');
      expect(own.vipBadge, isTrue, reason: 'avatar_subscript as a string');
      expect(own.banner, isNull);
      expect(own.bannerLabel, isNull, reason: 'a number without a title');
      expect([own.favourites.count, own.bangumi.count, own.coins.count, own.likes.count], [0, 0, 2, 0]);
      expect([...own.favourites.items, ...own.bangumi.items, ...own.coins.items, ...own.likes.items], isEmpty);
      expect(own.garbs.count, 1);
      expect(own.garbTotal, 7779);
      final card = own.garbs.items.single;
      expect(
        (card.title, card.image, card.fansNumber, card.numberColor, card.maskColor),
        ('', 'https://i0.hdslb.com/bfs/garb/made-up/odd.png', '', null, null),
      );
      expect(
        [own.favourites, own.bangumi, own.coins, own.likes, own.garbs].map((section) => section.hidden),
        everyElement(isFalse),
        reason: 'a setting that is not an object hides nothing',
      );
    });

    test('an answer without any extra still decodes, with every default', () {
      final own = ownOf({
        'card': {'mid': 1, 'name': '空'},
      });
      expect(
        (own.exp, own.nextExp, own.pendant, own.vipBadge, own.banner, own.bannerLabel, own.garbTotal),
        (0, 0, null, false, null, null, 0),
      );
      for (final section in [own.favourites, own.bangumi, own.coins, own.likes, own.garbs]) {
        expect((section.count, section.items.length, section.hidden), (0, 0, false));
      }
    });

    test('the signed links on rows and cards are never kept', () {
      final own = ownOf(withLinks(dataOf(OwnSpaceFixtures.space))! as Map<String, Object?>);
      final strings = [
        own.pendant,
        own.banner,
        own.bannerLabel?.title,
        own.bannerLabel?.subtitle,
        for (final folder in own.favourites.items) ...[folder.title, folder.cover],
        for (final season in own.bangumi.items) ...[season.title, season.cover, season.progress],
        for (final video in [...own.coins.items, ...own.likes.items]) ...kept(video),
        for (final card in own.garbs.items) ...[card.title, card.image, card.fansNumber],
      ];
      expect(own.favourites.items, hasLength(2));
      expect(own.bangumi.items, hasLength(5));
      expect(own.garbs.items, hasLength(3));
      for (final text in strings.nonNulls) {
        expect(text, isNot(contains('MADE-UP-SIGNED')));
        expect(text, isNot(startsWith('bilibili://')));
      }
    });
  });

  group("anyone else's space", () {
    test('reads no extras, and parses the rest exactly as the own space does', () async {
      final data = dataOf(OwnSpaceFixtures.space);
      final other = SpaceProfile.fromJson(data);
      final own = SpaceProfile.fromJson(dataOf(OwnSpaceFixtures.space), own: true);
      expect(other.own, isNull);
      expect(own.own, isNotNull);
      List<Object?> shown(SpaceProfile profile) => [
        profile.mid,
        profile.name,
        profile.face,
        profile.sign,
        profile.level,
        profile.vip,
        profile.fans,
        profile.following,
        profile.banner,
        profile.defaultTab,
        for (final tab in profile.tabs) (tab.kind, tab.title),
        for (final chip in profile.chips) (chip.kind, chip.title),
      ];
      expect(shown(other), shown(own));
    });

    test("space() never asks for or reads the extras, even of the account's own space", () async {
      client.appToken = null;
      final profile = await client.space(mid: 20000001);
      expect(profile.own, isNull);
      expect(profile.name, '测试本人');
      expect(http.query(http.requestsTo(spacePath).single), isNot(contains('access_key')));
    });
  });

  group('追番 pages', () {
    test('go on while the rows so far are fewer than the count', () async {
      http.routes[bangumiPath] = (200, bangumiAnswer(count: 45, rows: bangumiRows(20)));
      final first = await client.spaceBangumi(mid: 20000001, page: 1);
      expect(first.items, hasLength(20));
      expect(first.items.first.seasonId, 42000);
      expect(first.total, 45);
      expect(first.hasMore, isTrue);

      http.routes[bangumiPath] = (200, OwnSpaceFixtures.bangumiLast);
      final last = await client.spaceBangumi(mid: 20000001, page: 3);
      expect(last.items.map((season) => (season.seasonId, season.progress)), [
        (41041, '全24话'),
        (41042, '更新至3话'),
        (41043, '即将开播'),
        (41044, '即将开播'),
      ]);
      expect(last.total, 45);
      expect(last.hasMore, isFalse, reason: '40 + 5 rows, the dropped one counted');

      final second = await client.spaceBangumi(mid: 20000001, page: 2);
      expect(second.hasMore, isTrue, reason: '20 + 5 of 45');
    });

    test('a page of rows that all fail to decode still moves on', () async {
      final bad = [
        for (var index = 0; index < 20; index++) <String, Object?>{'title': '坏$index'},
      ];
      http.routes[bangumiPath] = (200, bangumiAnswer(count: 45, rows: bad));
      final page = await client.spaceBangumi(mid: 20000001, page: 1);
      expect(page.items, isEmpty);
      expect(page.hasMore, isTrue);
    });

    test('an empty page ends the list, whatever the count', () async {
      http.routes[bangumiPath] = (200, bangumiAnswer(count: 45, rows: []));
      final page = await client.spaceBangumi(mid: 20000001, page: 2);
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('without a count, pages go on until one comes back empty', () async {
      http.routes[bangumiPath] = (200, bangumiAnswer(rows: bangumiRows(3)));
      final page = await client.spaceBangumi(mid: 20000001, page: 4);
      expect(page.total, isNull);
      expect(page.hasMore, isTrue);
      http.routes[bangumiPath] = (200, bangumiAnswer(rows: []));
      expect((await client.spaceBangumi(mid: 20000001, page: 5)).hasMore, isFalse);
    });

    test('a has_next wins over the count', () async {
      http.routes[bangumiPath] = (200, bangumiAnswer(count: 45, hasNext: false, rows: bangumiRows(20)));
      expect((await client.spaceBangumi(mid: 20000001, page: 1)).hasMore, isFalse);
      http.routes[bangumiPath] = (200, bangumiAnswer(count: 45, hasNext: true, rows: bangumiRows(5)));
      expect((await client.spaceBangumi(mid: 20000001, page: 3)).hasMore, isTrue);
    });

    test('decoded alone, a page counts as the first of 20', () {
      expect(SpaceBangumiPage.fromJson(dataOf(OwnSpaceFixtures.bangumiLast)).hasMore, isTrue);
      expect(SpaceBangumiPage.fromJson(dataOf(OwnSpaceFixtures.bangumiLast), page: 9).hasMore, isFalse);
    });

    test('an odd count reads as none', () {
      final page = SpaceBangumiPage.fromJson({'count': '--', 'item': bangumiRows(2)});
      expect(page.total, isNull);
      expect(page.hasMore, isTrue);
      expect(SpaceBangumiPage.fromJson({'count': 2, 'item': 'none'}).items, isEmpty);
    });

    test('an error code throws the API error', () async {
      http.routes[bangumiPath] = (200, SpaceFixtures.notFound);
      await expectLater(
        client.spaceBangumi(mid: 20000001, page: 1),
        throwsA(const BiliError.api(code: -404, message: '啥都木有')),
      );
    });
  });
}
