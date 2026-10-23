import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'app_signer_test.dart' show makeClient;
import 'fake_http.dart';
import 'official_api_test.dart' show token;

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
 "can_play":1,"like_button":{"aid":90000007,"count":5123,"show_count":true,"event":"like"},"is_atten":0,
 "share_plane":{"title":"大卡片","bvid":"BV1Te411d4dD","aid":90000007},
 "three_point_v2":[{"title":"我不想看","type":"dislike","reasons":[
  {"id":1,"name":"不感兴趣","toast":"将减少相似内容推荐"}]}]}
]}}''';

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
 "like_button":{"count":0,"show_count":0}},
{"card_goto":"av","param":"90000013","can_play":1,"player_args":{"aid":90000013}},
{"card_goto":"inline_av_v2","param":"90000014","can_play":1,"player_args":{"aid":90000014},"ad_info":{}},
{"card_goto":"inline_av_v2","param":"90000015","can_play":1,"player_args":{"aid":90000015}}
]}}''');
    final cards = await client.officialFeed(index: 1);
    expect(cards.map((card) => card.aid), [90000012, 90000015, 90000011, 90000013]);
    expect(cards[0].big, const FeedBig(likes: 0, showLikes: false));
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

    expect(big.big, const FeedBig(likes: 5123, showLikes: true));
    expect(big.bvid, 'BV1Te411d4dD', reason: "the big card's bvid is only in share_plane");
    expect(big.reason, '5千点赞', reason: 'from rcmd_reason_style');
    expect(big.cid, 190000007);
    expect(big.duration, 95);
    expect(big.viewsText, '3.1万');
    expect(big.danmaku, 88);
    expect(big.ownerName, 'UP主丁');
    expect(big.ownerMid, 604);
    expect(big.isVertical, isFalse);
    expect(big.dislike?.goto, 'inline_av_v2', reason: "不感兴趣 names the card by its own card_goto");
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

  group('不感兴趣', () {
    test('sends one reason or one feedback with the card, signed, as a GET', () async {
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
      expect(query['sign'], isNotNull);
      expect(reason.headers['Cookie'], isNull);
      expect(http.query(feedback)['feedback_id'], '9');
      expect(http.query(feedback).containsKey('reason_id'), isFalse);
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
