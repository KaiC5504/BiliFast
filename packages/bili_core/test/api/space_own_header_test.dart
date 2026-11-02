import 'package:bili_core/api.dart';
import 'package:test/test.dart';

/// A made-up own space answer's `data`: the card with [vip] and [tags], and the 空间头图 [item] with [title].
Map<String, Object?> _data({
  Map<String, Object?>? vip,
  List<Object?> tags = const [],
  Map<String, Object?>? item,
  Map<String, Object?>? title,
}) => {
  'card': {'mid': '20000001', 'name': '测试账号', 'face': '', 'vip': ?vip, 'space_tag': tags},
  'images': {
    'collection_top_simple': {
      'top': {
        'result': [
          {
            'cover': 'https://i0.hdslb.com/bfs/garb/made-up/cover.png',
            'item': ?item,
            'title': title ?? {'title': '测试收藏集'},
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
    /// The animation as KaiC's answer shapes it (2026-11-02), every address made up.
    Map<String, Object?> animation({
      Object? videos = const [
        'http://i0.hdslb.com/bfs/garb/made-up/a.mp4',
        'https://i0.hdslb.com/bfs/garb/made-up/b.mp4',
      ],
      Object? firstFrame = 'https://i0.hdslb.com/bfs/garb/made-up/first.png',
      Object? backup = 'https://i0.hdslb.com/bfs/garb/made-up/backup.png',
      Object? silent = false,
    }) => {
      'is_silence': silent,
      'animation_video_urls': videos,
      'animation_backup_image': backup,
      'animation_first_frame': firstFrame,
      'width': 1080,
      'height': 1618,
      'duration': 8,
      'loop_mode': '',
      'location': '0-0-1080-1618',
      'compressed_w_h': '',
    };

    OwnSpace own(Map<String, Object?> animation) =>
        _profile(_data(item: {'item_type': 1, 'image': null, 'animation': animation})).own!;

    test('plays its first video over its first frame, laid out by its size and location', () {
      final space = own(animation());
      expect(space.bannerVideo, 'https://i0.hdslb.com/bfs/garb/made-up/a.mp4');
      expect(space.banner, 'https://i0.hdslb.com/bfs/garb/made-up/first.png');
      expect(space.bannerSize, (width: 1080, height: 1618));
      expect(space.bannerSilent, isFalse);
      expect(space.bannerAlignY, closeTo(1080 / 1618 - 1, 1e-9), reason: 'the second and third parts, as PiliPlus');
    });

    test('takes the second video when the first is empty or odd, and none from an odd list', () {
      expect(own(animation(videos: ['', 'https://i0.hdslb.com/b.mp4'])).bannerVideo, 'https://i0.hdslb.com/b.mp4');
      expect(own(animation(videos: [7, '//i0.hdslb.com/b.mp4'])).bannerVideo, 'https://i0.hdslb.com/b.mp4');
      for (final videos in [
        null,
        <Object?>[],
        'https://i0.hdslb.com/a.mp4',
        <Object?>[null, ''],
      ]) {
        expect(own(animation(videos: videos)).bannerVideo, isNull, reason: '$videos');
      }
    });

    test('the still falls back from the first frame to the backup picture to the cover', () {
      expect(own(animation(firstFrame: '')).banner, 'https://i0.hdslb.com/bfs/garb/made-up/backup.png');
      expect(own(animation(firstFrame: null, backup: '')).banner, 'https://i0.hdslb.com/bfs/garb/made-up/cover.png');
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

  group('the label\'s picture', () {
    test('is the title\'s title_icon', () {
      final label = _profile(
        _data(
          title: {'title': '测试收藏集', 'sub_title': 'CD.013149', 'title_icon': 'http://i0.hdslb.com/bfs/garb/icon.png'},
        ),
      ).own!.bannerLabel!;
      expect(label.icon, 'https://i0.hdslb.com/bfs/garb/icon.png');
      expect(label.subtitle, 'CD.013149');
    });

    test('is null when the title has none, or an empty or odd one', () {
      for (final icon in [null, '', 7]) {
        final label = _profile(_data(title: {'title': '测试收藏集', 'title_icon': ?icon})).own!.bannerLabel!;
        expect(label.icon, isNull, reason: '$icon');
      }
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
