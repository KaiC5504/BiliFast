import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'app_signer_test.dart' show iphoneKey, makeClient, signedBy;
import 'fake_http.dart';
import 'official_api_test.dart' show token;
import 'official_identity_test.dart' show iphoneParams, iphoneUserAgent;
import 'space_api_test.dart' show androidKey, androidParams, androidUserAgent;

const feedPath = '/x/v2/feed/index';
const dislikePath = '/x/feed/dislike';
const cancelPath = '/x/feed/dislike/cancel';

// Every id, name and link is made up. The shape follows PiliPlus's RcmdVideoItemAppModel: an ad, a live room, a
// 番剧, a banner and an unplayable card around three videos, one without its bvid, and last, as Android lists it, the
// big inline card (its fields as KaiC's PC check of 2026-10-24 named them).
const officialFeed = r'''
{"code":0,"message":"0","ttl":1,"data":{"items":[
{"card_type":"banner_v8","card_goto":"banner","goto":"banner","param":"","can_play":1,"banner_item":[]},
{"card_type":"small_cover_v2","card_goto":"av","goto":"av","param":"90000001","bvid":"BV1Te411a1aA",
 "cover":"https://i0.hdslb.com/bfs/archive/official-0001.jpg","title":"官方推荐一",
 "uri":"bilibili://video/90000001?player_width=1920&player_height=1080&player_rotate=0",
 "args":{"up_id":601,"up_name":"UP主甲","tid":17,"tname":"单机游戏"},
 "player_args":{"aid":90000001,"cid":190000001,"type":"av","duration":412},
 "cover_left_text_1":"10.4万","cover_left_text_2":"174","cover_right_text":"6:52","rcmd_reason":"1千点赞","can_play":1,
 "three_point_v2":[
  {"title":"添加至稍后再看","type":"watch_later"},
  {"title":"反馈","subtitle":"(选择后将优化首页此类内容)","type":"feedback","reasons":[
   {"id":2,"name":"色情低俗","toast":"将优化首页此类内容"},
   {"id":1,"name":"恐怖血腥","toast":"将优化首页此类内容"},
   {"id":4,"name":"标题党/封面党","toast":"将优化首页此类内容"},
   {"id":9,"name":"该内容已推荐过","toast":"将优化首页此类内容"},
   {"name":"没有id"}]},
  {"title":"我不想看","subtitle":"(选择后将减少相似内容推荐)","type":"dislike","reasons":[
   {"id":4,"name":"UP主:UP主甲","toast":"将减少相似内容推荐"},
   {"id":3,"name":"频道:单机游戏","toast":"将减少相似内容推荐"},
   {"id":1,"name":"不感兴趣","toast":"将减少相似内容推荐"}]}]},
{"card_type":"small_cover_v2","card_goto":"ad_av","goto":"av","param":"90000002","can_play":1,"title":"广告",
 "player_args":{"aid":90000002}},
{"card_type":"small_cover_v2","card_goto":"av","goto":"av","param":"90000003","can_play":1,"title":"带广告信息",
 "ad_info":{"creative_id":1},"player_args":{"aid":90000003}},
{"card_type":"small_cover_v2","card_goto":"live","goto":"live","param":"5001","can_play":1,"title":"直播间"},
{"card_type":"small_cover_v2","card_goto":"bangumi","goto":"bangumi","param":"6001","can_play":1,"title":"番剧"},
{"card_type":"small_cover_v2","card_goto":"av","goto":"av","param":"90000004","can_play":0,"title":"不能播",
 "player_args":{"aid":90000004}},
{"card_type":"small_cover_v2","card_goto":"av","goto":"av","param":"170001",
 "cover":"https://i0.hdslb.com/bfs/archive/official-0005.jpg","title":"没有BV号的竖屏",
 "uri":"bilibili://video/170001?player_width=1080&player_height=1920&player_rotate=0",
 "args":{"up_id":602,"up_name":"UP主乙"},"player_args":{"aid":170001,"cid":190000005,"duration":15},
 "cover_left_text_1":"1.2亿","cover_left_text_2":"-","rcmd_reason":"竖屏","can_play":1},
{"card_type":"small_cover_v2","card_goto":"av","goto":"av","param":"90000006","bvid":"BV1Te411c3cC","can_play":1,
 "title":"没有三点","player_args":{"aid":90000006,"cid":190000006,"duration":61},"args":{"up_id":603,"up_name":"UP主丙"},
 "cover_left_text_1":"5432","cover_left_text_2":"12"},
{"card_type":"large_cover_v9","card_goto":"inline_av_v2","goto":"av","param":"90000007",
 "cover":"https://i0.hdslb.com/bfs/archive/official-0007.jpg","title":"大卡片",
 "uri":"bilibili://video/90000007?player_width=1920&player_height=1080&player_rotate=0",
 "args":{"up_id":604,"up_name":"UP主丁","tid":17,"tname":"单机游戏","aid":90000007,"is_follow":0},
 "player_args":{"aid":90000007,"cid":190000007,"type":"av","duration":95,"report_history":1},
 "up_args":{"up_id":604,"up_name":"UP主丁","up_face":"https://i0.hdslb.com/bfs/face/official-face-0007.jpg",
  "selected":0},
 "idx":1,"track_id":"track-0007","talk_back":"大卡片","official_icon":0,
 "cover_left_text_1":"3.1万","cover_left_icon_1":1,"cover_left_text_2":"88","cover_left_icon_2":2,
 "cover_right_text":"1:35","rcmd_reason_style":{"text":"5千点赞","text_color":"#FB7299","icon_url":""},
 "can_play":1,"like_button":{"aid":90000007,"count":5123,"show_count":true,"selected":1,"event":"like"},"is_atten":0,
 "share_plane":{"title":"大卡片","bvid":"BV1Te411d4dD","aid":90000007},
 "three_point_v2":[{"title":"我不想看","type":"dislike","reasons":[
  {"id":1,"name":"不感兴趣","toast":"将减少相似内容推荐"}]}]}
]}}''';

