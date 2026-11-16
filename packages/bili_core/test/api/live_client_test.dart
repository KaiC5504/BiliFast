import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'app_signer_test.dart' show iphoneKey, signedBy;
import 'fake_http.dart';
import 'fixtures.dart';
import 'official_identity_test.dart' show iphoneParams, iphoneUserAgent, tokenOf;
import 'space_api_test.dart' show androidKey, androidParams, androidUserAgent;

const _navPath = '/x/web-interface/nav';
const _feedPath = '/xlive/app-interface/v2/index/feed';
const _areaPath = '/xlive/app-interface/v2/second/getList';
const _followingPath = '/xlive/web-ucenter/user/following';
const _playPath = '/xlive/web-room/v2/index/getRoomPlayInfo';
const _roomPath = '/xlive/web-room/v1/index/getInfoByRoom';
const _cardPath = '/x/web-interface/card';
const _danmuPath = '/xlive/web-room/v1/index/getDanmuInfo';
const _historyPath = '/xlive/web-room/v1/dM/gethistory';
const _superChatPath = '/av/v1/SuperChat/getMessageList';
const _rankPath = '/xlive/general-interface/v1/rank/queryContributionRank';
const _guardPath = '/xlive/app-room/v2/guardTab/topListNew';
const _emotePath = '/xlive/web-ucenter/v2/emoticon/GetEmoticons';
const _sendPath = '/msg/send';
const _likePath = '/xlive/app-ucenter/v1/like_info_v3/like/likeReportV3';
const _enterPath = '/xlive/web-room/v1/index/roomEntryAction';

const _live = 'api.live.bilibili.com';
const _mixinKey = 'ea1db124af3c7062474693fa704f4ff8';
const _ok = '{"code":0,"message":"0","ttl":1,"data":{}}';

String _fixture(String name) => File('test/fixtures/live/$name.json').readAsStringSync();

