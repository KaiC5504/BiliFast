import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

final class _Events implements LogSink {
  final List<LogEvent> events = [];

  @override
  void receive(LogEvent event) => events.add(event);

  String get text => events.map((event) => event.encode()).join('\n');
}

const navPath = '/x/web-interface/nav';
const statPath = '/x/web-interface/nav/stat';
const playPath = '/x/player/wbi/playurl';

const _wbi = {
  'img_url': 'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
  'sub_url': 'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
};

// Made up, in the shape the website's nav answers a logged-in account with.
Map<String, Object?> _account() => {
  'isLogin': true,
  'mid': 12345,
  'uname': '测试用户',
  'face': 'https://i0.hdslb.com/bfs/face/test.jpg',
  'level_info': {'current_level': 6, 'current_min': 28800, 'current_exp': 30000, 'next_exp': '--'},
  'money': 128.5,
  'pendant': {'pid': 1, 'name': '测试挂件', 'image': 'https://i0.hdslb.com/bfs/garb/item/pendant-test.png', 'expire': 0},
  'vipStatus': 1,
  'vipType': 2,
  'vip_label': {'path': '', 'text': '年度大会员', 'label_theme': 'annual_vip'},
  'vip_avatar_subscript': 1,
  'wallet': {'mid': 12345, 'bcoin_balance': 5.0, 'coupon_balance': 0},
  'wbi_img': _wbi,
};

String _ok(Map<String, Object?> data) => jsonEncode({'code': 0, 'message': '0', 'ttl': 1, 'data': data});

const _stat = '{"code":0,"message":"0","ttl":1,"data":{"following":321,"follower":987654,"dynamic_count":42}}';
const _loggedOut = '{"code":-101,"message":"账号未登录","ttl":1}';

