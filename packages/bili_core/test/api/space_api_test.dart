import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/src/api/md5.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'space_fixtures.dart';

const spacePath = '/x/v2/space';
const archivePath = '/x/v2/space/archive/cursor';
const seasonPath = '/x/v2/space/season/videos';
const seriesPath = '/x/v2/space/series';

const androidKey = 'dfca71928277209b';
const androidSecret = 'b5475a8825547a4fc26c7d518eaaa02e';
const androidUserAgent =
    'Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com) os/android model/android mobi_app/android build/8430300 '
    'channel/master innerVer/8430300 osVer/15 network/2';
// The clock makeTestClient fixes.
const ts = '1702204169';

const androidParams = {
  'build': '8430300',
  'version': '8.43.0',
  'c_locale': 'zh_CN',
  'channel': 'master',
  'mobi_app': 'android',
  'platform': 'android',
  's_locale': 'zh_CN',
  'statistics': '{"appId":1,"platform":3,"version":"8.43.0","abtest":""}',
};

const seasonChip = SpaceChip(kind: SpaceChipKind.season, title: '测试合集', seasonId: 2001);
const seriesChip = SpaceChip(kind: SpaceChipKind.series, title: '测试系列', seriesId: 3001);

/// A made-up stand-in for the signed play link the real answers carry.
const signedLink = 'bilibili://video/100000000000001?player_preload=MADE-UP-SIGNED-PLAY-LINK';

DateTime local(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

/// Every string a video keeps.
List<String> kept(SpaceVideo video) => [video.bvid, video.title, video.cover, video.publishedText, ...video.badges];

/// The answer with [signedLink] in every place the real one carries a link: rows, the 播放全部 button, the cards
/// under the header and the tag lines (badges get one too, which does no harm).
String withLinks(String fixture) {
  const linked = ['bvid', 'text', 'module_type', 'text_color'];
  Object? walk(Object? node) => switch (node) {
    final Map<String, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries) key: walk(value),
      if (linked.any(map.containsKey)) ...{'uri': signedLink, 'player_preload': signedLink, 'url': signedLink},
    },
    final List<Object?> list => [for (final item in list) walk(item)],
    _ => node,
  };
  return jsonEncode(walk(jsonDecode(fixture)));
}

