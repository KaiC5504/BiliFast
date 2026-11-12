import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'app_signer_test.dart' show iphoneKey, makeClient, signedBy;
import 'fake_http.dart';
import 'official_identity_test.dart' show iphoneParams, iphoneUserAgent;
import 'report_api_test.dart' show tokenOf;

const storyPath = '/x/v2/feed/index/story';

// Every id, name, link and track value is made up. The shape follows docs/reference/official-iphone-calls.md: the
// entered video first, a live room, an ad, a video with ad_info, a video stored rotated, one without a bvid, one
// without a cid, and a 合集 episode whose ids are only at the top level.
const storyAnswer = r'''
{"code":0,"message":"0","ttl":1,"data":{"config":{"swipe_opacity":{"other_ui_alpha_percent":10}},"items":[
{"goto":"vertical_av","bvid":"BV1Te411a1aA","title":"进来的视频",
 "cover":"https://i0.hdslb.com/bfs/archive/story-0001.jpg","ff_cover":"https://i0.hdslb.com/bfs/archive/ff-0001.jpg",
 "duration":78,"dimension":{"width":1080,"height":1920,"rotate":0},
 "player_args":{"aid":90000001,"cid":190000001,"type":"av"},
 "owner":{"mid":601,"name":"UP主甲","face":"https://i0.hdslb.com/bfs/face/story-face-0001.jpg","fans":12345,
  "relation":{"status":2,"is_follow":1,"is_followed":0}},
 "stat":{"view":104000,"like":5123,"reply":88,"coin":77,"favorite":66,"share":55,"danmaku":44},
 "track_id":"track-story-0001","report_flow_data":"{\"flow_card_type\":\"story\"}","idx":1763100001,
 "desc":"简介","pubdate":1763000000},
{"goto":"vertical_live","title":"直播间","room_id":5001},
{"goto":"vertical_ad_av","bvid":"BV1Te411b2bB","player_args":{"aid":90000002,"cid":190000002}},
{"goto":"vertical_av","bvid":"BV1Te411c3cC","ad_info":{"creative_id":1},"player_args":{"aid":90000003,"cid":190000003}},
{"goto":"vertical_av","bvid":"BV1Te411d4dD","title":"转过的","cover":"https://i0.hdslb.com/bfs/archive/story-0004.jpg",
 "duration":"61","dimension":{"width":1920,"height":1080,"rotate":1},
 "player_args":{"aid":90000004,"cid":190000004},
 "owner":{"mid":"602","name":"UP主乙","relation":{"status":1}},
 "stat":{"view":"--","like":3},"track_id":"","report_flow_data":"","idx":"1763100002"},
{"goto":"vertical_av","player_args":{"aid":90000005,"cid":190000005},"title":"没有BV号"},
{"goto":"vertical_av","bvid":"BV1Te411f6fF","player_args":{"aid":90000006},"title":"没有cid"},
{"goto":"vertical_av","bvid":"BV1Te411g7gG","aid":90000007,"cid":190000007,"title":"合集里的",
 "dimension":{"width":1920,"height":1080},"owner":{"mid":603,"name":"UP主丙","relation":{"status":4}},
 "season":{"title":"合集名","current_index":3,"total":12}},
"not an object"
]}}''';

const entry = PlaySource(fromSpmid: 'tm.recommend.0.0', from: '7', trackId: 'track-entry', flowData: '{}');

/// The fields every page sends beside the identity's common ones.
const everyPage = {
  'client_attr': '1',
  'collection_second_feed_iaa': '1',
  'contain': '0',
  'extra_content': '{"story_video_bg_play_listen":"0"}',
  'fnval': '17364',
  'fnver': '0',
  'force_host': '0',
  'fourk': '1',
  'material_no': '0',
  'network': 'wifi',
  'player_extra_content': '{"short_edge":"1320","long_edge":"2868"}',
  'player_net': '1',
  'product_id': '',
  'product_type': '',
  'qn': '120',
  'qn_policy': '0',
  'room_id': '0',
  'server_name': '',
  'soft_fnval': '0',
  'sp_id': '',
  'statistics': '{"appId":1,"platform":1,"version":"9.18.0"}',
  'teenagers_age': '16',
  'video_mode': '1',
  'voice_balance': '1',
};

