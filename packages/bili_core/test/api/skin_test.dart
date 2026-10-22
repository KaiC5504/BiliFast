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

    test('an answer of another shape is a decoding error naming its keys, never nothing equipped', () async {
      final data = skinData();
      (data['user_equip']! as Map<String, Object?>).remove('package_url');
      http.routes[skinPath] = (200, jsonEncode({'code': 0, 'message': '0', 'data': data}));
      await expectLater(
        client.skin(),
        throwsA(
          isA<BiliDecodingError>().having(
            (error) => error.detail,
            'detail',
            'DecodeError: skin: user_equip has no package_url (user_equip keys: conf, data, id, name, package_md5, ver)',
          ),
        ),
      );
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

    test('is null when nothing is equipped: empty data, a null, empty or zero user_equip, or a colour theme', () {
      expect(SkinEquip.fromJson(<String, Object?>{}), isNull);
      expect(SkinEquip.fromJson(skinData()..['user_equip'] = null), isNull);
      expect(SkinEquip.fromJson(skinData()..['user_equip'] = <String, Object?>{}), isNull);
      for (final id in [0, '0', 0.0]) {
        final zero = {
          'id': id,
          'name': '',
          'ver': 0,
          'package_url': '',
          'package_md5': '',
          'data': <String, Object?>{},
        };
        expect(SkinEquip.fromJson(skinData()..['user_equip'] = zero), isNull, reason: '$id');
      }
      final colourTheme = skinData()
        ..['user_equip'] = {
          'id': 8,
          'name': '测试粉',
          'data': {'color': '#FB7299'},
        };
      expect(SkinEquip.fromJson(colourTheme), isNull, reason: 'id 8 is among skin_colors');
    });

    test('any other shape throws, naming the problem and the keys but never a value', () {
      Matcher fails(String message) => throwsA(isA<DecodeError>().having((error) => error.message, 'message', message));
      expect(
        () => SkinEquip.fromJson(skinData()..remove('user_equip')),
        fails('skin: no user_equip (data keys: common_equip, load_equip, skin_colors)'),
      );
      expect(
        () => SkinEquip.fromJson(skinData()..['user_equip'] = 'none'),
        fails('skin: user_equip is a string (data keys: common_equip, load_equip, skin_colors, user_equip)'),
      );
      expect(
        () => SkinEquip.fromJson(skinData()..['user_equip'] = [1]),
        fails('skin: user_equip is a list (data keys: common_equip, load_equip, skin_colors, user_equip)'),
      );
      expect(
        () => equipWith((equip) => equip.remove('package_url')),
        fails('skin: user_equip has no package_url (user_equip keys: conf, data, id, name, package_md5, ver)'),
      );
      expect(
        () => equipWith((equip) => equip['package_url'] = ' '),
        fails(
          'skin: user_equip has no package_url (user_equip keys: conf, data, id, name, package_md5, package_url, ver)',
        ),
      );
      expect(
        () => equipWith((equip) => equip['package_url'] = 7),
        fails('skin: package_url is a number (user_equip keys: conf, data, id, name, package_md5, package_url, ver)'),
      );
      expect(
        () => equipWith(
          (equip) => equip
            ..remove('package_url')
            ..['id'] = 9,
        ),
        throwsA(isA<DecodeError>()),
        reason: 'an id that is no colour theme',
      );
      expect(
        () => equipWith(
          (equip) => equip
            ..remove('package_url')
            ..remove('id'),
        ),
        throwsA(isA<DecodeError>()),
        reason: 'an object of other keys',
      );
      expect(() => SkinEquip.fromJson([1]), throwsA(isA<DecodeError>()));

      final long = skinData()..remove('user_equip');
      for (var i = 0; i < 30; i++) {
        long['key_$i${'x' * 50}'] = i;
      }
      try {
        SkinEquip.fromJson(long);
        fail('no user_equip');
      } on DecodeError catch (error) {
        expect(error.message, endsWith(', …)'));
        expect(error.message.split(', ').where((key) => key.startsWith('key_')), everyElement(hasLength(40)));
      }
    });

    test('the messages carry no value of the answer', () {
      for (final change in <void Function(Map<String, Object?>)>[
        (equip) => equip.remove('package_url'),
        (equip) => equip['package_url'] = 7,
      ]) {
        try {
          equipWith(change);
          fail('should throw');
        } on DecodeError catch (error) {
          for (final value in ['34001', '测试', 'hdslb', '0123456789abcdef', '1700000000', '#FFFFFF']) {
            expect(error.message, isNot(contains(value)));
          }
        }
      }
    });

    test('loops the header video only for "loop", and so does a SkinColors made without it', () {
      expect(const SkinColors().headMyselfVideoLoop, isFalse);
      expect(colorsWith((data) => data.remove('head_myself_mp4_play')).headMyselfVideoLoop, isFalse);
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