// As the iPhone identity's answer lists them (docs/reference/official-iphone-calls.md): the big card first, each video
// with its idx and track data, which the uri repeats. The second card names them only in its uri, the third names
// them empty, the last not at all. Every id and value is made up.
const iphoneFeed = r'''
{"code":0,"message":"0","ttl":1,"data":{"items":[
{"card_type":"large_cover_v9","card_goto":"inline_av_v2","goto":"av","param":"90000021","can_play":1,
 "uri":"bilibili://video/90000021?player_width=1920&player_height=1080&trackid=track-uri-0021&report_flow_data=%7B%7D",
 "player_args":{"aid":90000021,"cid":190000021,"duration":95},
 "idx":1763000021,"track_id":"track-0021","report_flow_data":"{\"flow_card_type\":\"big\"}"},
{"card_type":"small_cover_v2","card_goto":"av","goto":"av","param":"90000022","can_play":1,
 "uri":"bilibili://video/90000022?trackid=track-uri-0022&report_flow_data=%7B%22flow_card_type%22%3A%22uri%22%7D",
 "player_args":{"aid":90000022,"cid":190000022,"duration":61},"idx":1763000020},
{"card_type":"small_cover_v2","card_goto":"av","goto":"av","param":"90000023","can_play":1,
 "uri":"bilibili://video/90000023?trackid=&report_flow_data=",
 "player_args":{"aid":90000023},"idx":1763000019,"track_id":"","report_flow_data":""},
{"card_type":"small_cover_v2","card_goto":"av","goto":"av","param":"90000024","can_play":1,
 "player_args":{"aid":90000024}}
]}}''';

final iphoneToken = AppToken(
  accessToken: 'ACCESS',
  refreshToken: 'REFRESH',
  mid: 7,
  expiresAt: DateTime.utc(2027, 4, 1),
  identity: OfficialIdentity.iphone,
);