void main() {
  late FakeHTTP http;
  late BiliClient client;

  setUp(() {
    http = FakeHTTP()..routes = {storyPath: (200, storyAnswer)};
    client = makeClient(http)
      ..appToken = tokenOf(OfficialIdentity.iphone)
      ..appBuvid = 'XYDEVICE';
  });

  Map<String, String> asked([int index = 0]) => http.query(http.requestsTo(storyPath)[index]);

  group('the request', () {
    test("the first page is the iPhone app's whole: the entered video, where 竖屏 was entered from, cold, signed by "
        'the iPhone pair', () async {
      await client.storyFeed(aid: 90000001, cid: 190000001, page: 1, entry: entry, trackId: 'track-entry');
      final request = http.requestsTo(storyPath).single;
      expect(request.method, 'GET');
      expect(request.url.host, 'app.bilibili.com');
      final query = asked();
      expect(query['sign'], signedBy(AppSigner.iphone, query));
      expect(
        query
          ..remove('ts')
          ..remove('sign'),
        {
          ...iphoneParams,
          ...everyPage,
          'access_key': 'ACCESS',
          'appkey': iphoneKey,
          'aid': '90000001',
          'cid': '190000001',
          'trackid': 'track-entry',
          'display_id': '1',
          'pull': '1',
          'from': '7',
          'from_spmid': 'tm.recommend.0.0',
          'spmid': 'main.ugc-video-detail-vertical.0.0',
          'auto_play': '0',
          'open_event': 'cold',
          'epid': '0',
          'ogv_style': '0',
        },
      );
    });

    test('a later page counts on, pull 0, and leaves out where 竖屏 was entered from', () async {
      await client.storyFeed(aid: 90000001, cid: 190000001, page: 3, entry: entry, trackId: 'track-entry');
      final query = asked();
      expect(query['sign'], signedBy(AppSigner.iphone, query));
      expect(
        query
          ..remove('ts')
          ..remove('sign'),
        {
          ...iphoneParams,
          ...everyPage,
          'access_key': 'ACCESS',
          'appkey': iphoneKey,
          'aid': '90000001',
          'cid': '190000001',
          'trackid': 'track-entry',
          'display_id': '3',
          'pull': '0',
        },
      );
    });

    test('no trackid without one; an entry with no from code sends none, its from_spmid as it is', () async {
      await client.storyFeed(aid: 1, cid: 2, page: 1, entry: PlaySource.unknown);
      final query = asked();
      expect(query.containsKey('trackid'), isFalse);
      expect(query.containsKey('from'), isFalse);
      expect(query['from_spmid'], '');
      expect(query['spmid'], 'main.ugc-video-detail-vertical.0.0');
    });

    test("the headers are the iPhone identity's, with no cookies", () async {
      await client.storyFeed(aid: 1, cid: 2, page: 1, entry: entry);
      expect(http.requestsTo(storyPath).single.headers, {
        'User-Agent': iphoneUserAgent,
        'Referer': BiliClient.referer,
        'Accept': 'application/json',
        'app-key': 'iphone',
        'env': 'prod',
        'buvid': 'XYDEVICE',
        'session_id': client.appSessionId,
      });
    });

    test('without a token nothing is sent', () async {
      client.appToken = null;
      await expectLater(client.storyFeed(aid: 1, cid: 2, page: 1, entry: entry), throwsA(BiliError.noAppToken));
      expect(http.requests, isEmpty);
    });

    test('under an Android token nothing is sent: the feed is only known for the iPhone app', () async {
      client.appToken = tokenOf(OfficialIdentity.android);
      await expectLater(client.storyFeed(aid: 1, cid: 2, page: 1, entry: entry), throwsStateError);
      expect(http.requests, isEmpty);
    });

    test("a refusal throws Bilibili's code, and a refused token is reported", () async {
      http.routes[storyPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
      final rejected = <String>[];
      client.onAppTokenRejected = rejected.add;
      await expectLater(
        client.storyFeed(aid: 1, cid: 2, page: 2, entry: entry),
        throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -101)),
      );
      expect(rejected, ['ACCESS']);
    });
  });

  group('the answer', () {
    test('keeps only videos with a bvid and a cid: live rooms, ads and anything with ad_info are dropped', () async {
      final items = await client.storyFeed(aid: 90000001, cid: 190000001, page: 1, entry: entry);
      expect(items.map((item) => item.bvid), ['BV1Te411a1aA', 'BV1Te411d4dD', 'BV1Te411g7gG']);
    });

    test('an item decodes its video, shape, uploader, counts and track data', () async {
      final [entered, ...] = await client.storyFeed(aid: 90000001, cid: 190000001, page: 1, entry: entry);
      expect(entered.aid, 90000001);
      expect(entered.cid, 190000001);
      expect(entered.title, '进来的视频');
      expect(entered.cover, 'https://i0.hdslb.com/bfs/archive/story-0001.jpg');
      expect(entered.firstFrame, 'https://i0.hdslb.com/bfs/archive/ff-0001.jpg');
      expect(entered.duration, 78);
      expect((entered.width, entered.height), (1080, 1920));
      expect(entered.upright, isTrue);
      expect(entered.ownerMid, 601);
      expect(entered.ownerName, 'UP主甲');
      expect(entered.ownerFace, 'https://i0.hdslb.com/bfs/face/story-face-0001.jpg');
      expect(entered.ownerFans, 12345);
      expect(entered.following, isTrue);
      expect(
        [entered.views, entered.likes, entered.replies, entered.coins, entered.favourites, entered.shares],
        [104000, 5123, 88, 77, 66, 55],
      );
      expect(entered.danmaku, 44);
      expect(entered.trackId, 'track-story-0001');
      expect(entered.flowData, '{"flow_card_type":"story"}');
      expect(entered.idx, 1763100001);
      expect(entered.seasonTitle, isNull);
      expect(entered.seasonIndex, isNull);
      expect(entered.seasonTotal, isNull);
    });

    test('a file stored rotated is shown with width and height swapped; numbers sent as text still read', () async {
      final [_, rotated, _] = await client.storyFeed(aid: 1, cid: 2, page: 2, entry: entry);
      expect((rotated.width, rotated.height), (1080, 1920));
      expect(rotated.upright, isTrue);
      expect(rotated.duration, 61);
      expect(rotated.ownerMid, 602);
      expect(rotated.idx, 1763100002);
      expect(rotated.views, 0, reason: 'a hidden count');
      expect(rotated.likes, 3);
      expect(rotated.following, isFalse, reason: 'status 1 is not following');
      expect(rotated.trackId, isNull, reason: 'empty');
      expect(rotated.flowData, isNull, reason: 'empty');
      expect(rotated.firstFrame, isNull);
      expect(rotated.ownerFace, '');
    });

    test("a 合集 episode names its season; ids at the top level are read; 互相关注 is following", () async {
      final [_, _, episode] = await client.storyFeed(aid: 1, cid: 2, page: 2, entry: entry);
      expect(episode.aid, 90000007);
      expect(episode.cid, 190000007);
      expect(episode.seasonTitle, '合集名');
      expect(episode.seasonIndex, 3);
      expect(episode.seasonTotal, 12);
      expect(episode.upright, isFalse);
      expect(episode.following, isTrue);
      expect(episode.trackId, isNull, reason: 'missing');
      expect(episode.idx, isNull);
    });

    test('an item without a bvid or a cid throws DecodeError; one that is not an object too', () {
      final data = (jsonDecode(storyAnswer) as Map<String, Object?>)['data']! as Map<String, Object?>;
      final [..., noBvid, noCid, _, notObject] = data['items']! as List<Object?>;
      expect(() => StoryItem.fromJson(noBvid), throwsA(isA<DecodeError>()));
      expect(() => StoryItem.fromJson(noCid), throwsA(isA<DecodeError>()));
      expect(() => StoryItem.fromJson(notObject), throwsA(isA<DecodeError>()));
    });

    test("the uploader's 大会员 is the item's own vip: an active one with a type, else not", () {
      Map<String, Object?> item(Map<String, Object?>? vip) => {
        'goto': 'vertical_av',
        'bvid': 'BV1xx411c7mD',
        'player_args': {'aid': 1, 'cid': 2},
        'owner': {'mid': 3, 'name': 'up'},
        'vip': ?vip,
      };
      expect(StoryItem.fromJson(item({'type': 2, 'status': 1})).ownerVip, isTrue);
      expect(StoryItem.fromJson(item({'type': 0, 'status': 0})).ownerVip, isFalse);
      expect(StoryItem.fromJson(item({'type': 1, 'status': 0})).ownerVip, isFalse);
      expect(StoryItem.fromJson(item(null)).ownerVip, isFalse);
    });

    test('an answer without items is empty', () async {
      http.routes[storyPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{"items":null}}');
      expect(await client.storyFeed(aid: 1, cid: 2, page: 2, entry: entry), isEmpty);
      http.routes[storyPath] = (200, '{"code":0,"message":"0","ttl":1,"data":null}');
      expect(await client.storyFeed(aid: 1, cid: 2, page: 3, entry: entry), isEmpty);
    });
  });

  test('one log line per answer names the item gotos only: never an id, a link, the track data or the token', () async {
    final logs = MemorySink();
    final logged = BiliClient(
      transport: http,
      cookies: CookieJar(const {}),
      now: () => testNow,
      logger: Logger(session: 'test')..add(logs),
    )..appToken = tokenOf(OfficialIdentity.iphone);
    await logged.storyFeed(aid: 90000001, cid: 190000001, page: 1, entry: entry, trackId: 'track-entry');
    final line = logs.events.singleWhere((event) => event.msg == 'story item types');
    expect(
      (line.f['items'] as LogString?)?.value,
      'vertical_av vertical_live vertical_ad_av vertical_av/ad vertical_av vertical_av vertical_av vertical_av',
    );
    expect(
      line.f['undecoded']?.toJson(),
      3,
      reason: 'no bvid, no cid, not an object; the live room and the ads were dropped, not undecoded',
    );
    http.routes[storyPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
    await expectLater(logged.storyFeed(aid: 1, cid: 2, page: 2, entry: entry), throwsA(isA<BiliAPIError>()));
    for (final event in logs.events) {
      final text = event.encode();
      for (final secret in ['track-', 'flow_card_type', 'ACCESS', 'REFRESH', '9000000', 'BV1', 'hdslb', 'https://']) {
        expect(text, isNot(contains(secret)), reason: event.msg);
      }
    }
  });

  test("PlaySource.story gives the doc's labels: the vertical page, default-value, the entry's from_spmid, the "
      "item's own track data, and story-single for the entered video, story-series after", () {
    final entered = PlaySource.story(entry: entry, entered: true, trackId: 'track-item', flowData: '{"a":1}');
    expect(entered.spmid, 'main.ugc-video-detail-vertical.0.0');
    expect(entered.from, 'default-value');
    expect(entered.fromSpmid, 'tm.recommend.0.0');
    expect(entered.trackId, 'track-item');
    expect(entered.flowData, '{"a":1}');
    expect(entered.historySource, 'story-single');
    final swiped = PlaySource.story(entry: entry, entered: false);
    expect(swiped.historySource, 'story-series');
    expect(swiped.trackId, isNull, reason: "the entry's track data stays with the entry");
    expect(swiped.flowData, isNull);
    expect(entry.historySource, isNull, reason: 'the video page names no source');
    expect(entry.spmid, 'united.player-video-detail.0.0');
  });
}
