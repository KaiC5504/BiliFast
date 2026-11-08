import 'package:bili_core/api.dart';
import 'package:test/test.dart';

/// A made-up own space answer's `data`: the card with [vip] and [tags], and the 空间头图 [item] with [title], its
/// [bizType] and [digital] extra.
Map<String, Object?> _data({
  Map<String, Object?>? vip,
  List<Object?> tags = const [],
  Map<String, Object?>? item,
  Map<String, Object?>? title,
  Object? bizType,
  Map<String, Object?>? digital,
}) => {
  'card': {'mid': '20000001', 'name': '测试账号', 'face': '', 'vip': ?vip, 'space_tag': tags},
  'images': {
    'collection_top_simple': {
      'top': {
        'result': [
          {
            'biz_type': ?bizType,
            'cover': 'https://i0.hdslb.com/bfs/garb/made-up/cover.png',
            'item': ?item,
            'title': title ?? {'title': '测试收藏集'},
            'digital_extra': ?digital,
          },
        ],
      },
    },
  },
};

SpaceProfile _profile(Map<String, Object?> data) => SpaceProfile.fromJson(data, own: true);

double _alignOf(Map<String, Object?> item) => _profile(_data(item: item)).own!.bannerAlignY;

Map<String, Object?> _image(Object? location, Object? height) => {
  'default_image': 'https://i0.hdslb.com/bfs/garb/made-up/top.png',
  'width': 1125,
  'location': ?location,
  'height': ?height,
};

