import 'package:bili_core/api.dart';
import 'package:bilifast/message/feed/feed_targets.dart';
import 'package:bilifast/message/feed/like_row.dart';
import 'package:bilifast/message/feed/reply_row.dart';
import 'package:flutter_test/flutter_test.dart';

import 'feed_support.dart';

void main() {
  test('av to BV as Bilibili publishes it', () {
    expect(avToBv(170001), 'BV17x411w7KC');
    expect(avToBv(2), 'BV1xx411c7mD');
  });

  test('a reply on a video: the link\'s BV, else its av, else the aid; the thread is its root, else itself', () {
    final linked = replyTarget(reply(1, rootId: 5, sourceId: 6, nativeUri: 'bilibili://video/BV1Ab4y1C7De?page=1'));
    expect(linked, isA<FeedVideo>().having((target) => target.bvid, 'bvid', 'BV1Ab4y1C7De'));
    expect((linked as FeedVideo).comment?.root, 5);
    expect(linked.comment?.reply, 6);
    final av = replyTarget(reply(2, subjectId: 9, uri: 'https://www.bilibili.com/video/av170001'));
    expect((av as FeedVideo).bvid, 'BV17x411w7KC');
    final bare = replyTarget(reply(3, subjectId: 2, sourceId: 30));
    expect((bare as FeedVideo).bvid, 'BV1xx411c7mD');
    expect(bare.comment?.root, 30);
  });

  test('a post: 17 by its subject, 11 only by its link; an @ in the post itself opens the post', () {
    expect(replyTarget(reply(1, businessId: 17, subjectId: 44)), isA<FeedPost>().having((p) => p.id, 'id', '44'));
    expect(replyTarget(reply(2, businessId: 11, subjectId: 44)), isA<FeedNowhere>());
    final mention = replyTarget(reply(3, feed: NoticeFeed.at, business: 'dynamic', businessId: 17, subjectId: 44));
    expect((mention as FeedPost).toComments, isFalse);
    final inComment = replyTarget(reply(4, feed: NoticeFeed.at, business: 'reply', businessId: 17, subjectId: 44));
    expect((inComment as FeedPost).toComments, isTrue);
  });

  test('an article or anything else is nowhere yet', () {
    expect(replyTarget(reply(1, businessId: 12, business: 'article')), isA<FeedNowhere>());
    expect(likeTarget(like(1, uri: 'https://www.bilibili.com/read/cv1')), isA<FeedNowhere>());
  });

  test('the action words for each kind and list', () {
    expect(replyAction(reply(1, business: 'reply')), '回复了我的评论');
    expect(replyAction(reply(1, business: 'video')), '评论了我的视频');
    expect(replyAction(reply(1, business: 'dynamic')), '评论了我的动态');
    expect(replyAction(reply(1, feed: NoticeFeed.at, business: 'reply')), '在评论中@了我');
    expect(replyAction(reply(1, feed: NoticeFeed.at, business: 'dynamic')), '在动态中@了我');
    expect(likedThing(like(1, business: '弹幕')), '我的弹幕');
  });

  test('a like\'s line: the newest two names, the count once more than one liked', () {
    final three = likeLine(
      like(
        1,
        users: [
          person(1, name: '甲'),
          person(2, name: '乙'),
          person(3),
        ],
        count: 3,
      ),
    );
    expect(three.names, ['甲', '乙']);
    expect(three.rest, '等总计3人赞了我的评论');
    expect(likeLine(like(2, users: [person(1, name: '甲')])).rest, '点赞了我的评论');
  });
}
