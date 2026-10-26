import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/src/api/bvid.dart';
import 'package:test/test.dart';

/// Made-up answers in the live answers' shapes (2026-10-26).
String fixture(String name) => File('test/fixtures/dynamic/$name.json').readAsStringSync();

T decoded<T>(String name, T Function(Object? json) decode) =>
    decode((jsonDecode(fixture(name)) as Map<String, Object?>)['data']);

DynamicPage pageOf(String name) => decoded(name, DynamicDecode.page);

/// A node as one comparable record, so a test can list a post's text in order.
Object nodeShape(DynamicNode node) => switch (node) {
  DynamicTextNode(:final text) => ('text', text),
  DynamicEmojiNode(:final text, :final url, :final large) => ('emoji', text, url, large),
  DynamicMentionNode(:final text, :final mid) => ('at', text, mid),
  DynamicTopicNode(:final text) => ('topic', text),
  DynamicLinkNode(:final text, :final url) => ('link', text, url),
  DynamicVideoLinkNode(:final text, :final bvid) => ('video', text, bvid),
  DynamicBadgeNode(:final text, :final kind) => ('badge', text, kind),
};

List<Object> shapes(DynamicItem item) => [for (final node in item.nodes) nodeShape(node)];

void main() {
  group('the feed', () {
    late DynamicPage page;
    setUp(() => page = pageOf('feed_all'));

    test('keeps the paging fields', () {
      expect(page.offset, '1100000000000000099');
      expect(page.hasMore, isTrue);
    });

    test('drops an item that will not decode and counts it by type, without failing the page', () {
      expect(page.items.map((item) => item.id), [
        '1100000000000000001',
        '1100000000000000002',
        '1100000000000000003',
        '1100000000000000004',
        '1100000000000000005',
        '1100000000000000006',
      ]);
      expect(page.skipped, {'DYNAMIC_TYPE_DRAW': 1, 'DYNAMIC_TYPE_AV': 1, 'unknown': 1});
    });

    test('a repost carries its text and the original in the same shape', () {
      final repost = page.items[0];
      expect(repost.kind, DynamicKind.forward);
      expect(repost.typeName, 'DYNAMIC_TYPE_FORWARD');
      expect(repost.author.mid, 20000001);
      expect(repost.author.name, '测试转发者');
      expect(repost.author.pubTime, '8分钟前');
      expect(repost.major, isNull);
      expect(shapes(repost), [
        ('text', '转发一下 '),
        ('emoji', '[测试表情]', 'https://i0.hdslb.com/bfs/emote/fake-icon.png', false),
        ('text', ' 好看'),
      ]);
      expect(repost.comments, const CommentArea(oid: 1100000000000000001, type: 17));
      expect(repost.stat.comment, 3);
      expect(repost.stat.like, 2);
      expect(repost.stat.favourite, isNull);
      expect(repost.menu, [DynamicMenuItem.unfollow, DynamicMenuItem.report]);

      final original = repost.original!;
      expect(original.id, '1100000000000000011');
      expect(original.kind, DynamicKind.video);
      expect(original.author.name, '测试原作者');
      expect(original.author.pubAction, '投稿了视频');
      expect(original.author.following, isFalse);
      expect(original.menu, isEmpty);
      expect(original.stat.like, 0);
      expect(original.original, isNull);
      final video = original.major! as DynamicVideo;
      expect(video.aid, 115000000000011);
      expect(video.bvid, 'BV1FakeOrg011');
      expect(video.title, '被转发的测试视频');
      expect(video.durationText, '21:50');
      expect(video.duration, 1310);
      expect(video.plays, '5.6万');
      expect(video.danmaku, '348');
      expect(video.badge, '', reason: '投稿视频 is sent as no badge');
    });

    test('a picture post takes its text, pictures and goods from the opus', () {
      final post = page.items[1];
      expect(post.kind, DynamicKind.draw);
      expect(shapes(post), [('text', '今天的图\n'), ('badge', '测试商品链接', 'goods')]);
      expect(post.foldedLines, isFalse, reason: 'every opus sends fold_action; only has_more means a cut');
      final pictures = post.major! as DynamicPictures;
      expect(pictures.title, '');
      expect(pictures.pictures.single.url, 'https://i0.hdslb.com/bfs/new_dyn/fake-pic-1.jpg');
      expect(pictures.pictures.single.width, 1080);
      expect(pictures.pictures.single.height, 1350);
      final goods = post.goods!;
      expect(goods.headText, 'UP主的推荐');
      expect(goods.items.map((item) => (item.name, item.cover, item.brief, item.jumpText)), [
        ('测试商品一', 'https://i0.hdslb.com/bfs/mall/fake-goods-1.png', '最高100元', '去看看'),
        ('测试商品二', 'https://i0.hdslb.com/bfs/mall/fake-goods-2.png', '', '去看看'),
      ]);
      expect(post.comments, const CommentArea(oid: 300000002, type: 11));
      expect((post.stat.forward, post.stat.comment, post.stat.like), (9, 100, 388));
    });

    test('the author row: 大会员, verification and the fan card', () {
      final painter = page.items[1].author;
      expect(painter.vipPink, isTrue);
      expect(painter.verify, DynamicVerify.personal);
      expect(painter.decoration!.cardUrl, 'https://i0.hdslb.com/bfs/garb/fake-card.png');
      expect(painter.decoration!.number, '000011');
      expect(painter.decoration!.colour, 0xFFFFB48E);
      expect(painter.following, isTrue);

      final official = page.items[2].author;
      expect(official.verify, DynamicVerify.organisation);
      expect(official.pubAction, '发布了动态视频');
      expect(official.decoration, isNull);

      final plain = page.items[3].author;
      expect(plain.vipPink, isFalse, reason: 'no 大会员 type');
      expect(plain.verify, DynamicVerify.none);
      expect(plain.pubTime, '昨天 10:10');
      expect(page.items[4].author.vipPink, isFalse, reason: 'a lapsed 大会员 (status 0)');
    });

    test('the avatar frame is pendant.image, empty when the pendant is empty or not sent', () {
      expect(page.items[1].author.pendant, 'https://i0.hdslb.com/bfs/garb/fake-pendant.png');
      expect(page.items[2].author.pendant, '');
      expect(page.items[3].author.pendant, '');
    });

    test('a video post: every kind of text node, the video box and its comment area', () {
      final post = page.items[2];
      expect(post.kind, DynamicKind.video);
      expect(shapes(post), [
        ('topic', '#测试话题#'),
        ('text', ' 看 '),
        ('at', '@测试路人', 20000099),
        ('text', ' '),
        ('link', '网页链接', 'https://www.bilibili.com/blackboard/fake.html'),
        ('emoji', '[测试大表情]', 'https://i0.hdslb.com/bfs/emote/fake-big.webp', true),
        ('video', '测试视频链接', 'BV1FakeLnk003'),
      ]);
      final video = post.major! as DynamicVideo;
      expect(video.aid, 115000000000003);
      expect(video.bvid, 'BV1FakeAvi003');
      expect(video.cover, 'https://i0.hdslb.com/bfs/archive/fake-cover-115000000000003.jpg');
      expect((video.durationText, video.duration), ('00:56', 56));
      expect((video.plays, video.danmaku), ('37.1万', '1233'));
      expect(video.badge, '动态视频');
      expect(post.goods, isNull, reason: 'only goods are drawn from additional');
      expect(post.comments, const CommentArea(oid: 115000000000003, type: 1));
    });

    test('a comment area sent as type 0 falls back to the aid for a video, rid_str for pictures', () {
      final video = page.items[3];
      expect((video.major! as DynamicVideo).duration, 3723, reason: '1:02:03');
      expect(video.comments, const CommentArea(oid: 115000000000004, type: 1));

      final pictures = page.items[4];
      expect(pictures.comments, const CommentArea(oid: 300000005, type: 11));
      expect((pictures.major! as DynamicPictures).pictures, hasLength(4));
      expect(pictures.stat.liked, isTrue);
      expect(pictures.stat.like, 7);
    });

    test('an article: its title on the pictures, its cut text folded', () {
      final article = page.items[5];
      expect(article.kind, DynamicKind.article);
      expect(shapes(article), [('text', '专栏的开头一段')]);
      expect(article.foldedLines, isTrue);
      final major = article.major! as DynamicPictures;
      expect(major.title, '测试专栏标题');
      expect(major.pictures.single.width, 1200);
      expect(article.comments, const CommentArea(oid: 40000006, type: 12));
    });
  });

  group('rarer kinds', () {
    late DynamicPage page;
    setUp(() => page = pageOf('feed_kinds'));

    test('a numeric offset and the last page', () {
      expect(page.offset, '1100000000000000199');
      expect(page.hasMore, isFalse);
      expect(page.skipped, {'orig:DYNAMIC_TYPE_AV': 1}, reason: 'only the reduced original; no item dropped');
      expect(page.items, hasLength(9));
    });

    test('a text post: badges, unknown nodes, nodes missing their target, a cut desc', () {
      final post = page.items[0];
      expect(post.kind, DynamicKind.word);
      expect(post.major, isNull);
      expect(shapes(post), [
        ('badge', '互动抽奖', 'lottery'),
        ('text', ' 来抽 '),
        ('badge', '测试投票', 'vote'),
        ('badge', '测试番剧', 'RICH_TEXT_NODE_TYPE_OGV_SEASON'),
        ('text', '@没有编号'),
        ('text', '失效链接'),
        ('video', '测试旧编号', avToBv(170001)),
        ('text', '很长的字'),
      ]);
      expect(post.foldedLines, isTrue);
      expect(post.author.location, 'IP属地：上海');
      expect(post.menu, [DynamicMenuItem.report, DynamicMenuItem.other]);
      expect(post.comments, const CommentArea(oid: 1100000000000000101, type: 17));
    });

    test('a text post whose opus has no picture has no body', () {
      final post = page.items[1];
      expect(post.kind, DynamicKind.word);
      expect(post.major, isNull);
      expect(shapes(post), [('text', '只有字的图文')]);
    });

    test('a text post or repost sent as type 0 takes its own id as type 17', () {
      expect(page.items[1].comments, const CommentArea(oid: 1100000000000000102, type: 17));
      expect(page.items[6].kind, DynamicKind.forward);
      expect(page.items[6].comments, const CommentArea(oid: 1100000000000000107, type: 17));
    });

    test('直播推荐 reads its title and cover out of the content string', () {
      final post = page.items[2];
      expect(post.kind, DynamicKind.live);
      final major = post.major! as DynamicOtherMajor;
      expect(major.typeName, 'MAJOR_TYPE_LIVE_RCMD');
      expect(major.title, '测试直播间');
      expect(major.cover, 'https://i0.hdslb.com/bfs/live/fake-cover.jpg');
      expect(post.comments, isNull, reason: 'type 0 and not a video or picture post: the detail is asked');
    });

    test('番剧 is pgc with its title and cover', () {
      final post = page.items[3];
      expect(post.kind, DynamicKind.pgc);
      final major = post.major! as DynamicOtherMajor;
      expect(
        (major.typeName, major.title, major.cover),
        ('MAJOR_TYPE_PGC', '测试番剧 第1话', 'https://i0.hdslb.com/bfs/bangumi/fake.jpg'),
      );
    });

    test('a 合集 update is a video, its BV id made from the aid when not sent', () {
      final post = page.items[4];
      expect(post.kind, DynamicKind.video);
      final video = post.major! as DynamicVideo;
      expect(video.aid, 170001);
      expect(video.bvid, avToBv(170001));
      expect((video.duration, video.plays, video.danmaku), (187, '1024', '8'));
      expect(post.comments, const CommentArea(oid: 115000000000105, type: 1));
    });

    test('an unknown kind is other, its body named by its major type, its plain text kept', () {
      final post = page.items[5];
      expect(post.kind, DynamicKind.other);
      expect(post.typeName, 'DYNAMIC_TYPE_COMMON_SQUARE');
      expect(shapes(post), [('text', '只有纯文本')]);
      final major = post.major! as DynamicOtherMajor;
      expect((major.typeName, major.title), ('MAJOR_TYPE_COMMON', '测试卡片'));
    });

    test('a repost of a deleted post keeps the original with its tips', () {
      final original = page.items[6].original!;
      expect(original.kind, DynamicKind.other);
      expect(original.typeName, 'DYNAMIC_TYPE_NONE');
      expect(original.id, '');
      expect(original.author.mid, 0);
      final major = original.major! as DynamicOtherMajor;
      expect((major.typeName, major.title), ('MAJOR_TYPE_NONE', '源动态已被作者删除'));
      expect(original.comments, isNull);
    });

    test('a repost whose original will not decode keeps its place, the original reduced to its kind', () {
      final repost = page.items[7];
      expect(shapes(repost), [('text', '坏的')]);
      final original = repost.original!;
      expect(original.id, '1100000000000000118');
      expect(original.kind, DynamicKind.video);
      expect(original.typeName, 'DYNAMIC_TYPE_AV');
      expect(original.major, isNull);
      expect(original.author.name, '');
      expect(page.skipped, {'orig:DYNAMIC_TYPE_AV': 1});
    });

    test('an unreadable original counts as orig:unknown unless its repost is dropped; a text original without an id '
        'has no comment area', () {
      Map<String, Object?> repost(String id, Object? orig) => {
        'id_str': id,
        'type': 'DYNAMIC_TYPE_FORWARD',
        'modules': {
          'module_author': {'mid': 20000501, 'name': '测试转发者'},
        },
        'orig': orig,
      };
      final page = DynamicDecode.page({
        'items': [
          repost('1100000000000000501', 'not an original'),
          repost('1100000000000000502', {
            'type': 'DYNAMIC_TYPE_WORD',
            'basic': {'rid_str': '', 'comment_type': 0, 'comment_id_str': ''},
          }),
          {
            'id_str': '1100000000000000503',
            'type': 'DYNAMIC_TYPE_FORWARD',
            'modules': {
              'module_author': {'name': '没有编号的转发者'},
            },
            'orig': 'dropped with its repost',
          },
        ],
      });
      expect(page.items.map((item) => item.id), ['1100000000000000501', '1100000000000000502']);
      expect(page.skipped, {'orig:unknown': 1, 'DYNAMIC_TYPE_FORWARD': 1});
      expect(page.items[0].original!.kind, DynamicKind.other);
      final text = page.items[1].original!;
      expect(text.kind, DynamicKind.word);
      expect(text.comments, isNull);
    });

    test('the old picture body, and counts sent as strings, "--" or below zero', () {
      final post = page.items[8];
      expect(post.kind, DynamicKind.draw);
      final pictures = (post.major! as DynamicPictures).pictures;
      expect(pictures.map((picture) => (picture.url, picture.width, picture.height)), [
        ('https://i0.hdslb.com/bfs/album/fake-old-1.jpg', 800, 600),
      ]);
      expect((post.stat.forward, post.stat.comment, post.stat.like), (0, 0, 12));
      expect(post.stat.liked, isTrue);
      expect(post.menu, isEmpty);
    });
  });

  test('a space feed marks its pinned post', () {
    final page = pageOf('feed_space');
    expect(page.items.single.pinned, isTrue);
    expect(page.items.single.menu, [DynamicMenuItem.report]);
    expect(pageOf('feed_all').items.any((item) => item.pinned), isFalse);
  });

  group('the detail', () {
    test('a post with its IP属地, full time, ⭐ and liked state', () {
      final item = decoded('detail', DynamicDecode.detail);
      expect(item.id, '1100000000000000301');
      expect(item.author.location, 'IP属地：浙江');
      expect(item.author.pubTime, '2026年10月26日 17:19');
      expect(shapes(item), [('text', '详情的完整文字')]);
      expect((item.stat.forward, item.stat.comment, item.stat.like), (4, 5, 6));
      expect(item.stat.liked, isTrue);
      expect(item.stat.favourite, 414);
      expect(item.menu, [DynamicMenuItem.report]);
      expect(item.comments, const CommentArea(oid: 1100000000000000301, type: 17));

      final original = item.original!;
      expect(original.kind, DynamicKind.draw);
      expect(shapes(original), [('text', '原图的字')]);
      expect((original.major! as DynamicPictures).pictures, hasLength(1));
      expect(original.comments, isNull, reason: 'type 0 with no rid_str: the post page asks its own detail');
    });

    test('takes the item itself as well as data', () {
      final data = (jsonDecode(fixture('detail')) as Map<String, Object?>)['data']! as Map<String, Object?>;
      expect(DynamicDecode.detail(data['item']).id, '1100000000000000301');
    });

    test('an item without its id is an error, not an empty post', () {
      expect(() => DynamicDecode.detail({'item': <String, Object?>{}}), throwsA(isA<DecodeError>()));
    });
  });

  group('最常访问', () {
    test('the portal: its up_list, a face without a usable mid dropped', () {
      final ups = decoded('portal', DynamicDecode.ups);
      expect(ups.ups.map((up) => (up.mid, up.name, up.face, up.hasUpdate)), [
        (20000901, '测试常看一', 'https://i0.hdslb.com/bfs/face/fake-up-20000901.jpg', true),
        (20000902, '测试常看二', 'https://i0.hdslb.com/bfs/face/fake-up-20000902.jpg', false),
      ]);
      expect(ups.offset, 'fake-offset-portal-0001');
      expect(ups.hasMore, isTrue);
    });

    test('uplist: the next page, data itself', () {
      final ups = decoded('uplist', DynamicDecode.ups);
      expect(ups.ups.single.mid, 20000903);
      expect(ups.offset, 'fake-offset-portal-0002');
      expect(ups.hasMore, isFalse);
    });
  });

  group('我的关注', () {
    FollowingPage followings(int page) =>
        decoded('followings', (json) => DynamicDecode.followings(json, page: page, pageSize: 20));

    test('rows with verification and 大会员, a row without a mid dropped', () {
      final page = followings(1);
      expect(page.users.map((user) => (user.mid, user.name, user.sign, user.verify, user.vipPink)), [
        (20001001, '测试关注一', '测试签名', DynamicVerify.personal, true),
        (20001002, '测试关注二', '', DynamicVerify.organisation, false),
        (20001003, '测试关注三', '测试签名', DynamicVerify.none, false),
      ]);
      expect(page.users.first.face, 'https://i0.hdslb.com/bfs/face/fake-follow-20001001.jpg');
      expect(page.total, 45);
    });

    test('more while page × size is under the total', () {
      expect(followings(1).hasMore, isTrue);
      expect(followings(2).hasMore, isTrue);
      expect(followings(3).hasMore, isFalse);
    });

    test('an empty page ends it whatever the total; without a total, a full page asks for more', () {
      expect(DynamicDecode.followings({'list': <Object?>[], 'total': 45}, page: 1, pageSize: 20).hasMore, isFalse);
      final full = [
        for (var i = 0; i < 20; i++) {'mid': i + 1, 'uname': '测试$i'},
      ];
      expect(DynamicDecode.followings({'list': full}, page: 1, pageSize: 20).hasMore, isTrue);
      expect(DynamicDecode.followings({'list': full.sublist(0, 5)}, page: 1, pageSize: 20).hasMore, isFalse);
    });
  });

  test('我的追番: posters with their progress, paged by the total', () {
    final first = decoded('bangumi', (json) => DynamicDecode.bangumi(json, page: 1, pageSize: 15));
    expect(first.items.map((season) => (season.seasonId, season.title, season.cover, season.progress)), [
      (81001, '测试番剧一', 'https://i0.hdslb.com/bfs/bangumi/fake-81001.jpg', '全23话'),
      (81002, '测试番剧二', 'https://i0.hdslb.com/bfs/bangumi/fake-81002.jpg', '更新至第5话'),
    ]);
    expect(first.total, 17);
    expect(first.hasMore, isTrue);
    expect(decoded('bangumi', (json) => DynamicDecode.bangumi(json, page: 2, pageSize: 15)).hasMore, isFalse);
  });
}
