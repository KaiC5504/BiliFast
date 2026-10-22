import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/src/api/md5.dart';
import 'package:test/test.dart';

import 'app_signer_test.dart' show makeClient;
import 'fake_http.dart';
import 'official_api_test.dart' show token;
import 'own_space_fixtures.dart';
import 'space_api_test.dart' show androidKey, androidParams, androidSecret, ts;

const skinPath = '/x/resource/show/skin';

Map<String, Object?> skinData() =>
    (jsonDecode(OwnSpaceFixtures.skin) as Map<String, Object?>)['data']! as Map<String, Object?>;

/// The fixture's skin with [change] made to its `user_equip`.
SkinEquip? equipWith(void Function(Map<String, Object?> equip) change) {
  final data = skinData();
  change(data['user_equip']! as Map<String, Object?>);
  return SkinEquip.fromJson(data);
}

/// The fixture's skin with [change] made to its colour `data`.
SkinColors colorsWith(void Function(Map<String, Object?> colours) change) =>
    equipWith((equip) => change(equip['data']! as Map<String, Object?>))!.colors;

void main() {
  late FakeHTTP http;
  late BiliClient client;

  setUp(() {
    http = FakeHTTP();
    http.routes[skinPath] = (200, OwnSpaceFixtures.skin);
    client = makeClient(http)
      ..appToken = token
      ..appBuvid = 'XYDEVICE';
  });

  group('the call', () {
    test('goes to the app host with the token, is_free_theme 0 and the Android parameters, signed', () async {
      await client.skin();
      final request = http.requestsTo(skinPath).single;
      expect(request.method, 'GET');
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'app.bilibili.com');
      final query = http.query(request);
      expect(Map.of(query)..removeWhere((key, _) => key == 'appkey' || key == 'ts' || key == 'sign'), {
        ...androidParams,
        'is_free_theme': '0',
        'access_key': 'ACCESS',
      });
      expect(query['appkey'], androidKey);
      expect(query['ts'], ts);
      final unsigned = request.url.query.split('&').where((pair) => !pair.startsWith('sign=')).join('&');
      expect(query['sign'], MD5.hex(unsigned + androidSecret));
      expect(request.headers.keys.map((name) => name.toLowerCase()), isNot(contains('cookie')));
      expect(query, isNot(contains('csrf')));
      expect(request.headers['buvid'], 'XYDEVICE');
    });

    test('without the app token nothing is sent', () async {
      client.appToken = null;
      await expectLater(client.skin(), throwsA(BiliError.noAppToken));
      expect(http.requests, isEmpty);
    });

    test('a rejected token is reported, then the call throws', () async {
      http.routes[skinPath] = (200, OwnSpaceFixtures.notLoggedIn);
      final rejected = <String>[];
      client.onAppTokenRejected = rejected.add;
      await expectLater(client.skin(), throwsA(const BiliError.api(code: -101, message: '账号未登录')));
      expect(rejected, ['ACCESS']);
    });

    test('an answer without data is nothing equipped, not an error', () async {
      http.routes[skinPath] = (200, OwnSpaceFixtures.skinNone);
      expect(await client.skin(), isNull);
    });

    test('a plain colour theme is nothing to dress with, not an error', () async {
      http.routes[skinPath] = (200, OwnSpaceFixtures.skinColourTheme);
      expect(await client.skin(), isNull);
    });
  });

  group('the equipped skin', () {
    test('decodes its id, name, version, package and colours', () async {
      final skin = (await client.skin())!;
      expect(skin.id, 34001);
      expect(skin.name, '测试装扮');
      expect(skin.ver, 1700000000);
      expect(skin.packageUrl, 'https://i0.hdslb.com/bfs/garb/zip/made-up-skin.zip');
      expect(skin.packageMd5, '0123456789abcdef0123456789abcdef');
      expect(skin.primaryOnly, isTrue);
      final colors = skin.colors;
      expect(colors.color, 0xFFFFFFFF);
      expect(colors.colorSecondPage, 0xFF5A4632);
      expect(colors.lightText, isTrue);
      expect(colors.tailColor, 0xFF999999);
      expect(colors.tailColorSelected, 0xFFFB7299);
      expect(colors.tailIconTinted, isTrue);
      expect(colors.tailIconColor, 0x80999999);
      expect(colors.tailIconColorSelected, 0xFFFB7299);
      expect(colors.tailIconAnimated, isTrue);
      expect(colors.tailIconCycle, isTrue);
      expect(colors.headMyselfVideoLoop, isTrue);
    });

    test('is null without a user_equip or its package, whatever common_equip, skin_colors or load_equip hold', () {
      final data = skinData()..remove('user_equip');
      expect(SkinEquip.fromJson(data), isNull);
      expect(SkinEquip.fromJson(skinData()..['user_equip'] = 'none'), isNull);
      expect(SkinEquip.fromJson(<String, Object?>{}), isNull);
      expect(equipWith((equip) => equip.remove('package_url')), isNull);
      expect(equipWith((equip) => equip['package_url'] = ''), isNull);
      expect(equipWith((equip) => equip['package_url'] = 7), isNull);
    });

    test('primary pages only is bit 2 of conf.attribute', () {
      bool primaryOnly(Object? attribute) =>
          equipWith((equip) => equip['conf'] = {'attribute': attribute})!.primaryOnly;
      expect(primaryOnly(4), isTrue);
      expect(primaryOnly(6), isTrue);
      expect(primaryOnly(7), isTrue);
      expect(primaryOnly('4'), isTrue);
      expect(primaryOnly(3), isFalse);
      expect(primaryOnly(0), isFalse);
      expect(primaryOnly(null), isFalse);
      expect(primaryOnly('all'), isFalse);
      expect(equipWith((equip) => equip.remove('conf'))!.primaryOnly, isFalse);
    });

    test('the modes read only their named values', () {
      final other = colorsWith(
        (data) => data
          ..['color_mode'] = 'dark'
          ..['tail_icon_mode'] = 'image'
          ..['tail_icon_ani'] = 0
          ..['tail_icon_ani_mode'] = 'once'
          ..['head_myself_mp4_play'] = 'once',
      );
      expect(other.lightText, isFalse);
      expect(other.tailIconTinted, isFalse);
      expect(other.tailIconAnimated, isFalse);
      expect(other.tailIconCycle, isFalse);
      expect(other.headMyselfVideoLoop, isFalse);
      expect(colorsWith((data) => data['tail_icon_ani'] = 1).tailIconAnimated, isTrue);
    });

    test('without colour data, nothing is coloured and nothing loops', () {
      final colors = equipWith((equip) => equip.remove('data'))!.colors;
      expect([
        colors.color,
        colors.colorSecondPage,
        colors.tailColor,
        colors.tailColorSelected,
        colors.tailIconColor,
        colors.tailIconColorSelected,
      ], everyElement(isNull));
      expect([
        colors.lightText,
        colors.tailIconTinted,
        colors.tailIconAnimated,
        colors.tailIconCycle,
      ], everyElement(isFalse));
      expect(colors.headMyselfVideoLoop, isFalse, reason: 'only "loop" loops');
    });

    test('a bad or empty colour costs only itself', () {
      final colors = colorsWith(
        (data) => data
          ..['color'] = ''
          ..['color_second_page'] = 'white'
          ..['tail_color'] = 0xFFFFFF
          ..['tail_color_selected'] = '#FFF',
      );
      expect([colors.color, colors.colorSecondPage, colors.tailColor, colors.tailColorSelected], everyElement(isNull));
      expect(colors.tailIconColor, 0x80999999);
      expect(colors.lightText, isTrue);
    });

    test('odd ids and versions read as 0, and the name as empty, without failing the skin', () {
      final skin = equipWith(
        (equip) => equip
          ..['id'] = 'x'
          ..['ver'] = null
          ..['name'] = 3
          ..['package_md5'] = null,
      )!;
      expect((skin.id, skin.ver, skin.name, skin.packageMd5), (0, 0, '', ''));
      expect(equipWith((equip) => equip['ver'] = '1700000001')!.ver, 1700000001);
    });

    test('a package link comes back as https', () {
      expect(
        equipWith((equip) => equip['package_url'] = '//i0.hdslb.com/bfs/garb/zip/a.zip')!.packageUrl,
        'https://i0.hdslb.com/bfs/garb/zip/a.zip',
      );
      expect(
        equipWith((equip) => equip['package_url'] = 'https://i0.hdslb.com/bfs/garb/zip/b.zip')!.packageUrl,
        'https://i0.hdslb.com/bfs/garb/zip/b.zip',
      );
    });
  });

  test('colours: #RRGGBB is opaque, #AARRGGBB keeps its alpha, any case, with or without #', () {
    expect(argbColour('#FB7299'), 0xFFFB7299);
    expect(argbColour('#fb7299'), 0xFFFB7299);
    expect(argbColour('FB7299'), 0xFFFB7299);
    expect(argbColour(' #FB7299 '), 0xFFFB7299);
    expect(argbColour('#80FB7299'), 0x80FB7299);
    expect(argbColour('#00000000'), 0x00000000);
    for (final bad in [
      null,
      '',
      '#',
      '#FFF',
      '#FFFFF',
      '#FFFFFFF',
      '#FFFFFFFFF',
      '#GGGGGG',
      '#-FFFFF',
      '+FFFFFF',
      'red',
    ]) {
      expect(argbColour(bad), isNull, reason: '$bad');
    }
    expect(argbColour(0xFFFFFF), isNull);
    expect(argbColour(['#FFFFFF']), isNull);
  });
}