void main() {
  late FakeHTTP fakeHTTP;
  late BiliClient client;
  late MemorySink sink;

  setUp(() {
    fakeHTTP = FakeHTTP();
    sink = MemorySink();
    client = BiliClient(
      transport: fakeHTTP,
      cookies: CookieJar({'SESSDATA': 'MADE-UP-SESSION', 'bili_jct': 'MADE-UP-CSRF', 'buvid3': 'b3', 'buvid4': 'b4'}),
      now: () => testNow,
      logger: Logger(session: 'test')..add(sink),
    );
    fakeHTTP.routes[spacePath] = (200, SpaceFixtures.profile);
    fakeHTTP.routes[archivePath] = (200, SpaceFixtures.archiveFirst);
    fakeHTTP.routes[seasonPath] = (200, SpaceFixtures.season);
    fakeHTTP.routes[seriesPath] = (200, SpaceFixtures.series);
  });

  HTTPRequest only(String path) {
    final requests = fakeHTTP.requestsTo(path);
    expect(requests, hasLength(1));
    return requests.single;
  }

  Future<void> callEach() async {
    await client.space(mid: 10000001);
    await client.spaceVideos(mid: 10000001, order: SpaceOrder.latest);
    await client.spaceChipVideos(mid: 10000001, chip: seasonChip);
    await client.spaceChipVideos(mid: 10000001, chip: seriesChip);
  }

  group('requests', () {
    test("are signed with the Android app's key pair over the query as sent", () async {
      await callEach();
      expect(fakeHTTP.requests, hasLength(4));
      for (final request in fakeHTTP.requests) {
        final query = fakeHTTP.query(request);
        expect(query['appkey'], androidKey);
        expect(query['ts'], ts);
        final unsigned = request.url.query.split('&').where((pair) => !pair.startsWith('sign=')).join('&');
        expect(query['sign'], MD5.hex(unsigned + androidSecret), reason: request.url.path);
      }
    });

    test("go to the app host with the Android app's parameters and headers", () async {
      await callEach();
      Map<String, String> sent(String path) {
        final query = fakeHTTP.query(only(path));
        return Map.of(query)..removeWhere((key, _) => key == 'appkey' || key == 'ts' || key == 'sign');
      }

      expect(sent(spacePath), {...androidParams, 'vmid': '10000001'});
      expect(sent(archivePath), {
        ...androidParams,
        'vmid': '10000001',
        'ps': '20',
        'qn': '80',
        'order': 'pubdate',
        'sort': 'desc',
      });
      expect(sent(seasonPath), {
        ...androidParams,
        'vmid': '10000001',
        'season_id': '2001',
        'ps': '20',
        'qn': '32',
        'sort': 'desc',
      });
      expect(sent(seriesPath), {
        ...androidParams,
        'vmid': '10000001',
        'series_id': '3001',
        'ps': '20',
        'qn': '32',
        'sort': 'desc',
      });
      for (final request in fakeHTTP.requests) {
        expect(request.method, 'GET');
        expect(request.url.scheme, 'https');
        expect(request.url.host, 'app.bilibili.com');
        expect(request.headers['User-Agent'], androidUserAgent);
        expect(request.headers['bili-http-engine'], 'cronet');
      }
    });

    test('最多播放 sends order=click', () async {
      await client.spaceVideos(mid: 10000001, order: SpaceOrder.mostPlayed);
      expect(fakeHTTP.query(only(archivePath))['order'], 'click');
    });

    test("carry none of the account's cookies, csrf or token, though the client holds them", () async {
      await callEach();
      for (final request in fakeHTTP.requests) {
        expect(request.headers.keys.map((name) => name.toLowerCase()), isNot(contains('cookie')));
        final query = fakeHTTP.query(request);
        for (final name in ['csrf', 'access_key', 'SESSDATA', 'bili_jct']) {
          expect(query, isNot(contains(name)));
        }
        expect(request.url.toString(), isNot(contains('MADE-UP')));
      }
    });

    test('a chip without its id, or one that is not a list, is refused before any call', () async {
      for (final chip in const [
        SpaceChip(kind: SpaceChipKind.season, title: '没有编号'),
        SpaceChip(kind: SpaceChipKind.series, title: '没有编号'),
        SpaceChip(kind: SpaceChipKind.video, title: '视频'),
        SpaceChip(kind: SpaceChipKind.article, title: '图文'),
      ]) {
        await expectLater(client.spaceChipVideos(mid: 1, chip: chip), throwsArgumentError);
      }
      expect(fakeHTTP.requests, isEmpty);
    });
  });

  group('paging', () {
    test("投稿 pages by the last row's aid, even when that row is dropped, until has_next is false", () async {
      final first = await client.spaceVideos(mid: 10000001, order: SpaceOrder.latest);
      expect(first.items.map((video) => video.aid), [
        100000000000001,
        100000000000002,
      ], reason: 'the course and the row without a bvid are dropped');
      expect(first.hasMore, isTrue);
      expect(first.next, '100000000000003');
      expect(first.total, 45);

      fakeHTTP.routes[archivePath] = (200, SpaceFixtures.archiveLast);
      final last = await client.spaceVideos(mid: 10000001, order: SpaceOrder.latest, next: first.next);
      expect(fakeHTTP.query(fakeHTTP.requestsTo(archivePath).last)['aid'], '100000000000003');
      expect(fakeHTTP.query(fakeHTTP.requestsTo(archivePath).first), isNot(contains('aid')));
      expect(last.items.single.bvid, 'BV1madeup0045');
      expect(last.hasMore, isFalse);
      expect(last.next, isNull);
    });

    test('has_next with no rows ends the list rather than asking again from the same place', () async {
      fakeHTTP.routes[archivePath] = (200, SpaceFixtures.archiveEmptyButMore);
      final page = await client.spaceVideos(mid: 10000001, order: SpaceOrder.latest, next: '100000000000003');
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.next, isNull);
    });

    test("a 系列 pages by its next until next is 0", () async {
      final first = await client.spaceChipVideos(mid: 10000001, chip: seriesChip);
      expect(first.items.map((video) => video.bvid), ['BV1madeup0201', 'BV1madeup0202']);
      expect(first.hasMore, isTrue);
      expect(first.next, '97');
      expect(first.total, 115);

      fakeHTTP.routes[seriesPath] = (200, SpaceFixtures.seriesEnd);
      final last = await client.spaceChipVideos(mid: 10000001, chip: seriesChip, next: first.next);
      final query = fakeHTTP.query(fakeHTTP.requestsTo(seriesPath).last);
      expect(query['next'], '97');
      expect(query, isNot(contains('aid')));
      expect(last.items.single.bvid, 'BV1madeup0315');
      expect(last.hasMore, isFalse);
      expect(last.next, isNull);
    });

    test('a 合集 comes whole', () async {
      final page = await client.spaceChipVideos(mid: 10000001, chip: seasonChip);
      expect(page.items.map((video) => video.bvid), ['BV1madeup0101', 'BV1madeup0102']);
      expect(page.hasMore, isFalse);
      expect(page.next, isNull);
      expect(page.total, isNull);
    });
  });

  group('profile', () {
    test('decodes the card, counts, banner and cards under the header', () async {
      final profile = await client.space(mid: 10000001);
      expect(profile.mid, 10000001);
      expect(profile.name, '测试UP主');
      expect(profile.face, 'https://i0.hdslb.com/bfs/face/made-up/face.jpg');
      expect(profile.sign, '这是编的简介');
      expect(profile.level, 6);
      expect(profile.seniorMember, isTrue);
      expect(profile.vip, isTrue);
      expect(profile.vipLabel, 'https://i0.hdslb.com/bfs/vip/made-up/label.png');
      expect(profile.official, SpaceOfficial.person);
      expect(profile.officialTitle, 'bilibili UP主认证：测试认证');
      expect(profile.fans, 7037);
      expect(profile.following, 2);
      expect(profile.likes, 174000);
      expect(profile.videoCount, 45);
      expect(profile.banner, 'https://i0.hdslb.com/bfs/space/made-up/banner.jpg');
      expect(profile.chargeable, isTrue);
      expect(profile.orders, [SpaceOrder.latest, SpaceOrder.mostPlayed]);
      expect(profile.entries.map((entry) => (entry.kind, entry.title, entry.note)), [
        (SpaceEntryKind.shop, '小店', '1件商品'),
        (SpaceEntryKind.charge, '充电', '5人充电'),
      ]);
      expect(profile.tagLines.map((line) => (line.text, line.icon, line.link)), [
        ('IP属地：测试省', 'https://i0.hdslb.com/bfs/space/made-up/ip.png', false),
        ('测试大学', 'https://i0.hdslb.com/bfs/space/made-up/school.png', false),
      ]);
    });

    test('an organisation is verified blue', () async {
      fakeHTTP.routes[spacePath] = (200, SpaceFixtures.profileOrganisation);
      final profile = await client.space(mid: 10000003);
      expect(profile.mid, 10000003);
      expect(profile.official, SpaceOfficial.organisation);
      expect(profile.officialTitle, 'bilibili 机构认证：测试机构');
    });

    test('a tag line with a link of its own is marked, the link not kept', () async {
      fakeHTTP.routes[spacePath] = (200, withLinks(SpaceFixtures.profile));
      final profile = await client.space(mid: 10000001);
      expect(profile.tagLines.map((line) => line.link), [isTrue, isTrue]);
      expect(profile.tagLines.map((line) => line.text), ['IP属地：测试省', '测试大学']);
    });

    test('missing, empty or odd fields fall back without failing the space', () async {
      fakeHTTP.routes[spacePath] = (200, SpaceFixtures.profileBare);
      final profile = await client.space(mid: 10000002);
      expect(profile.mid, 10000002);
      expect(profile.name, '空空UP主');
      expect(profile.face, '');
      expect(profile.sign, '');
      expect(profile.level, 2);
      expect(profile.seniorMember, isFalse);
      expect(profile.vip, isFalse);
      expect(profile.vipLabel, isNull);
      expect(profile.official, SpaceOfficial.none);
      expect(profile.officialTitle, '');
      expect(profile.fans, 0);
      expect(profile.following, 0);
      expect(profile.likes, 0);
      expect(profile.videoCount, 0);
      expect(profile.banner, isNull, reason: 'an empty imgUrl draws the default banner');
      expect(profile.tagLines, isEmpty);
      expect(profile.entries, isEmpty);
      expect(profile.chargeable, isFalse);
      expect(profile.tabs, isEmpty);
      expect(profile.chips, isEmpty);
      expect(profile.orders, [SpaceOrder.latest, SpaceOrder.mostPlayed]);
    });

    test('a space without its card fails to decode', () async {
      fakeHTTP.routes[spacePath] = (200, SpaceFixtures.profileWithoutCard);
      await expectLater(client.space(mid: 10000004), throwsA(isA<BiliDecodingError>()));
    });
  });

  group('tabs', () {
    test("keep the uploader's tabs in order, the unknown ones as other with their titles", () async {
      final profile = await client.space(mid: 10000001);
      expect(profile.tabs.map((tab) => (tab.kind, tab.title)), [
        (SpaceTabKind.home, '主页'),
        (SpaceTabKind.dynamic, '动态'),
        (SpaceTabKind.contribute, '投稿'),
        (SpaceTabKind.shop, '小店'),
        (SpaceTabKind.favourite, '收藏'),
        (SpaceTabKind.other, '追番'),
      ]);
    });

    test('the default tab: video, contribute and archive are 投稿; home and dynamic stay; anything else is 投稿', () {
      SpaceTabKind opening(String? tab) => SpaceProfile.fromJson({
        'card': {'mid': 1, 'name': 'x'},
        'default_tab': ?tab,
      }).defaultTab;

      expect(opening('video'), SpaceTabKind.contribute);
      expect(opening('contribute'), SpaceTabKind.contribute);
      expect(opening('archive'), SpaceTabKind.contribute);
      expect(opening('home'), SpaceTabKind.home);
      expect(opening('dynamic'), SpaceTabKind.dynamic);
      expect(opening('bangumi'), SpaceTabKind.contribute);
      expect(opening(null), SpaceTabKind.contribute);
    });
  });

  test("投稿's chips: 视频, 图文 from opus or article, 合集 and 系列 with their ids, the rest as other", () async {
    final profile = await client.space(mid: 10000001);
    expect(profile.chips.map((chip) => (chip.kind, chip.title, chip.seasonId, chip.seriesId)), [
      (SpaceChipKind.video, '视频', null, null),
      (SpaceChipKind.article, '图文', null, null),
      (SpaceChipKind.article, '专栏', null, null),
      (SpaceChipKind.other, '音频', null, null),
      (SpaceChipKind.season, '测试合集', 2001, null),
      (SpaceChipKind.series, '测试系列', null, 3001),
      (SpaceChipKind.other, '充电专属', null, null),
    ], reason: 'a 合集 without its id and a chip without a title are dropped');
  });

  test('videos keep what is drawn, with defaults for what is missing', () async {
    final page = await client.spaceVideos(mid: 10000001, order: SpaceOrder.latest);
    final full = page.items.first;
    expect(full.aid, 100000000000001);
    expect(full.bvid, 'BV1madeup0001');
    expect(full.title, '测试视频一');
    expect(full.cover, 'https://i0.hdslb.com/bfs/archive/made-up/cover1.jpg');
    expect(full.duration, 1235);
    expect(full.play, 121);
    expect(full.danmaku, 7);
    expect(full.published, local(1702200000));
    expect(full.publishedText, '15小时前');
    expect(full.badges, ['合作'], reason: 'badges without text are dropped');

    final bare = page.items[1];
    expect(bare.aid, 100000000000002, reason: 'param as a number');
    expect(bare.title, '');
    expect(bare.cover, 'https://i0.hdslb.com/bfs/archive/made-up/cover2.jpg');
    expect(bare.duration, 0);
    expect(bare.play, 0);
    expect(bare.danmaku, 0);
    expect(bare.published, isNull);
    expect(bare.publishedText, '');
    expect(bare.badges, isEmpty);
  });

  test('pictures come back as https', () async {
    final profile = await client.space(mid: 10000001);
    final videos = await client.spaceVideos(mid: 10000001, order: SpaceOrder.latest);
    final season = await client.spaceChipVideos(mid: 10000001, chip: seasonChip);
    final pictures = [
      profile.face,
      profile.vipLabel!,
      profile.banner!,
      for (final line in profile.tagLines) line.icon!,
      for (final video in [...videos.items, ...season.items]) video.cover,
    ];
    expect(pictures, hasLength(9));
    for (final picture in pictures) {
      expect(picture, startsWith('https://'));
    }
  });

  test('an error code throws the API error', () async {
    fakeHTTP.routes[spacePath] = (200, SpaceFixtures.notFound);
    fakeHTTP.routes[archivePath] = (200, SpaceFixtures.notFound);
    fakeHTTP.routes[seriesPath] = (200, SpaceFixtures.notFound);
    const error = BiliError.api(code: -404, message: '啥都木有');
    await expectLater(client.space(mid: 10000005), throwsA(error));
    await expectLater(client.spaceVideos(mid: 10000005, order: SpaceOrder.latest), throwsA(error));
    await expectLater(client.spaceChipVideos(mid: 10000005, chip: seriesChip), throwsA(error));
  });

  test("the signed play links in the answers are never kept or logged", () async {
    fakeHTTP.routes[spacePath] = (200, withLinks(SpaceFixtures.profile));
    fakeHTTP.routes[archivePath] = (200, withLinks(SpaceFixtures.archiveFirst));
    fakeHTTP.routes[seasonPath] = (200, withLinks(SpaceFixtures.season));
    fakeHTTP.routes[seriesPath] = (200, withLinks(SpaceFixtures.series));
    expect(fakeHTTP.routes.values.every((route) => route.$2.contains(signedLink)), isTrue);

    final profile = await client.space(mid: 10000001);
    final pages = [
      await client.spaceVideos(mid: 10000001, order: SpaceOrder.latest),
      await client.spaceChipVideos(mid: 10000001, chip: seasonChip),
      await client.spaceChipVideos(mid: 10000001, chip: seriesChip),
    ];
    final strings = [
      profile.name,
      profile.face,
      profile.sign,
      profile.vipLabel,
      profile.officialTitle,
      profile.banner,
      for (final line in profile.tagLines) ...[line.text, line.icon],
      for (final entry in profile.entries) ...[entry.title, entry.note],
      for (final tab in profile.tabs) tab.title,
      for (final chip in profile.chips) chip.title,
      for (final page in pages) ...[page.next, for (final video in page.items) ...kept(video)],
    ];
    expect(pages.expand((page) => page.items), hasLength(6));
    for (final text in strings.nonNulls) {
      expect(text, isNot(contains('MADE-UP-SIGNED')));
      expect(text, isNot(startsWith('bilibili://')));
    }
    final log = sink.events.map((event) => event.encode()).join('\n');
    expect(sink.events, hasLength(4));
    for (final leak in ['MADE-UP', 'player_preload', 'bilibili://', 'sign=', '?']) {
      expect(log, isNot(contains(leak)));
    }
  });
}