void main() {
  group('the banner\'s crop', () {
    test('is (start + end) / height − 1 from the picture\'s location, as an alignment\'s y', () {
      expect(_alignOf({'image': _image('0-120-680', 1600)}), closeTo(-0.5, 1e-9));
      expect(_alignOf({'image': _image('1-800-800', 1600)}), closeTo(0, 1e-9));
      expect(_alignOf({'image': _image('0-1000-1600', 1600)}), closeTo(0.625, 1e-9));
      expect(
        _alignOf({'image': _image(' 0 - 300 - 500 ', '1600')}),
        closeTo(-0.5, 1e-9),
        reason: 'spaces, a text height',
      );
      expect(_alignOf({'image': _image('0-120.5-679.5', 1600.0)}), closeTo(-0.5, 1e-9), reason: 'fractions');
    });

    test('comes from the animation when the picture has none', () {
      expect(_alignOf({'animation': _image('0-0-400', 1000)}), closeTo(-0.6, 1e-9));
      expect(_alignOf({'image': _image(null, 1600), 'animation': _image('0-0-400', 1000)}), closeTo(-0.6, 1e-9));
      expect(
        _alignOf({'image': _image('0-120-680', 1600), 'animation': _image('0-0-400', 1000)}),
        closeTo(-0.5, 1e-9),
        reason: 'the picture first',
      );
    });

    test('is the middle when the location or the height is missing or odd', () {
      for (final (location, height) in <(Object?, Object?)>[
        (null, 1600),
        ('0-120-680', null),
        ('0-120-680', 0),
        ('0-120-680', -1600),
        ('0-120-680', 'tall'),
        ('0-120', 1600),
        ('120-680', 1600),
        ('', 1600),
        ('a-b-c', 1600),
        ('0-120-', 1600),
        (120680, 1600),
        (['0', '120', '680'], 1600),
      ]) {
        expect(_alignOf({'image': _image(location, height)}), 0, reason: '$location over $height');
      }
      expect(_alignOf({}), 0, reason: 'an item with neither');
      expect(_alignOf({'image': 'not an object'}), 0);
      expect(_profile(_data()).own!.bannerAlignY, 0, reason: 'no item');
    });

    test('stays within the picture when the location runs past it', () {
      expect(_alignOf({'image': _image('0-3000-3000', 1000)}), 1);
      expect(_alignOf({'image': _image('0--5000-0', 1000)}), 0, reason: 'a negative start doesn\'t split as a number');
    });

    test('of anyone else\'s space is not read', () {
      final data = _data(item: {'image': _image('0-120-680', 1600)});
      expect(SpaceProfile.fromJson(data).own, isNull);
    });
  });

  group('an animated 空间头图', () {
    /// An animation as KaiC's answer shapes it (2026-11-09: `animation` and `additional_animation` alike), every
    /// address and number made up.
    Map<String, Object?> animation({
      String name = 'a',
      Object? videos,
      Object? firstFrame,
      Object? backup,
      Object? silent = false,
      int width = 1080,
      int height = 1618,
      Object? location = '0-6-1080-1210',
    }) => {
      'is_silence': silent,
      'animation_video_urls':
          videos ??
          [
            'http://upos-hz-mirrorakam.akamaized.net/made-up/$name.mp4?e=made-up',
            'https://i0.hdslb.com/bfs/garb/made-up/$name-backup.mp4',
          ],
      'animation_backup_image': backup ?? 'https://i0.hdslb.com/bfs/garb/made-up/$name-backup.png',
      'animation_first_frame': firstFrame ?? 'https://i0.hdslb.com/bfs/garb/made-up/$name-first.png',
      'width': width,
      'height': height,
      'duration': 8,
      'loop_mode': '',
      'location': location,
      'compressed_w_h': '',
    };

    OwnSpace own(Map<String, Object?> animation, {Map<String, Object?>? additional}) => _profile(
      _data(item: {'item_type': 1, 'image': null, 'animation': animation, 'additional_animation': ?additional}),
    ).own!;

    test('plays its first video over its backup picture, laid out by its size, the rest kept as backups', () {
      final space = own(animation());
      expect(space.bannerVideo, 'https://upos-hz-mirrorakam.akamaized.net/made-up/a.mp4?e=made-up');
      expect(space.bannerVideoBackups, ['https://i0.hdslb.com/bfs/garb/made-up/a-backup.mp4']);
      expect(space.banner, 'https://i0.hdslb.com/bfs/garb/made-up/a-backup.png');
      expect(space.bannerSize, (width: 1080, height: 1618));
      expect(space.bannerSilent, isFalse);
      expect(space.bannerAlignY, 0, reason: 'a four-part location is a rect, not PiliPlus\'s three parts');
    });

    test('additional_animation\'s video, still, size and crop come before animation\'s, as the official app\'s', () {
      final space = own(
        animation(width: 1080, height: 1920, location: '0-0-1080-1920', silent: true),
        additional: animation(name: 'extra', width: 720, height: 1080, location: '0-9-720-540'),
      );
      expect(space.bannerVideo, 'https://upos-hz-mirrorakam.akamaized.net/made-up/extra.mp4?e=made-up');
      expect(space.banner, 'https://i0.hdslb.com/bfs/garb/made-up/extra-backup.png');
      expect(space.bannerSize, (width: 720, height: 1080));
      expect(space.bannerSilent, isFalse, reason: 'the played one\'s is_silence');
      expect(space.bannerCrop!.middle, closeTo((9 + 540 / 2) / 1080, 1e-9));
      expect(space.bannerCrop!.aspect, closeTo(1080 / 720, 1e-9));
      expect(space.bannerFacts, {
        'image': false,
        'additional': true,
        'played': 'additional',
        'videos': 2,
        'width': 720,
        'height': 1080,
        'sizeFrom': 'additional',
        'location': '0-9-720-540',
        'cropFrom': 'additional',
        'cropWidth': 720,
        'cropHeight': 1080,
      });
    });

    test('without additional_animation\'s videos, animation\'s play; its still and crop still come first', () {
      final space = own(
        animation(),
        additional: animation(name: 'extra', videos: <Object?>[], location: '0-0-1080-800'),
      );
      expect(space.bannerVideo, 'https://upos-hz-mirrorakam.akamaized.net/made-up/a.mp4?e=made-up');
      expect(space.banner, 'https://i0.hdslb.com/bfs/garb/made-up/extra-backup.png');
      expect(space.bannerCrop!.middle, closeTo(400 / 1618, 1e-9));
      expect(space.bannerFacts['played'], 'animation');
    });

    test('the crop is animation\'s when additional_animation has none, and the image\'s after both', () {
      expect(own(animation(), additional: animation(location: '')).bannerCrop!.middle, closeTo(611 / 1618, 1e-9));
      final still = _profile(_data(item: {'image': _image('0-200-1125-1000', 2000)})).own!;
      expect(still.bannerCrop!.middle, closeTo(700 / 2000, 1e-9));
      expect(still.bannerCrop!.aspect, closeTo(2000 / 1125, 1e-9));
      expect(still.bannerAlignY, 0);
    });

    test('a crop needs four numbers and the art\'s size', () {
      for (final location in ['0-6-1080', '0-6-1080-1210-1', 'a-6-1080-1210', '0-6-1080-0', 1080, null]) {
        expect(own(animation(location: location)).bannerCrop, isNull, reason: '$location');
      }
      expect(own(animation(width: 0)).bannerCrop, isNull);
      expect(own(animation(height: 0)).bannerCrop, isNull);
    });

    test('a rect without its size, or with no band, falls to the next one\'s', () {
      for (final additional in [
        animation(name: 'extra', width: 0),
        animation(name: 'extra', height: 0),
        animation(name: 'extra')..remove('width'),
        animation(name: 'extra', location: '0-6-1080-0'),
        animation(name: 'extra', location: 'a-b-c-d'),
      ]) {
        final space = own(animation(), additional: additional);
        expect(space.bannerCrop!.middle, closeTo(611 / 1618, 1e-9), reason: '$additional');
        expect(space.bannerFacts['cropFrom'], 'animation');
      }
      final still = _profile(
        _data(
          item: {
            'image': _image('0-200-1125-1000', 2000),
            'animation': animation(width: 0),
            'additional_animation': animation(name: 'extra', height: 0),
          },
        ),
      ).own!;
      expect(still.bannerCrop!.middle, closeTo(700 / 2000, 1e-9), reason: 'the image\'s after both');
    });

    test('as KaiC\'s 数字藏品 answers: additional_animation plays with no size or location, so its crop and size are '
        'animation\'s, and the log names them', () {
      final additional = animation(name: 'extra', width: 0, height: 0)..remove('location');
      final space = own(animation(), additional: additional);
      expect(space.bannerVideo, 'https://upos-hz-mirrorakam.akamaized.net/made-up/extra.mp4?e=made-up');
      expect(space.bannerVideoBackups, hasLength(1));
      expect(space.bannerSize, (width: 1080, height: 1618));
      expect(space.bannerCrop!.middle, closeTo(611 / 1618, 1e-9));
      expect(space.bannerCrop!.aspect, closeTo(1618 / 1080, 1e-9));
      expect(space.bannerFacts, {
        'image': false,
        'additional': true,
        'played': 'additional',
        'videos': 2,
        'width': 1080,
        'height': 1618,
        'sizeFrom': 'animation',
        'location': '0-6-1080-1210',
        'cropFrom': 'animation',
        'cropWidth': 1080,
        'cropHeight': 1618,
      });

      final bare = own(animation(width: 0, height: 0)..remove('location'), additional: additional);
      expect(bare.bannerSize, isNull);
      expect(bare.bannerCrop, isNull);
      expect(bare.bannerFacts, containsPair('sizeFrom', 'none'));
      expect(bare.bannerFacts, containsPair('cropFrom', 'none'));

      final still = _profile(
        _data(
          item: {
            'image': _image('0-200-1125-1000', 2000),
            'animation': animation(width: 0, height: 0)..remove('location'),
            'additional_animation': additional,
          },
        ),
      ).own!;
      expect(still.bannerCrop!.middle, closeTo(700 / 2000, 1e-9));
      expect(still.bannerFacts, containsPair('cropFrom', 'image'));
      expect(still.bannerFacts, containsPair('cropWidth', 1125));
    });

    test('the animation\'s rect wins over the image\'s three-part alignment in a box', () {
      final space = _profile(_data(item: {'image': _image('0-120-680', 1600), 'animation': animation()})).own!;
      expect(space.bannerAlignY, closeTo(-0.5, 1e-9));
      expect(space.bannerCrop!.middle, closeTo(611 / 1618, 1e-9));
      expect(space.bannerAlignIn(440, 295.67), space.bannerCrop!.alignY(440, 295.67));
      expect(space.bannerAlignIn(440, 295.67), isNot(closeTo(-0.5, 1e-3)));
    });

    test('takes the second video when the first is empty or odd, and none from an odd list', () {
      expect(own(animation(videos: ['', 'https://i0.hdslb.com/b.mp4'])).bannerVideo, 'https://i0.hdslb.com/b.mp4');
      expect(own(animation(videos: [7, '//i0.hdslb.com/b.mp4'])).bannerVideo, 'https://i0.hdslb.com/b.mp4');
      for (final videos in [
        <Object?>[],
        'https://i0.hdslb.com/a.mp4',
        <Object?>[null, ''],
      ]) {
        expect(own(animation(videos: videos)).bannerVideo, isNull, reason: '$videos');
      }
    });

    test('the still falls back from the backup picture to the first frame to the cover', () {
      expect(own(animation(backup: '')).banner, 'https://i0.hdslb.com/bfs/garb/made-up/a-first.png');
      expect(own(animation(backup: '', firstFrame: '')).banner, 'https://i0.hdslb.com/bfs/garb/made-up/cover.png');
    });

    test('is_silence leaves the sound out', () {
      expect(own(animation(silent: true)).bannerSilent, isTrue);
      expect(own(animation(silent: 1)).bannerSilent, isTrue);
      expect(own(animation(silent: null)).bannerSilent, isFalse);
    });

    test('without a size the video has none', () {
      final odd = animation()..['width'] = 0;
      expect(own(odd).bannerSize, isNull);
      expect(own(animation()..remove('height')).bannerSize, isNull);
    });

    test('a still 空间头图 has no video', () {
      final space = _profile(_data(item: {'image': _image('0-120-680', 1600)})).own!;
      expect(space.bannerVideo, isNull);
      expect(space.banner, 'https://i0.hdslb.com/bfs/garb/made-up/top.png');
      expect(space.bannerSize, isNull);
    });
  });

  group('the label', () {
    const title = {
      'title': '测试收藏集',
      'sub_title': 'CD.000001',
      'title_icon': 'https://i0.hdslb.com/bfs/garb/made-up/card-art.png',
    };

    SpaceBannerLabel label({Object? bizType, Map<String, Object?>? digital, Map<String, Object?> title = title}) =>
        _profile(_data(title: title, bizType: bizType, digital: digital)).own!.bannerLabel!;

    test('a 数字藏品\'s draws the ◇ glyph, never the title_icon (the card\'s own art)', () {
      final collectible = label(bizType: 2, digital: {'region_type': 1, 'region_icon': ''});
      expect(collectible.glyph, SpaceBannerGlyph.collectible);
      expect(collectible.icon, isNull);
      expect(label(bizType: 3).glyph, SpaceBannerGlyph.collectible, reason: 'NFT');
      expect(label(bizType: '2').glyph, SpaceBannerGlyph.collectible);
    });

    test('a region_type 2 draws its own glyph; a 装扮 or an unknown kind draws none', () {
      expect(label(bizType: 2, digital: {'region_type': 2}).glyph, SpaceBannerGlyph.region);
      expect(label(bizType: 1, digital: {'region_type': 2}).glyph, SpaceBannerGlyph.region);
      for (final kind in [1, 0, null, 'garb']) {
        final drawn = label(bizType: kind);
        expect((drawn.glyph, drawn.icon), (SpaceBannerGlyph.none, null), reason: '$kind');
      }
    });

    test('region_icon is drawn before any glyph', () {
      final drawn = label(
        bizType: 2,
        digital: {'region_type': 2, 'region_icon': 'http://i0.hdslb.com/bfs/made-up/r.png'},
      );
      expect(drawn.icon, 'https://i0.hdslb.com/bfs/made-up/r.png');
      expect(drawn.glyph, SpaceBannerGlyph.none);
    });

    test('region_title and region_subtitle come before the title\'s, which stand in for empty ones', () {
      final region = label(digital: {'region_title': '地区收藏集', 'region_subtitle': 'CD.000002'});
      expect((region.title, region.subtitle), ('地区收藏集', 'CD.000002'));
      final empty = label(digital: {'region_title': '', 'region_subtitle': ''});
      expect((empty.title, empty.subtitle), ('测试收藏集', 'CD.000001'));
      expect(label(title: const {}, digital: {'region_title': '只有地区'}).title, '只有地区');
      expect(_profile(_data(title: const {})).own!.bannerLabel, isNull);
    });
  });

  group('the crop in a box', () {
    // 25's box: 440 × 295.67, the art 1080 × 1618 drawn 440 wide (659.19 tall).
    const width = 440.0;
    const height = 295.67;
    const aspect = 1618 / 1080;

    double topOf(double alignY) => (1 + alignY) / 2 * (height - width * aspect);

    test('puts the band\'s middle at the box\'s middle', () {
      for (final middle in [0.2, 0.35, 0.5, 0.8]) {
        final y = SpaceBannerCrop(middle: middle, aspect: aspect).alignY(width, height);
        expect(topOf(y) + middle * width * aspect, closeTo(height / 2, 1e-9), reason: '$middle');
      }
      expect(const SpaceBannerCrop(middle: 0.5, aspect: aspect).alignY(width, height), closeTo(0, 1e-9));
      expect(
        const SpaceBannerCrop(middle: 0, aspect: aspect).alignY(width, height),
        lessThan(-1),
        reason: 'unclamped, as the official app\'s',
      );
    });

    test('a short picture is cut about its middle', () {
      expect(const SpaceBannerCrop(middle: 0.1, aspect: 0.5).alignY(width, height), 0);
    });

    test('OwnSpace takes the crop over the three-part alignment', () {
      const space = OwnSpace(bannerAlignY: -0.5, bannerCrop: SpaceBannerCrop(middle: 0.5, aspect: aspect));
      expect(space.bannerAlignIn(width, height), closeTo(0, 1e-9));
      expect(const OwnSpace(bannerAlignY: -0.5).bannerAlignIn(width, height), -0.5);
    });
  });

  group('the 大 on the avatar', () {
    bool badge(Map<String, Object?>? vip) => _profile(_data(vip: vip)).own!.vipBadge;

    test('goes by avatar_subscript when the card\'s vip has one', () {
      expect(badge({'vipType': 2, 'vipStatus': 1, 'avatar_subscript': 1}), isTrue);
      expect(badge({'vipType': 1, 'vipStatus': 1, 'avatar_subscript': 1}), isTrue);
      expect(badge({'vipType': 2, 'vipStatus': 1, 'avatar_subscript': 0}), isFalse);
      expect(badge({'vipType': 2, 'vipStatus': 1, 'avatar_subscript': null}), isFalse);
    });

    test('without one, as the own space\'s answer comes, is a 大会员\'s while it lasts', () {
      expect(badge({'vipType': 2, 'vipStatus': 1, 'vipDueDate': 1800000000000, 'themeType': 0}), isTrue);
      expect(badge({'vipType': 1, 'vipStatus': 1}), isTrue, reason: 'a monthly 大会员');
      expect(badge({'type': 2, 'status': 1}), isTrue, reason: 'the web card\'s names');
      expect(badge({'vipType': 0, 'vipStatus': 1}), isFalse, reason: 'no 大会员');
      expect(badge({'vipType': 2, 'vipStatus': 0}), isFalse, reason: 'lapsed');
      expect(badge({}), isFalse);
      expect(badge(null), isFalse);
    });
  });

  group('the tag lines', () {
    test('mark 添加学校信息 by its type, and nothing else', () {
      final tags = _profile(
        _data(
          tags: [
            {'type': 'location', 'title': 'IP属地：澳大利亚'},
            {'type': 'submit_school', 'title': '添加学校信息', 'uri': 'bilibili://made-up'},
            {'type': 'school', 'title': '某某大学', 'uri': 'bilibili://made-up'},
            {'title': '没有类型'},
          ],
        ),
      ).tagLines;
      expect([for (final tag in tags) tag.schoolPrompt], [false, true, false, false]);
      expect(tags[1].link, isTrue);
    });
  });
}