void main() {
  group('nav', () {
    test('a logged-in answer gives the level, 硬币, B币, the vip label and badge and the frame', () async {
      final http = FakeHTTP()..routes[navPath] = (200, _ok(_account()));
      final nav = await makeTestClient(http).nav();
      expect(nav.isLogin, isTrue);
      expect(nav.mid, 12345);
      expect(nav.uname, '测试用户');
      expect(nav.level, 6);
      expect(nav.coins, 128.5);
      expect(nav.bcoin, 5.0);
      expect(nav.vipLabel, '年度大会员');
      expect(nav.vipBadge, isTrue);
      expect(nav.pendant, 'https://i0.hdslb.com/bfs/garb/item/pendant-test.png');
      expect(nav.isVip, isTrue);
    });

    test('whole numbers of 硬币 and B币 read as doubles', () {
      final nav = NavInfo.fromJson(_account()
        ..['money'] = 12
        ..['wallet'] = {'bcoin_balance': 0});
      expect(nav.coins, 12.0);
      expect(nav.bcoin, 0.0);
    });

    test('without the fields, the defaults', () {
      final nav = NavInfo.fromJson({'isLogin': true, 'mid': 12345, 'wbi_img': _wbi});
      expect(nav.level, 0);
      expect(nav.coins, 0);
      expect(nav.bcoin, 0);
      expect(nav.vipLabel, '');
      expect(nav.vipBadge, isFalse);
      expect(nav.pendant, isNull);
    });

    test('an account without a frame or label answers them empty: no frame, no label, no badge', () {
      final nav = NavInfo.fromJson(_account()
        ..['pendant'] = {'pid': 0, 'name': '', 'image': '', 'expire': 0}
        ..['vip_label'] = {'path': '', 'text': '', 'label_theme': ''}
        ..['vip_avatar_subscript'] = 0);
      expect(nav.pendant, isNull);
      expect(nav.vipLabel, '');
      expect(nav.vipBadge, isFalse);
    });

    test('a frame given as http or protocol-relative is asked over https', () {
      final plain = NavInfo.fromJson(_account()..['pendant'] = {'image': 'http://i0.hdslb.com/bfs/garb/item/a.png'});
      expect(plain.pendant, 'https://i0.hdslb.com/bfs/garb/item/a.png');
      final relative = NavInfo.fromJson(_account()..['pendant'] = {'image': '//i0.hdslb.com/bfs/garb/item/b.png'});
      expect(relative.pendant, 'https://i0.hdslb.com/bfs/garb/item/b.png');
    });

    test('我的 fields of an unexpected shape read as defaults and the WBI keys still sign', () async {
      final odd = _account()
        ..['level_info'] = {'current_level': '--'}
        ..['money'] = '--'
        ..['wallet'] = {'bcoin_balance': '5'}
        ..['vip_label'] = {'text': 1}
        ..['vip_avatar_subscript'] = true
        ..['pendant'] = {'image': 7};
      final http = FakeHTTP()
        ..routes[navPath] = (200, _ok(odd))
        ..routes[playPath] = (200, Fixtures.playURL);
      final client = makeTestClient(http);
      final nav = await client.nav();
      expect(nav.isLogin, isTrue);
      expect(nav.level, 0);
      expect(nav.coins, 0);
      expect(nav.bcoin, 0);
      expect(nav.vipLabel, '');
      expect(nav.vipBadge, isFalse);
      expect(nav.pendant, isNull);
      await client.playURL(bvid: 'BV1GJ411x7h7', cid: 1, quality: 120);
      expect(http.query(http.requestsTo(playPath).single)['w_rid']?.length, 32);
      expect(http.requestsTo(navPath), hasLength(1));
    });

    test('a logged-out answer (-101) is returned with the defaults and the WBI keys', () async {
      final http = FakeHTTP()..routes[navPath] = (200, Fixtures.navLoggedOut);
      final nav = await makeTestClient(http).nav();
      expect(nav.isLogin, isFalse);
      expect(nav.mid, isNull);
      expect(nav.level, 0);
      expect(nav.coins, 0);
      expect(nav.bcoin, 0);
      expect(nav.vipLabel, '');
      expect(nav.vipBadge, isFalse);
      expect(nav.pendant, isNull);
      expect(nav.imgURL, isNotEmpty);
      expect(nav.subURL, isNotEmpty);
    });

    test('equality covers the new fields', () {
      final nav = NavInfo.fromJson(_account());
      expect(NavInfo.fromJson(_account()), nav);
      expect(NavInfo.fromJson(_account()..['money'] = 128), isNot(nav));
      expect(NavInfo.fromJson(_account()..['level_info'] = {'current_level': 5}), isNot(nav));
      expect(NavInfo.fromJson(_account()..['wallet'] = {'bcoin_balance': 1}), isNot(nav));
      expect(NavInfo.fromJson(_account()..['vip_label'] = {'text': '大会员'}), isNot(nav));
      expect(NavInfo.fromJson(_account()..['vip_avatar_subscript'] = 0), isNot(nav));
      expect(NavInfo.fromJson(_account()..['pendant'] = {'image': ''}), isNot(nav));
    });
  });

  group('NavStat', () {
    test('reads 关注, 粉丝 and 动态', () {
      expect(
        NavStat.fromJson({'following': 321, 'follower': 987654, 'dynamic_count': 42}),
        const NavStat(following: 321, follower: 987654, dynamicCount: 42),
      );
    });

    test('a count missing or null is 0', () {
      expect(NavStat.fromJson(<String, Object?>{}), const NavStat(following: 0, follower: 0, dynamicCount: 0));
      expect(
        NavStat.fromJson({'following': null, 'follower': 7, 'dynamic_count': null}),
        const NavStat(following: 0, follower: 7, dynamicCount: 0),
      );
    });
  });

  group('navStat', () {
    test('is an unsigned GET to the API host with the web login\'s cookies', () async {
      final http = FakeHTTP()..routes[statPath] = (200, _stat);
      final stat = await makeTestClient(http, cookies: {'SESSDATA': 'sess', 'bili_jct': 'JCT'}).navStat();
      expect(stat, const NavStat(following: 321, follower: 987654, dynamicCount: 42));
      final request = http.requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.bilibili.com$statPath');
      expect(request.body, isNull);
      expect(request.headers['Cookie'], contains('SESSDATA=sess'));
      expect(request.headers['Referer'], 'https://www.bilibili.com/');
    });

    test('logged out throws -101', () async {
      final http = FakeHTTP()..routes[statPath] = (200, _loggedOut);
      await expectLater(
        makeTestClient(http).navStat(),
        throwsA(const BiliError.api(code: -101, message: '账号未登录')),
      );
    });

    test('another code throws it', () async {
      final http = FakeHTTP()..routes[statPath] = (200, '{"code":-412,"message":"请求被拦截"}');
      await expectLater(
        makeTestClient(http).navStat(),
        throwsA(const BiliError.api(code: -412, message: '请求被拦截')),
      );
    });
  });

  test('the log carries the paths and codes, never the account, its counts or a cookie', () async {
    final log = _Events();
    final http = FakeHTTP()
      ..routes[navPath] = (200, _ok(_account()))
      ..routes[statPath] = (200, _stat);
    final client = BiliClient(
      transport: http,
      cookies: CookieJar({'SESSDATA': 'sess-made-up', 'bili_jct': 'jct-made-up'}),
      now: () => testNow,
      logger: Logger(session: 'test')..add(log),
    );
    await client.nav();
    await client.navStat();
    expect(log.text, contains(statPath));
    for (final value in ['sess-made-up', 'jct-made-up', '测试用户', '年度大会员', 'pendant-test', '128.5', '987654']) {
      expect(log.text, isNot(contains(value)), reason: value);
    }
  });
}
