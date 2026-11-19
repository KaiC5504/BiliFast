import 'package:bili_core/api.dart';
import 'package:test/test.dart';

/// A face as the portal lists it, made up.
Map<String, Object?> face(Object? mid, String name, {Object? hasUpdate = true}) => {
  'face': 'https://i0.hdslb.com/bfs/face/fake-$mid.jpg',
  'has_update': hasUpdate,
  'is_reserve_recall': false,
  'mid': mid,
  'uname': name,
};

/// The portal's `data` with [items] as `up_list` and [live] as `live_users`.
Map<String, Object?> portal(List<Object?> items, {List<Object?> live = const []}) => {
  'my_info': {'mid': '20000900', 'name': '测试我'},
  'live_users': {'count': '${live.length}', 'group': 'default', 'items': live},
  'up_list': {'has_more': true, 'items': items, 'offset': 'fake-offset-1'},
};

void main() {
  test('every face the portal lists comes through in its order, whatever form its fields take', () {
    final list = DynamicDecode.ups(
      portal([
        face(20000901, '测试常看一'),
        face('20000902', '测试常看二'),
        {
          'mid': '20000903',
          'uname': '测试常看三_Long',
          'has_update': 1,
          'is_reserve_recall': true,
          'unknown_field': {'x': 1},
        },
        face(20000904.0, '测试常看四', hasUpdate: 'yes'),
        face(20000900, '测试我', hasUpdate: false),
        face(20000905, '测试常看五', hasUpdate: null),
      ]),
    );
    expect(list.ups.map((up) => (up.mid, up.name, up.hasUpdate)), [
      (20000901, '测试常看一', true),
      (20000902, '测试常看二', true),
      (20000903, '测试常看三_Long', true),
      (20000904, '测试常看四', false),
      (20000900, '测试我', false),
      (20000905, '测试常看五', false),
    ]);
    expect(list.ups[2].face, '', reason: 'a face without its picture still shows');
    expect(list.dropped, 0);
    expect(list.offset, 'fake-offset-1');
    expect(list.hasMore, isTrue);
  });

  test('a face without a usable mid is dropped, and counted for the log', () {
    final list = DynamicDecode.ups(
      portal([
        face(20000901, '测试常看一'),
        face('不是数字', '测试坏一'),
        {'uname': '测试坏二'},
        '不是对象',
        face(20000902, '测试常看二'),
      ]),
    );
    expect(list.ups.map((up) => up.mid), [20000901, 20000902]);
    expect(list.dropped, 3);
  });

  test('live_users is read apart from the faces: its mids, whether up_list holds them too or not', () {
    final list = DynamicDecode.ups(
      portal(
        [face(20000901, '测试常看一'), face(20000902, '测试常看二')],
        live: [
          {'mid': '20000902', 'uname': '测试常看二', 'room_id': 1, 'title': '测试直播'},
          {'mid': 20000909, 'uname': '测试直播中', 'room_id': 2},
          {'uname': '测试无号'},
        ],
      ),
    );
    expect(list.ups.map((up) => up.mid), [20000901, 20000902]);
    expect(list.liveMids, [20000902, 20000909]);
  });

  group('live_users.items', () {
    test('a full item gives its mid, name, face and room, in the order listed', () {
      final list = DynamicDecode.ups(
        portal(
          const [],
          live: [
            {
              'face': 'https://i0.hdslb.com/bfs/face/fake-live-1.jpg',
              'has_update': false,
              'is_reserve_recall': false,
              'jump_url': 'https://live.bilibili.com/30000001?broadcast_type=0&is_room_feed=1',
              'mid': 20000911,
              'room_id': 30000001,
              'title': '测试直播的标题',
              'uname': '测试直播一',
            },
            {
              'face': 'https://i0.hdslb.com/bfs/face/fake-live-2.jpg',
              'mid': '20000912',
              'room_id': '30000002',
              'uname': '测试直播二',
            },
          ],
        ),
      );
      expect(list.liveUps.map((up) => (up.mid, up.name, up.face, up.roomId)), [
        (20000911, '测试直播一', 'https://i0.hdslb.com/bfs/face/fake-live-1.jpg', 30000001),
        (20000912, '测试直播二', 'https://i0.hdslb.com/bfs/face/fake-live-2.jpg', 30000002),
      ]);
    });

    test('the room comes from the link when room_id is missing, and the older call\'s uid stands for mid', () {
      final list = DynamicDecode.ups(
        portal(
          const [],
          live: [
            {'mid': 20000921, 'uname': '测试链接', 'jump_url': '//live.bilibili.com/30000021?session_id=x'},
            {'uid': 20000922, 'uname': '测试旧版', 'link': 'https://live.bilibili.com/30000022'},
            {'mid': 20000923, 'uname': '测试客户端', 'jump_url': 'bilibili://live/30000023?extra=1'},
            {'mid': 20000924, 'uname': '测试别处', 'jump_url': 'https://space.bilibili.com/20000924'},
          ],
        ),
      );
      expect(list.liveUps.map((up) => (up.mid, up.roomId)), [
        (20000921, 30000021),
        (20000922, 30000022),
        (20000923, 30000023),
        (20000924, 0),
      ]);
    });

    test('a missing name, face or room is tolerated; an item without a usable mid is dropped', () {
      final list = DynamicDecode.ups(
        portal(
          const [],
          live: [
            {'mid': 20000931},
            {'mid': 20000932, 'uname': 42, 'face': null, 'room_id': '不是数字'},
            {'mid': 0, 'uname': '测试零号', 'room_id': 1},
            {'mid': '不是数字', 'uname': '测试坏号', 'room_id': 2},
            {'uname': '测试无号', 'room_id': 3},
            '不是对象',
            null,
          ],
        ),
      );
      expect(list.liveUps.map((up) => (up.mid, up.name, up.face, up.roomId)), [
        (20000931, '', '', 0),
        (20000932, '', '', 0),
      ]);
      expect(list.dropped, 0, reason: 'dropped counts the faces only');
    });

    test('an empty, null or absent live list is no live faces', () {
      expect(DynamicDecode.ups(portal([face(20000901, '测试常看一')])).liveUps, isEmpty);
      expect(DynamicDecode.ups({'live_users': null, 'up_list': {'items': <Object?>[]}}).liveUps, isEmpty);
      expect(DynamicDecode.ups({'live_users': {'count': 0, 'items': null}}).liveUps, isEmpty);
      expect(DynamicDecode.ups({'live_users': {'count': 1, 'items': '不是数组'}}).liveUps, isEmpty);
      expect(DynamicDecode.ups({'up_list': <String, Object?>{}}).liveUps, isEmpty);
    });
  });

  test("uplist's page is data itself, with no live list", () {
    final list = DynamicDecode.ups({
      'items': [face(20000906, '测试常看六', hasUpdate: false)],
      'offset': 'fake-offset-2',
      'has_more': false,
    });
    expect(list.ups.single.mid, 20000906);
    expect(list.liveMids, isEmpty);
    expect(list.hasMore, isFalse);
  });

  test('a portal without faces is an empty row, not an error', () {
    expect(DynamicDecode.ups(portal(const [])).ups, isEmpty);
    expect(DynamicDecode.ups({'my_info': <String, Object?>{}, 'up_list': null}).ups, isEmpty);
  });
}