void main() {
  late FakeHTTP http;
  late BiliClient client;
  late MemorySink sink;

  setUp(() {
    http = FakeHTTP()..routes[_navPath] = (200, Fixtures.navLoggedIn);
    sink = MemorySink();
    client = BiliClient(
      transport: http,
      cookies: CookieJar({'SESSDATA': 'MADE-UP-SESSION', 'bili_jct': 'MADE-UP-CSRF', 'buvid3': 'b3', 'buvid4': 'b4'}),
      now: () => testNow,
      logger: Logger(session: 'test')..add(sink),
    )..appBuvid = 'DEVICE';
  });

  String log() => sink.events.map((event) => event.encode()).join('\n');

  HTTPRequest only(String path) => http.requestsTo(path).single;

  /// The signed query rebuilt from the request's own fields: the signature covers exactly them.
  void expectWbiSigned(HTTPRequest request) {
    final query = http.query(request);
    final fields = Map.of(query)
      ..remove('w_rid')
      ..remove('wts');
    expect(request.url.query, WBI.signedQuery(fields, mixinKey: _mixinKey, wts: int.parse(query['wts']!)));
  }

  Map<String, String> unsigned(Map<String, String> sent) => Map.of(sent)
    ..remove('appkey')
    ..remove('ts')
    ..remove('sign');

  group('the tab’s feed', () {
    test(
      'the Android identity: app-signed on the live host, no cookies, PiliPlus’s fields, no token without one',
      () async {
        http.routes[_feedPath] = (200, _fixture('feed'));
        await client.liveFeed(page: 2);
        final request = only(_feedPath);
        expect((request.method, request.url.host), ('GET', _live));
        final sent = http.query(request);
        expect(sent['appkey'], androidKey);
        expect(sent['sign'], signedBy(AppSigner.android, sent));
        expect(unsigned(sent), {
          ...androidParams,
          'actionKey': 'appkey',
          'device': 'android',
          'device_name': 'android',
          'device_type': '0',
          'disable_rcmd': '0',
          'scale': '2',
          'fnval': '912',
          'https_url_req': '1',
          'network': 'wifi',
          'page': '2',
        });
        expect(request.headers['User-Agent'], androidUserAgent);
        expect(request.headers['app-key'], 'android');
        expect(request.headers['buvid'], 'DEVICE');
        expect(request.headers.containsKey('Cookie'), isFalse);
      },
    );

    test('a held token goes as access_key with relation_page, under its own identity', () async {
      http.routes[_feedPath] = (200, _fixture('feed'));
      client.appToken = tokenOf(OfficialIdentity.iphone);
      await client.liveFeed(page: 1);
      final request = only(_feedPath);
      final sent = http.query(request);
      expect(sent['appkey'], iphoneKey);
      expect(sent['sign'], signedBy(AppSigner.iphone, sent));
      expect(unsigned(sent), {
        ...iphoneParams,
        'device_name': 'iPhone 17 Pro Max',
        'scale': '3',
        'fnval': '912',
        'https_url_req': '1',
        'network': 'wifi',
        'page': '1',
        'relation_page': '1',
        'access_key': 'MADE-UP-ACCESS',
      });
      expect(request.headers['User-Agent'], iphoneUserAgent);
      expect(request.headers['app-key'], 'iphone');
      expect(request.headers['session_id'], client.appSessionId);
      expect(log(), isNot(contains('MADE-UP-ACCESS')));
      expect(log(), isNot(contains('DEVICE')));
    });

    test('decodes the carousel, 我的关注, the area tabs and the cards; a bad card costs only itself', () async {
      http.routes[_feedPath] = (200, _fixture('feed'));
      final page = await client.liveFeed(page: 1);
      expect(page.page, 1);
      expect(page.hasMore, isTrue);

      expect(page.bigCards.map((big) => big.card.roomId), [5001, 5002], reason: 'the activity banner names no room');
      final big = page.bigCards.first;
      expect((big.card.title, big.card.uname, big.card.uid), ('测试大卡', '测试主播甲', 7001));
      expect(big.card.cover, 'https://i0.hdslb.com/bfs/live/big-0001.jpg');
      expect((big.rankText, big.rankValue), ('人气榜TOP·2', '2009助力值'));

      expect(page.followingTotal, 3);
      final [followed] = page.following;
      expect(
        (followed.roomId, followed.uname, followed.areaName, followed.watchedText),
        (5010, '你关注的主播', '剑网3', '883'),
      );
      expect(followed.badge?.text, 'TopStar');
      expect(followed.badge?.icon, 'https://i0.hdslb.com/bfs/live/topstar-icon.png');
      expect(followed.badge?.colors, [0xFF3D2B5E]);

      expect(page.areas.map((area) => (area.id, area.parentId, area.name)), [
        (0, 0, '推荐'),
        (0, 14, '聊天室'),
        (145, 1, '颜值'),
      ]);
      expect(page.areas.first.isRecommend, isTrue);

      final [first, second] = page.cards;
      expect((first.roomId, first.uid, first.title, first.uname), (5020, 7020, '全国大赛测试', '测试主播丙'));
      expect(first.cover, 'https://i0.hdslb.com/bfs/live/system-0020.jpg', reason: 'system_cover wins');
      expect((first.areaName, first.watchedText, first.likeText), ('无畏契约', '9.1万', '12.3万'));
      expect(first.badge?.text, 'SS主播');
      expect(first.badge?.icon, 'https://i0.hdslb.com/bfs/live/ss-icon.png');
      expect(first.badge?.colors, [0xFFFF6699]);
      expect(first.cornerIcon, 'https://i0.hdslb.com/bfs/live/corner-0001.png');
      expect(first.verify, LiveVerify.personal);

      expect(
        (second.roomId, second.verify, second.cover),
        (5021, LiveVerify.organization, 'https://i0.hdslb.com/bfs/live/cover-0021.jpg'),
      );
      expect(second.badge?.text, '全站第5');
      expect(second.badge?.colors, [0xFFFB9E60]);
      expect((second.face, second.watchedText, second.likeText, second.cornerIcon), ('', '', '', ''));
    });

    test("each page's card types are logged in order, names only", () async {
      http.routes[_feedPath] = (200, _fixture('feed'));
      await client.liveFeed(page: 1);
      final line = sink.events.singleWhere((event) => event.msg == 'live feed card types');
      expect(
        (line.f['cards'] as LogString?)?.value,
        'banner_v2 my_idol_v1 area_entrance_v3 small_card_v1 small_card_v1 small_card_v1 unknown_v9',
      );
      expect(log(), isNot(contains('hdslb')));
      expect(log(), isNot(contains('5020')));
    });

    test('a later page without area tabs has none; an empty page ends the list', () {
      final page = LiveDecode.feed({
        'card_list': [
          {
            'card_type': 'small_card_v1',
            'card_data': {
              'small_card_v1': {'roomid': 1, 'title': 't', 'uname': 'u'},
            },
          },
        ],
        'has_more': 1,
      }, page: 2);
      expect((page.areas.length, page.cards.length, page.hasMore), (0, 1, true));
      expect(LiveDecode.feed({'card_list': <Object?>[], 'has_more': 1}, page: 3).hasMore, isFalse);
      expect(LiveDecode.feed(<String, Object?>{}, page: 1).areas, [LiveArea.recommend]);
    });

    test('a rejected token is reported and the call throws its code', () async {
      http.routes[_feedPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
      final rejected = <String>[];
      client
        ..appToken = tokenOf(OfficialIdentity.android)
        ..onAppTokenRejected = rejected.add;
      await expectLater(client.liveFeed(page: 1), throwsA(const BiliError.api(code: -101, message: '账号未登录')));
      expect(rejected, ['MADE-UP-ACCESS']);
    });

    test('risk control surfaces as BiliError', () async {
      http.routes[_feedPath] = (200, '{"code":-352,"message":"风控校验失败","ttl":1}');
      await expectLater(client.liveFeed(page: 1), throwsA(const BiliError.api(code: -352, message: '风控校验失败')));
    });
  });

  group('area lists', () {
    const area = LiveArea(id: 145, parentId: 1, name: '颜值');

    test('second/getList, app-signed, with the area and 20 a page', () async {
      http.routes[_areaPath] = (200, '{"code":0,"message":"0","data":{"count":45,"list":[{"roomid":1,"title":"a"}]}}');
      final page = await client.liveArea(area, page: 2);
      final sent = http.query(only(_areaPath));
      expect(sent['sign'], signedBy(AppSigner.android, sent));
      expect(only(_areaPath).url.host, _live);
      expect(sent, containsPair('area_id', '145'));
      expect(sent, containsPair('parent_area_id', '1'));
      expect(sent, containsPair('page', '2'));
      expect(sent, containsPair('page_size', '20'));
      expect(sent, containsPair('tag_version', '1'));
      expect(sent.containsKey('relation_page'), isFalse);
      expect((page.total, page.hasMore), (45, true));
    });

    test('a full page has more until count; has_more wins when answered; a bad row costs only itself', () {
      final rows = [
        for (var id = 1; id <= 20; id++) <String, Object?>{'roomid': id, 'title': '$id'},
      ];
      expect(LiveDecode.areaPage({'list': rows}, page: 1, pageSize: 20).hasMore, isTrue);
      expect(LiveDecode.areaPage({'list': rows, 'count': 20}, page: 1, pageSize: 20).hasMore, isFalse);
      expect(LiveDecode.areaPage({'list': rows, 'has_more': 0, 'count': 99}, page: 1, pageSize: 20).hasMore, isFalse);
      final page = LiveDecode.areaPage(
        {
          'list': [
            {'title': '没有房间'},
            'x',
            {'id': 9, 'title': '好的'},
          ],
        },
        page: 1,
        pageSize: 20,
      );
      expect(page.cards.map((card) => card.roomId), [9]);
    });

    test("推荐 is the feed's cards", () async {
      http.routes[_feedPath] = (200, _fixture('feed'));
      final page = await client.liveArea(LiveArea.recommend, page: 1);
      expect(page.cards.map((card) => card.roomId), [5020, 5021]);
      expect(http.requestsTo(_areaPath), isEmpty);
    });
  });

  group('206', () {
    test('the website’s following list with cookies, 9 a page; only live rooms, the live count as total', () async {
      http.routes[_followingPath] = (200, _fixture('following'));
      final page = await client.liveFollowing(page: 1);
      final request = only(_followingPath);
      expect((request.method, request.url.host), ('GET', _live));
      expect(http.query(request), {'page': '1', 'page_size': '9', 'ignoreRecord': '1', 'hit_ab': 'true'});
      expect(request.headers['Cookie'], contains('SESSDATA=MADE-UP-SESSION'));
      expect(page.cards.map((card) => (card.roomId, card.areaName, card.watchedText)), [
        (5010, '剑网3', '883'),
        (5011, '聊天室', '1.2万'),
      ]);
      expect(page.cards.first.cover, 'https://i0.hdslb.com/bfs/live/cover-0010.jpg');
      expect(page.total, 2);
      expect(page.hasMore, isFalse, reason: 'a room that is not live ends the live ones');
    });

    test('a page of live rooms has more until the last page', () {
      final rows = [
        for (var id = 1; id <= 9; id++) {'roomid': id, 'live_status': 1},
      ];
      expect(LiveDecode.following({'list': rows, 'totalPage': 3}, page: 1).hasMore, isTrue);
      expect(LiveDecode.following({'list': rows, 'totalPage': 3}, page: 3).hasMore, isFalse);
    });

    test('logged out it answers -101 as BiliError', () async {
      http.routes[_followingPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
      await expectLater(
        client.liveFollowing(page: 1),
        throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)),
      );
    });
  });

  group('the stream', () {
    test('getRoomPlayInfo is WBI-signed with the website’s fields, 10000 without a qn', () async {
      http.routes[_playPath] = (200, _fixture('play_info'));
      await client.livePlayInfo(5001);
      final request = only(_playPath);
      expect((request.method, request.url.host), ('GET', _live));
      expectWbiSigned(request);
      final sent = http.query(request)
        ..remove('w_rid')
        ..remove('wts');
      expect(sent, {
        'room_id': '5001',
        'protocol': '0,1',
        'format': '0,1,2',
        'codec': '0,1',
        'qn': '10000',
        'platform': 'web',
        'ptype': '8',
        'dolby': '5',
        'panorama': '1',
        'web_location': '444.8',
      });
      expect(request.headers['Referer'], 'https://live.bilibili.com/5001');
    });

    test('picks HLS fmp4 HEVC first, its first host, and names its qualities', () async {
      http.routes[_playPath] = (200, _fixture('play_info'));
      final info = await client.livePlayInfo(5001);
      expect(
        (info.roomId, info.shortId, info.uid, info.status, info.portrait),
        (5001, 3, 7001, LiveStatus.live, false),
      );
      expect(info.liveTime, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
      expect(
        info.url.toString(),
        'https://cn-test-fmp4.bilivideo.com/live-test/fmp4-hevc/index.m3u8?expires=1&sign=MADE-UP-FMP4-HEVC',
      );
      expect(info.currentQn, 10000);
      expect(info.qualities.map((quality) => (quality.qn, quality.name)), [
        (10000, '原画'),
        (400, '蓝光'),
        (250, '超清'),
        (999, '999'),
      ]);
      expect(log(), isNot(contains('MADE-UP-FMP4')));
      expect(log(), isNot(contains('bilivideo')));
    });

    test('a qn only AVC plays now takes fmp4 AVC; one no stream offers falls back to the first pick', () async {
      http.routes[_playPath] = (200, _fixture('play_info'));
      final avc = await client.livePlayInfo(5001, qn: 150);
      expect(http.query(http.requests.last)['qn'], '150');
      expect(avc.url.toString(), startsWith('https://cn-test-fmp4.bilivideo.com/live-test/fmp4-avc/'));
      expect(avc.currentQn, 150);
      expect(avc.qualities.map((quality) => quality.qn), [10000, 150]);

      final missing = await client.livePlayInfo(5001, qn: 80);
      expect(missing.url.toString(), contains('fmp4-hevc'));
      expect(missing.currentQn, 10000);
    });

    test('without fmp4, ts: HEVC before AVC; without HLS, no stream', () {
      Map<String, Object?> stream(List<Object?> formats) => {
        'room_id': 1,
        'live_status': 1,
        'playurl_info': {
          'playurl': {
            'stream': [
              {'protocol_name': 'http_hls', 'format': formats},
            ],
          },
        },
      };
      Map<String, Object?> codec(String name, String path) => {
        'codec_name': name,
        'current_qn': 10000,
        'accept_qn': [10000],
        'base_url': '/$path?',
        'url_info': [
          {'host': 'https://cn-test.bilivideo.com', 'extra': 'x=1'},
        ],
      };
      final ts = LiveDecode.playInfo(
        stream([
          {
            'format_name': 'ts',
            'codec': [codec('avc', 'a'), codec('hevc', 'h')],
          },
        ]),
      );
      expect(ts.url.toString(), 'https://cn-test.bilivideo.com/h?x=1');
      expect(ts.qualities.single.name, '10000', reason: 'no g_qn_desc names it');

      final none = LiveDecode.playInfo({
        'room_id': 1,
        'live_status': 0,
        'playurl_info': {
          'playurl': {
            'stream': [
              {
                'protocol_name': 'http_stream',
                'format': [
                  {
                    'format_name': 'flv',
                    'codec': [codec('avc', 'f')],
                  },
                ],
              },
            ],
          },
        },
      });
      expect((none.url, none.qualities.length, none.currentQn, none.status), (null, 0, 0, LiveStatus.offline));
      expect(LiveDecode.playInfo({'room_id': 2, 'live_status': 2, 'playurl_info': null}).status, LiveStatus.rotating);
      expect(() => LiveDecode.playInfo({'live_status': 1}), throwsA(isA<DecodeError>()));
    });
  });

  group('the room', () {
    test('getInfoByRoom, then the anchor’s card for 关注 when logged in', () async {
      http.routes[_roomPath] = (200, _fixture('room_info'));
      http.routes[_cardPath] = (
        200,
        '{"code":0,"message":"0","data":{"card":{"mid":"7001","name":"测试主播甲"},"following":true}}',
      );
      final info = await client.liveRoomInfo(5001);
      expectWbiSigned(only(_roomPath));
      expect(http.query(only(_roomPath)), containsPair('room_id', '5001'));
      expect(http.query(only(_cardPath)), containsPair('mid', '7001'));
      expect((info.roomId, info.uid, info.title), (5001, 7001, '全国大赛 AQ vs LGD'));
      expect((info.anchorName, info.anchorFace), ('测试主播甲', 'https://i0.hdslb.com/bfs/face/live-face-0001.jpg'));
      expect(info.anchorFrame, 'https://i0.hdslb.com/bfs/live/frame-mobile.png');
      expect(info.verify, LiveVerify.personal);
      expect(info.description, '测试公告第一行\n第二行 & 更多\n第三行');
      expect((info.areaName, info.likeCount, info.watchedText), ('无畏契约', 124000, '9.1万人看过'));
      expect(info.onlineCount, 9349);
      expect(info.topFaces, [
        'https://i0.hdslb.com/bfs/face/rank-0001.jpg',
        'https://i0.hdslb.com/bfs/face/rank-0002.jpg',
        'https://i0.hdslb.com/bfs/face/rank-0004.jpg',
      ]);
      expect(info.rankChips, ['热门榜', '网游人气第 28']);
      expect(info.following, isTrue);
    });

    test('logged out it asks only the room; a failed card leaves 关注 off', () async {
      http.routes[_roomPath] = (200, _fixture('room_info'));
      http.routes[_cardPath] = (200, '{"code":-352,"message":"风控","ttl":1}');
      expect((await client.liveRoomInfo(5001)).following, isFalse);
      expect(http.requestsTo(_cardPath), hasLength(1));

      client.cookies.remove('SESSDATA');
      await client.liveRoomInfo(5001);
      expect(http.requestsTo(_cardPath), hasLength(1));
    });

    test('a ranked room says 全站第 N; the area rank falls back to area_rank_info', () {
      final info = LiveDecode.roomInfo({
        'room_info': {'room_id': 1, 'parent_area_name': '娱乐'},
        'popular_rank_info': {'rank': 5},
        'area_rank_info': {
          'areaRank': {'rank': '12'},
        },
      });
      expect(info.rankChips, ['全站第 5', '娱乐人气第 12']);
      expect(
        LiveDecode.roomInfo({
          'room_info': {'room_id': 1},
        }).rankChips,
        isEmpty,
      );
    });

    test('getDanmuInfo is WBI-signed; hosts without a port are dropped; the token never reaches the log', () async {
      http.routes[_danmuPath] = (
        200,
        '{"code":0,"message":"0","data":{"token":"MADE-UP-DM-TOKEN","host_list":['
            '{"host":"broadcast-test-1.chat.bilibili.com","port":2243,"wss_port":443,"ws_port":2244},'
            '{"host":"broadcast-test-2.chat.bilibili.com","wss_port":0},{"wss_port":443}]}}',
      );
      final info = await client.liveDanmuInfo(5001);
      expectWbiSigned(only(_danmuPath));
      expect(http.query(only(_danmuPath)), containsPair('id', '5001'));
      expect(http.query(only(_danmuPath)), containsPair('type', '0'));
      expect(info.token, 'MADE-UP-DM-TOKEN');
      expect(info.hosts.map((host) => (host.host, host.wssPort)), [('broadcast-test-1.chat.bilibili.com', 443)]);
      expect(log(), isNot(contains('MADE-UP-DM-TOKEN')));
    });

    test(
      'history: the room’s lines with medals, emotes, a whole-message emote and a reply; bad rows dropped',
      () async {
        http.routes[_historyPath] = (200, _fixture('history'));
        final [first, second] = await client.liveHistory(5001);
        final request = only(_historyPath);
        expect(http.query(request), {'roomid': '5001'});
        expect(request.headers['Referer'], 'https://live.bilibili.com/5001');

        expect(
          (first.id, first.text, first.time),
          ('made-up-id-0001', '测试弹幕 [dog]', DateTime.fromMillisecondsSinceEpoch(1763327106 * 1000)),
        );
        expect((first.user.uid, first.user.name, first.user.wealthLevel, first.user.guardLevel), (9001, '观众甲', 4, 3));
        expect(first.user.nameColor, 0xFF00D1F1);
        final medal = first.user.medal!;
        expect((medal.name, medal.level, medal.guardLevel, medal.lit), ('莲宝', 21, 3, true));
        expect((medal.colorStart, medal.colorEnd, medal.border), (0xCC4775EF, 0xCC4775EF, 0xFF58A1F8));
        expect(first.emotes.keys, ['[dog]']);
        expect(first.emotes['[dog]']!.url, 'https://i0.hdslb.com/bfs/live/emote-dog.png');
        expect(first.emotes['[dog]']!.unique, 'emoji_208');
        expect((first.bigEmote, first.replyTo), (null, ''));

        expect(second.time, DateTime.utc(2026, 11, 16, 21, 6), reason: 'timeline is Beijing time');
        expect(second.bigEmote?.unique, 'room_5001_77');
        expect((second.bigEmote?.width, second.bigEmote?.height), (120, 60));
        expect(second.replyTo, '观众甲');
        final grey = second.user.medal!;
        expect((grey.lit, grey.colorStart), (false, 0xFFC0C0C0));
      },
    );

    test('super chats: those still showing, colours, the user and medal', () async {
      http.routes[_superChatPath] = (200, _fixture('super_chats'));
      final [chat] = await client.liveSuperChats(5001);
      expect(http.query(only(_superChatPath)), {'room_id': '5001'});
      expect((chat.id, chat.message, chat.price, chat.batteries), (6001, '测试醒目留言', 30, 300));
      expect(chat.end, DateTime.fromMillisecondsSinceEpoch(1702204300 * 1000));
      expect((chat.user.uid, chat.user.name, chat.user.guardLevel), (9101, '醒目甲', 3));
      expect(chat.user.faceFrame, 'https://i0.hdslb.com/bfs/live/frame-sc.png');
      expect(chat.user.medal?.name, '莲宝');
      expect(chat.user.medal?.level, 21);
      expect(
        (chat.background, chat.backgroundBottom, chat.priceColor, chat.headerColor),
        (0xFFEDF5FF, 0xFF2A60B2, 0xFF7497CD, 0xFF3171D2),
      );
    });

    test('在线榜: WBI-signed, 50 a page; rows, the viewer’s own unranked row and the count', () async {
      http.routes[_rankPath] = (200, _fixture('rank'));
      final page = await client.liveRank(5001, anchorUid: 7001, page: 1);
      final request = only(_rankPath);
      expectWbiSigned(request);
      final sent = http.query(request)
        ..remove('w_rid')
        ..remove('wts');
      expect(sent, {
        'ruid': '7001',
        'room_id': '5001',
        'page': '1',
        'page_size': '50',
        'type': 'online_rank',
        'switch': 'contribution_rank',
        'platform': 'web',
        'web_location': '444.8',
      });
      final [first, second] = page.entries;
      expect(
        (first.rank, first.score, first.user.name, first.user.wealthLevel, first.user.guardLevel),
        (1, 3768, '榜一', 41, 3),
      );
      expect(first.user.medal?.colorStart, 0xCC9660E5);
      expect((second.user.medal?.name, second.user.medal?.level, second.user.medal?.lit), ('旧牌', 5, false));
      expect((page.own?.rank, page.own?.user.uid, page.own?.user.wealthLevel), (0, 12345, 4));
      expect((page.count, page.hasMore), (9349, true));
    });

    test('大航海: the tab as typ, page 1 with the top three first, the total and the leader line', () async {
      http.routes[_guardPath] = (200, _fixture('guards'));
      final page = await client.liveGuards(5001, anchorUid: 7001, tab: LiveGuardTab.monthly, page: 1);
      expect(http.query(only(_guardPath)), {
        'roomid': '5001',
        'ruid': '7001',
        'page': '1',
        'page_size': '20',
        'typ': '4',
      });
      expect(page.entries.map((entry) => (entry.rank, entry.user.name, entry.user.guardLevel)), [
        (1, '提督甲', 2),
        (2, '提督乙', 2),
        (3, '提督丙', 2),
        (4, '舰长丁', 3),
        (5, '舰长戊', 3),
      ]);
      expect((page.total, page.hasMore), (5, false));
      expect((page.topText, page.topUser?.name), ('上周TOP1', '提督甲'));

      await client.liveGuards(5001, anchorUid: 7001, tab: LiveGuardTab.weekly, page: 2);
      expect(http.query(http.requests.last)['typ'], '3');
      await client.liveGuards(5001, anchorUid: 7001, tab: LiveGuardTab.companion, page: 2);
      expect(http.query(http.requests.last)['typ'], '5');
    });

    test('a later 大航海 page leaves top3 out', () {
      final page = LiveDecode.guards(
        {
          'info': {'num': 40},
          'top3': [
            {
              'rank': 1,
              'uinfo': {'uid': 1},
            },
          ],
          'list': [
            {
              'rank': 24,
              'uinfo': {'uid': 24},
            },
          ],
        },
        page: 2,
        pageSize: 20,
      );
      expect(page.entries.map((entry) => entry.rank), [24]);
      expect(page.hasMore, isTrue);
      expect((page.topText, page.topUser), ('', null));
    });

    test('emotes: the website’s pc packages, less what the viewer can’t send and packages left empty', () async {
      http.routes[_emotePath] = (200, _fixture('emotes'));
      final packages = await client.liveEmotes(5001);
      expect(http.query(only(_emotePath)), {'platform': 'pc', 'room_id': '5001'});
      expect(packages.map((package) => (package.id, package.name)), [(1, '通用表情'), (3, 'UP主大表情')]);
      final [emote] = packages.first.emotes;
      expect((emote.text, emote.unique, emote.width, emote.height), ('啊', 'official_331', 200, 60));
      expect(packages.first.icon, 'https://i0.hdslb.com/bfs/live/pkg-0001.png');
    });
  });

  group('writes', () {
    test('a danmaku: the form as the website sends it, csrf twice, web_location signed in the URL', () async {
      http.routes['POST $_sendPath'] = (200, _ok);
      await client.liveSend(5001, '测试弹幕');
      final request = only(_sendPath);
      expect((request.method, request.url.host), ('POST', _live));
      expectWbiSigned(request);
      expect(http.query(request), containsPair('web_location', '444.8'));
      expect(formFields(http.bodyText(request)), {
        'bubble': '0',
        'color': '16777215',
        'mode': '1',
        'fontsize': '25',
        'rnd': '${testNow.millisecondsSinceEpoch ~/ 1000}',
        'roomid': '5001',
        'msg': '测试弹幕',
        'room_type': '0',
        'jumpfrom': '0',
        'reply_mid': '0',
        'reply_attr': '0',
        'replay_dmid': '',
        'statistics': '{"appId":100,"platform":5}',
        'reply_type': '0',
        'reply_uname': '',
        'csrf_token': 'MADE-UP-CSRF',
        'csrf': 'MADE-UP-CSRF',
      });
      expect(request.headers['Referer'], 'https://live.bilibili.com/5001');
      expect(log(), isNot(contains('测试弹幕')));
      expect(log(), isNot(contains('MADE-UP-CSRF')));
    });

    test('an emote: its emoticon_unique as the message, dm_type 1', () async {
      http.routes['POST $_sendPath'] = (200, _ok);
      await client.liveSendEmote(
        5001,
        const LiveEmote(text: '啊', url: 'https://i0.hdslb.com/bfs/live/emote-0331.png', unique: 'official_331'),
      );
      final form = formFields(http.bodyText(only(_sendPath)));
      expect(form, containsPair('msg', 'official_331'));
      expect(form, containsPair('dm_type', '1'));
      expect(form, containsPair('emoticonOptions', '[object Object]'));
      expect(form.containsKey('reply_mid'), isFalse);
    });

    test('a refusal throws its code; logged out nothing is sent', () async {
      http.routes['POST $_sendPath'] = (200, '{"code":10031,"message":"发送频率过快","msg":"发送频率过快"}');
      await expectLater(client.liveSend(5001, 'x'), throwsA(const BiliError.api(code: 10031, message: '发送频率过快')));
      http.routes['POST $_sendPath'] = (200, '{"code":-352,"message":"风控","ttl":1}');
      await expectLater(client.liveSend(5001, 'x'), throwsA(const BiliError.api(code: -352, message: '风控')));

      client.cookies.remove('bili_jct');
      final before = http.requests.length;
      for (final call in [
        () => client.liveSend(5001, 'x'),
        () => client.liveSendEmote(5001, const LiveEmote(text: 'a', url: 'u', unique: 'official_1')),
        () => client.liveLike(5001, anchorUid: 7001, uid: 12345, clicks: 3),
        () => client.liveEnter(5001),
      ]) {
        await expectLater(call(), throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)));
      }
      expect(http.requests.skip(before).where((request) => request.url.host == _live), isEmpty);
    });

    test('点赞: one WBI-signed form with the clicks, the room, the viewer and the anchor', () async {
      http.routes['POST $_likePath'] = (200, _ok);
      await client.liveLike(5001, anchorUid: 7001, uid: 12345, clicks: 7);
      final request = only(_likePath);
      expect((request.method, request.url.host, request.url.query), ('POST', _live, ''));
      final form = formFields(http.bodyText(request));
      final signed = Map.of(form)
        ..remove('w_rid')
        ..remove('wts');
      expect(signed, {
        'click_time': '7',
        'room_id': '5001',
        'uid': '12345',
        'anchor_id': '7001',
        'web_location': '444.8',
        'csrf': 'MADE-UP-CSRF',
      });
      expect(form['wts'], '${testNow.millisecondsSinceEpoch ~/ 1000}');
      expect(
        WBI.signedQuery(signed, mixinKey: _mixinKey, wts: int.parse(form['wts']!)),
        endsWith('&w_rid=${form['w_rid']}'),
        reason: 'w_rid covers exactly the form',
      );
    });

    test('roomEntryAction: csrf in the URL and the form, room_id and platform pc', () async {
      http.routes['POST $_enterPath'] = (200, _ok);
      await client.liveEnter(5001);
      final request = only(_enterPath);
      expect(http.query(request), {'csrf': 'MADE-UP-CSRF'});
      expect(formFields(http.bodyText(request)), {'room_id': '5001', 'platform': 'pc', 'csrf': 'MADE-UP-CSRF'});
      http.routes['POST $_enterPath'] = (200, '{"code":-400,"message":"参数错误"}');
      await expectLater(client.liveEnter(5001), throwsA(const BiliError.api(code: -400, message: '参数错误')));
    });
  });
}