/// The Android feed's own fields as they went out before identities, less `idx` and `pull`.
const androidFeedFields = {
  'auto_refresh_state': '1',
  'autoplay_card': '11',
  'build': '8430300',
  'c_locale': 'zh_CN',
  'channel': 'master',
  'column': '2',
  'device': 'phone',
  'device_name': 'Pixel 9',
  'device_type': '0',
  'disable_rcmd': '0',
  'flush': '8',
  'fnval': '976',
  'fnver': '0',
  'force_host': '2',
  'fourk': '1',
  'guidance': '1',
  'https_url_req': '1',
  'inline_danmu': '2',
  'inline_sound': '1',
  'mobi_app': 'android',
  'network': 'wifi',
  'platform': 'android',
  'player_net': '1',
  'qn': '32',
  'recsys_mode': '0',
  's_locale': 'zh_CN',
  'splash_id': '',
  'statistics': '{"appId":1,"platform":3,"version":"8.43.0","abtest":""}',
  'voice_balance': '0',
};

/// Every header of the Android feed's request, as before identities: its own over the Android app's.
const androidFeedHeaders = {
  'User-Agent':
      'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd mobi_app/android_hd '
      'build/2001100 channel/master innerVer/2001100 osVer/15 network/2',
  'Referer': BiliClient.referer,
  'Accept': 'application/json',
  'bili-http-engine': 'cronet',
  'buvid': 'XYDEVICE',
  'fp_local': '1111111111111111111111111111111111111111111111111111111111111111',
  'fp_remote': '1111111111111111111111111111111111111111111111111111111111111111',
  'session_id': '11111111',
  'env': 'prod',
  'app-key': 'android_hd',
  'x-bili-trace-id': '11111111111111111111111111111111:1111111111111111:0:0',
  'x-bili-aurora-eid': '',
  'x-bili-aurora-zone': '',
};

void main() {
  late FakeHTTP http;
  late BiliClient client;

  setUp(() {
    http = FakeHTTP();
    client = makeClient(http)
      ..appToken = token
      ..appBuvid = 'XYDEVICE';
  });

  test('without the app token the feed sends nothing', () async {
    http.routes[feedPath] = (200, officialFeed);
    client.appToken = null;
    await expectLater(client.officialFeed(index: 0), throwsA(BiliError.noAppToken));
    expect(http.requests, isEmpty);
  });

  test("each page's card types are logged in order, names only: never an id, a cover or a link", () async {
    final events = _Events();
    final logged = BiliClient(
      transport: http,
      cookies: CookieJar({'SESSDATA': 'sess', 'bili_jct': 'TOKEN', 'buvid3': 'b3'}),
      now: () => testNow,
      logger: Logger(session: 'test')..add(events),
    )
      ..appToken = token
      ..appBuvid = 'XYDEVICE';
    http.routes[feedPath] = (200, officialFeed);
    await logged.officialFeed(index: 0);
    final line = events.events.singleWhere((event) => event.msg == 'feed card types');
    expect(
      (line.f['cards'] as LogString?)?.value,
      'banner/banner_v8 av/small_cover_v2 ad_av/small_cover_v2 av/small_cover_v2/ad live/small_cover_v2 '
      'bangumi/small_cover_v2 av/small_cover_v2 av/small_cover_v2 av/small_cover_v2 inline_av_v2/large_cover_v9',
    );
    final text = line.encode();
    for (final secret in ['hdslb', 'bilibili://', '90000001', 'BV1', token]) {
      expect(text, isNot(contains(secret)));
    }
  });

  test('keeps only playable videos: ads, live, 番剧, banners and unplayable cards are dropped', () async {
    http.routes[feedPath] = (200, officialFeed);
    final cards = await client.officialFeed(index: 0);
    expect(cards.map((card) => card.aid), [90000007, 90000001, 170001, 90000006]);
  });

  test("each page's big cards come first, as the iPhone shows them, the rest in order", () async {
    http.routes[feedPath] = (200, r'''
{"code":0,"message":"0","ttl":1,"data":{"items":[
{"card_goto":"av","param":"90000011","can_play":1,"player_args":{"aid":90000011}},
{"card_goto":"inline_av_v2","param":"90000012","can_play":1,"player_args":{"aid":90000012},
 "like_button":{"count":0,"show_count":0,"selected":true}},
{"card_goto":"av","param":"90000013","can_play":1,"player_args":{"aid":90000013}},
{"card_goto":"inline_av_v2","param":"90000014","can_play":1,"player_args":{"aid":90000014},"ad_info":{}},
{"card_goto":"inline_av_v2","param":"90000015","can_play":1,"player_args":{"aid":90000015}}
]}}''');
    final cards = await client.officialFeed(index: 1);
    expect(cards.map((card) => card.aid), [90000012, 90000015, 90000011, 90000013]);
    expect(cards[0].big, const FeedBig(likes: 0, showLikes: false, liked: true), reason: 'selected as a bool');
    expect(cards[1].big, const FeedBig(likes: 0, showLikes: false), reason: 'a big card without like_button');
    expect(cards[2].big, isNull);
  });

  test('a card decodes ids, counts as shown, owner, reason and shape', () async {
    http.routes[feedPath] = (200, officialFeed);
    final [big, first, vertical, plain] = await client.officialFeed(index: 0);
    expect(first.bvid, 'BV1Te411a1aA');
    expect(first.cid, 190000001);
    expect(first.title, '官方推荐一');
    expect(first.cover, 'https://i0.hdslb.com/bfs/archive/official-0001.jpg');
    expect(first.duration, 412);
    expect(first.viewsText, '10.4万');
    expect(first.views, 104000);
    expect(first.danmakuText, '174');
    expect(first.danmaku, 174);
    expect(first.ownerName, 'UP主甲');
    expect(first.ownerMid, 601);
    expect(first.reason, '1千点赞');
    expect(first.isVertical, isFalse);
    expect(first.big, isNull);

    expect(vertical.bvid, 'BV17x411w7KC', reason: "av170001's published BV id");
    expect(vertical.isVertical, isTrue);
    expect(vertical.reason, isNull, reason: '竖屏 is the shape, which the card shows by itself');
    expect(vertical.views, 120000000);
    expect(vertical.danmakuText, '-');
    expect(vertical.danmaku, 0);

    expect(plain.dislike, isNull);
    expect(plain.viewsText, '5432');

    expect(big.big, const FeedBig(likes: 5123, showLikes: true, liked: true), reason: 'selected as 0/1');
    expect(big.bvid, 'BV1Te411d4dD', reason: "the big card's bvid is only in share_plane");
    expect(big.reason, '5千点赞', reason: 'from rcmd_reason_style');
    expect(big.cid, 190000007);
    expect(big.duration, 95);
    expect(big.viewsText, '3.1万');
    expect(big.danmaku, 88);
    expect(big.ownerName, 'UP主丁');
    expect(big.ownerMid, 604);
    expect(big.isVertical, isFalse);
    expect(big.dislike?.goto, 'av', reason: "不感兴趣 names the big card by its item's goto, not inline_av_v2");
    expect(big.dislike?.id, 90000007);
  });

  test("three_point_v2's reasons: the video, the uploader, the tiles and 该内容已推荐过", () async {
    http.routes[feedPath] = (200, officialFeed);
    final dislike = (await client.officialFeed(index: 0))[1].dislike!;
    expect(dislike.goto, 'av');
    expect(dislike.id, 90000001);
    expect(dislike.video, const FeedReason(id: 1, name: '不感兴趣', kind: FeedReasonKind.dislike, toast: '将减少相似内容推荐'));
    expect(dislike.uploader?.id, 4);
    expect(dislike.uploader?.kind, FeedReasonKind.dislike);
    expect(dislike.tiles.map((reason) => reason.name), ['色情低俗', '恐怖血腥', '标题党/封面党']);
    expect(
      dislike.repeated,
      const FeedReason(id: 9, name: '该内容已推荐过', kind: FeedReasonKind.feedback, toast: '将优化首页此类内容'),
    );
    expect(dislike.feedbacks.length, 4, reason: 'a reason without an id is dropped');
  });

  test("the query is PiliPlus's as the Android phone app with the inline fields, signed, no cookies", () async {
    http.routes[feedPath] = (200, officialFeed);
    await client.officialFeed(index: 0);
    await client.officialFeed(index: 3);
    final [refresh, more] = http.requestsTo(feedPath);
    expect(refresh.url.host, 'app.bilibili.com');
    final first = http.query(refresh);
    expect(first['idx'], '0');
    expect(first['pull'], 'true');
    expect(first['disable_rcmd'], '0');
    expect(first['mobi_app'], 'android', reason: 'only the phone app is sent the big inline card');
    expect(first['device_name'], 'Pixel 9');
    expect(first['autoplay_card'], '11');
    expect(first['inline_sound'], '1');
    expect(first['inline_danmu'], '2');
    expect(first['auto_refresh_state'], '1');
    expect(first['build'], '8430300');
    expect(first['column'], '2');
    expect(first['access_key'], 'ACCESS');
    expect(first['appkey'], isNotNull);
    expect(first['sign'], isNotNull);
    expect(refresh.headers['Cookie'], isNull);
    expect(refresh.headers['buvid'], 'XYDEVICE');
    expect(refresh.headers['app-key'], 'android_hd');
    expect(http.query(more)['idx'], '3');
    expect(http.query(more)['pull'], 'false');
  });

  test("the Android identity's request is as before: firstIdx and cold change nothing in it", () async {
    http.routes[feedPath] = (200, officialFeed);
    await client.officialFeed(index: 0);
    final cards = await client.officialFeed(index: 3, firstIdx: 1763000021, cold: true);
    final [refresh, more] = http.requestsTo(feedPath);
    for (final request in [refresh, more]) {
      final query = http.query(request);
      for (final MapEntry(:key, :value) in androidFeedFields.entries) {
        expect(query[key], value, reason: key);
      }
      for (final key in ['open_event', 'login_event', 'client_attr', 'player_extra_content', 'actionKey']) {
        expect(query.containsKey(key), isFalse, reason: key);
      }
      expect(query['appkey'], androidKey);
      expect(query['sign'], signedBy(AppSigner.android, query));
      expect(request.headers, androidFeedHeaders);
    }
    expect(http.query(refresh)['idx'], '0');
    expect(http.query(refresh)['pull'], 'true');
    expect(http.query(more)['idx'], '3', reason: 'the page, not the card named');
    expect(http.query(more)['pull'], 'false');
    expect(cards.first.aid, 90000007, reason: 'the big card still moved first');
  });

  test("the iPad's query is the one asked before (38), with no inline fields; a big card keeps its place", () async {
    http.routes[feedPath] = (200, officialFeed);
    final cards = await client.officialFeed(index: 0, pad: true);
    final query = http.query(http.requestsTo(feedPath).single);
    expect(query['mobi_app'], 'android_i');
    expect(query['device_name'], 'android');
    expect(query['idx'], '0');
    expect(query['pull'], 'true');
    expect(query['access_key'], 'ACCESS');
    expect(query['sign'], isNotNull);
    for (final key in ['autoplay_card', 'inline_sound', 'inline_danmu', 'auto_refresh_state']) {
      expect(query.containsKey(key), isFalse, reason: key);
    }
    expect(cards.map((card) => card.aid), [90000001, 170001, 90000006, 90000007]);
  });

  test("a card's face comes from up_args where it is sent, '' otherwise; the official feed names no date", () async {
    http.routes[feedPath] = (200, officialFeed);
    final [big, first, ...] = await client.officialFeed(index: 0);
    expect(big.ownerFace, 'https://i0.hdslb.com/bfs/face/official-face-0007.jpg');
    expect(first.ownerFace, '');
    expect(first.published, 0);
  });

  test('a rejected token is reported and the feed throws its code', () async {
    http.routes[feedPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
    final rejected = <String>[];
    client.onAppTokenRejected = rejected.add;
    await expectLater(
      client.officialFeed(index: 0),
      throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -101)),
    );
    expect(rejected, ['ACCESS']);
  });

  test('a feed without items is empty', () async {
    http.routes[feedPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{"items":null}}');
    expect(await client.officialFeed(index: 1), isEmpty);
    http.routes[feedPath] = (200, '{"code":0,"message":"0","ttl":1,"data":null}');
    expect(await client.officialFeed(index: 2), isEmpty);
  });

  group('the iPhone identity', () {
    setUp(() => client.appToken = iphoneToken);

    Future<Map<String, String>> asked({required int index, int? firstIdx, bool cold = false, bool pad = false}) async {
      http.routes[feedPath] = (200, iphoneFeed);
      await client.officialFeed(index: index, firstIdx: firstIdx, cold: cold, pad: pad);
      return http.query(http.requestsTo(feedPath).last);
    }

    test("the launch's first page is cold: idx 0, pull 1, flush 0, open_event cold", () async {
      final query = await asked(index: 0, cold: true);
      expect(query['idx'], '0');
      expect(query['pull'], '1');
      expect(query['flush'], '0');
      expect(query['open_event'], 'cold');
    });

    test('a refresh names the first card on screen: pull 1, flush 6, open_event sent empty', () async {
      final query = await asked(index: 0, firstIdx: 1763000021);
      expect(query['idx'], '1763000021');
      expect(query['pull'], '1');
      expect(query['flush'], '6');
      expect(query['open_event'], '');
    });

    test('a refresh with no card on screen names idx 0', () async {
      final query = await asked(index: 0);
      expect(query['idx'], '0');
      expect(query['flush'], '6');
    });

    test('more below names the first card on screen too, not the page: pull 0, flush 8', () async {
      final query = await asked(index: 4, firstIdx: 1763000021);
      expect(query['idx'], '1763000021');
      expect(query['pull'], '0');
      expect(query['flush'], '8');
      expect(query['open_event'], '');
    });

    test("the whole request is the iPhone app's: the feed's own fields beside the identity's, the feed's statistics, "
        "the token and the iPhone pair's signature", () async {
      final query = await asked(index: 0, firstIdx: 1763000021);
      expect(query['sign'], signedBy(AppSigner.iphone, query));
      expect(query..remove('ts')..remove('sign'), {
        ...iphoneParams,
        'access_key': 'ACCESS',
        'appkey': iphoneKey,
        'idx': '1763000021',
        'pull': '1',
        'flush': '6',
        'open_event': '',
        'auto_refresh_state': '1',
        'autoplay_card': '11',
        'channel': 'pink_overseas',
        'client_attr': '1',
        'column': '2',
        'device_name': 'iPhone 17 Pro Max',
        'fnval': '17364',
        'fnver': '0',
        'force_host': '0',
        'fourk': '1',
        'guidance': '0',
        'https_url_req': '0',
        'inline_danmu': '2',
        'inline_sound': '1',
        'inline_sound_cold_state': '2',
        'login_event': '0',
        'network': 'wifi',
        'player_extra_content': '{"short_edge":"1320","long_edge":"2868"}',
        'player_net': '1',
        'qn': '120',
        'qn_policy': '0',
        'recsys_mode': '0',
        'soft_fnval': '0',
        'statistics': '{"appId":1,"platform":1,"version":"9.18.0"}',
        'video_mode': '1',
        'voice_balance': '1',
        'window_size_type': '1',
      });
      expect(http.requestsTo(feedPath).single.url.host, 'app.bilibili.com');
    });

    test("the headers are the identity's own, with none of the Android feed's on top and no cookies", () async {
      await asked(index: 0, firstIdx: 1763000021);
      expect(http.requestsTo(feedPath).single.headers, {
        'User-Agent': iphoneUserAgent,
        'Referer': BiliClient.referer,
        'Accept': 'application/json',
        'app-key': 'iphone',
        'env': 'prod',
        'buvid': 'XYDEVICE',
        'session_id': client.appSessionId,
      });
    });

    test('the iPad asks the same without the inline card fields', () async {
      final query = await asked(index: 0, firstIdx: 1763000021, pad: true);
      for (final key in ['autoplay_card', 'inline_danmu', 'inline_sound', 'inline_sound_cold_state']) {
        expect(query.containsKey(key), isFalse, reason: key);
      }
      expect(query['idx'], '1763000021');
      expect(query['flush'], '6');
      expect(query['auto_refresh_state'], '1');
      expect(query['device_name'], 'iPhone 17 Pro Max');
    });

    test("the answer keeps the server's order: nothing is moved first", () async {
      http.routes[feedPath] = (200, officialFeed);
      final cards = await client.officialFeed(index: 0);
      expect(cards.map((card) => card.aid), [90000001, 170001, 90000006, 90000007]);
    });

    test('no log line names a track id, the flow data or a token', () async {
      final events = _Events();
      final logged = BiliClient(
        transport: http,
        cookies: CookieJar({'SESSDATA': 'sess', 'bili_jct': 'TOKEN', 'buvid3': 'b3'}),
        now: () => testNow,
        logger: Logger(session: 'test')..add(events),
      )..appToken = iphoneToken;
      http.routes[feedPath] = (200, iphoneFeed);
      expect(await logged.officialFeed(index: 0, firstIdx: 1763000021), hasLength(4));
      http.routes[feedPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
      await expectLater(logged.officialFeed(index: 1, firstIdx: 1763000021), throwsA(isA<BiliAPIError>()));
      expect(events.events.map((event) => event.msg), containsAll(['feed card types', feedPath, 'app token rejected']));
      for (final event in events.events) {
        final text = event.encode();
        for (final secret in ['track-', 'flow_card_type', 'ACCESS', 'REFRESH']) {
          expect(text, isNot(contains(secret)), reason: event.msg);
        }
      }
    });
  });

  group("a card's idx and track data", () {
    Future<List<FeedCard>> cards([String answer = iphoneFeed]) async {
      http.routes[feedPath] = (200, answer);
      return client.officialFeed(index: 0);
    }

    test('come from the card itself, before what its uri repeats', () async {
      final big = (await cards()).first;
      expect(big.aid, 90000021);
      expect(big.idx, 1763000021);
      expect(big.trackId, 'track-0021');
      expect(big.flowData, '{"flow_card_type":"big"}');
    });

    test("come from the uri's trackid and report_flow_data when the card names none", () async {
      final card = (await cards())[1];
      expect(card.idx, 1763000020);
      expect(card.trackId, 'track-uri-0022');
      expect(card.flowData, '{"flow_card_type":"uri"}');
    });

    test('are null when empty or missing', () async {
      final [_, _, empty, missing] = await cards();
      expect(empty.idx, 1763000019);
      expect(empty.trackId, isNull);
      expect(empty.flowData, isNull);
      expect(missing.idx, isNull);
      expect(missing.trackId, isNull);
      expect(missing.flowData, isNull);
    });

    test('are part of what makes two cards equal', () async {
      final first = (await cards()).first;
      final again = (await cards()).first;
      expect(again, first);
      expect(again.hashCode, first.hashCode);
      for (final (from, to) in [
        ('"idx":1763000021', '"idx":1763000099'),
        ('"track_id":"track-0021"', '"track_id":"track-0099"'),
        (r'\"big\"', r'\"other\"'),
      ]) {
        final changed = iphoneFeed.replaceFirst(from, to);
        expect(changed, isNot(iphoneFeed));
        expect((await cards(changed)).first, isNot(first), reason: from);
      }
    });
  });

  group('不感兴趣', () {
    test("sends one reason or one feedback with the card, signed, as a GET, with PiliPlus's build and mobi_app under "
        'the Android identity', () async {
      http.routes[dislikePath] = (200, '{"code":0,"message":"0","ttl":1}');
      await client.feedDislike(goto: 'av', id: 90000001, reasonId: 1);
      await client.feedDislike(goto: 'av', id: 90000001, feedbackId: 9);
      final [reason, feedback] = http.requestsTo(dislikePath);
      expect(reason.method, 'GET');
      final query = http.query(reason);
      expect(query['goto'], 'av');
      expect(query['id'], '90000001');
      expect(query['reason_id'], '1');
      expect(query.containsKey('feedback_id'), isFalse);
      expect(query['mobi_app'], 'android');
      expect(query['build'], '1');
      expect(query['access_key'], 'ACCESS');
      expect(query['sign'], signedBy(AppSigner.android, query));
      expect(query..remove('ts')..remove('sign'), {
        ...androidParams,
        'build': '1',
        'access_key': 'ACCESS',
        'appkey': androidKey,
        'goto': 'av',
        'id': '90000001',
        'reason_id': '1',
      }, reason: 'as before identities');
      expect(reason.headers['User-Agent'], androidUserAgent);
      expect(reason.headers['Cookie'], isNull);
      expect(http.query(feedback)['feedback_id'], '9');
      expect(http.query(feedback).containsKey('reason_id'), isFalse);
    });

    test("the iPhone identity sends neither PiliPlus's build nor its mobi_app: the identity's own labels, pair and "
        'headers stand', () async {
      client.appToken = iphoneToken;
      http.routes[dislikePath] = (200, '{"code":0,"message":"0","ttl":1}');
      http.routes[cancelPath] = (200, '{"code":0,"message":"0","ttl":1}');
      await client.feedDislike(goto: 'av', id: 90000021, reasonId: 1);
      await client.feedDislikeCancel(goto: 'av', id: 90000021, reasonId: 1);
      for (final path in [dislikePath, cancelPath]) {
        final request = http.requestsTo(path).single;
        final query = http.query(request);
        expect(query['sign'], signedBy(AppSigner.iphone, query), reason: path);
        expect(query..remove('ts')..remove('sign'), {
          ...iphoneParams,
          'access_key': 'ACCESS',
          'appkey': iphoneKey,
          'goto': 'av',
          'id': '90000021',
          'reason_id': '1',
        }, reason: path);
        expect(request.headers['User-Agent'], iphoneUserAgent, reason: path);
        expect(request.headers['app-key'], 'iphone', reason: path);
        expect(request.headers['Cookie'], isNull, reason: path);
      }
    });

    test('needs exactly one of a reason and a feedback', () {
      expect(() => client.feedDislike(goto: 'av', id: 1), throwsArgumentError);
      expect(() => client.feedDislike(goto: 'av', id: 1, reasonId: 1, feedbackId: 2), throwsArgumentError);
      expect(http.requests, isEmpty);
    });

    test('cancel takes it back on its own path', () async {
      http.routes[cancelPath] = (200, '{"code":0,"message":"0","ttl":1}');
      await client.feedDislikeCancel(goto: 'av', id: 90000001, reasonId: 1);
      final query = http.query(http.requestsTo(cancelPath).single);
      expect(query['id'], '90000001');
      expect(query['reason_id'], '1');
    });

    test('without the token nothing is sent; a refusal throws', () async {
      client.appToken = null;
      await expectLater(client.feedDislike(goto: 'av', id: 1, reasonId: 1), throwsA(BiliError.noAppToken));
      await expectLater(client.feedDislikeCancel(goto: 'av', id: 1, reasonId: 1), throwsA(BiliError.noAppToken));
      expect(http.requests, isEmpty);

      client.appToken = token;
      http.routes[dislikePath] = (200, '{"code":-400,"message":"请求错误","ttl":1}');
      await expectLater(
        client.feedDislike(goto: 'av', id: 1, reasonId: 1),
        throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -400)),
      );
    });
  });

  test('counts read as the official app writes them', () {
    expect(parseCountText('174'), 174);
    expect(parseCountText('10.4万'), 104000);
    expect(parseCountText('3万'), 30000);
    expect(parseCountText('1.2亿'), 120000000);
    expect(parseCountText('-'), 0);
    expect(parseCountText(null), 0);
  });
}

final class _Events implements LogSink {
  final List<LogEvent> events = [];

  @override
  void receive(LogEvent event) => events.add(event);
}
