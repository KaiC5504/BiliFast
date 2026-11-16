import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/feed/likes_page.dart';
import 'package:bilifast/message/settings/notice_picker_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'feed_support.dart';

void main() {
  late RecordingOpeners opens;

  setUp(() => opens = RecordingOpeners());

  Future<RecordingMessages> open(WidgetTester tester, FakeMessageApi api) async {
    final services = await feedServices(api);
    await pumpFeed(tester, services, LikesPage(opens: opens));
    return services.messages as RecordingMessages;
  }

  String lineOf(WidgetTester tester, int id) => tester
      .widget<RichText>(find.descendant(of: byKey('feed-like-line-$id'), matching: find.byType(RichText)))
      .text
      .toPlainText(includePlaceholders: false);

  Future<void> toastGone(WidgetTester tester) => settle(tester, 60);

  testWidgets('two likers read "A 、B 等总计N人赞了…", one "A 点赞了…", by what was liked', (tester) async {
    final api = FakeMessageApi(
      likeList: [
        like(
          1,
          users: [
            person(1, name: '演示甲'),
            person(2, name: '演示乙'),
          ],
          count: 12,
        ),
        like(
          3,
          users: [person(3, name: '演示丙')],
          business: '弹幕',
        ),
        like(
          4,
          users: [person(4, name: '演示丁')],
          count: 5,
          business: '视频',
        ),
      ],
    );
    final messages = await open(tester, api);
    expect(lineOf(tester, 1), '演示甲 、演示乙等总计12人赞了我的评论');
    expect(lineOf(tester, 3), '演示丙点赞了我的弹幕');
    expect(lineOf(tester, 4), '演示丁等总计5人赞了我的视频');
    expect(messages.opened, [NoticeFeed.like]);
    expect(api.calls, ['likes 0']);
  });

  testWidgets('⋮: 不再通知 mutes the like, 删除 removes its row; a muted one offers only 删除', (tester) async {
    final api = FakeMessageApi(likeList: [like(1), like(2), like(3, notifying: false)]);
    await open(tester, api);
    await tester.tap(byKey('feed-like-more-1'));
    await settle(tester);
    await tester.tap(byKey('feed-sheet-mute'));
    await settle(tester);
    expect(api.muted, [(feed: NoticeFeed.like, id: 1)]);
    await toastGone(tester);

    await tester.tap(byKey('feed-like-more-1'));
    await settle(tester);
    expect(byKey('feed-sheet-mute'), findsNothing, reason: 'muted this visit');
    await tester.tap(byKey('feed-sheet-dim'));
    await settle(tester);

    await tester.tap(byKey('feed-like-more-3'));
    await settle(tester);
    expect(byKey('feed-sheet-mute'), findsNothing);
    await tester.tap(byKey('feed-sheet-delete'));
    await settle(tester);
    expect(api.calls.last, 'deleteNotice like 3');
    expect(byKey('feed-like-3'), findsNothing);
    await toastGone(tester);
  });

  testWidgets('a failed 删除 keeps the row and says why', (tester) async {
    final api = FakeMessageApi(likeList: [like(1)]);
    api.failures['deleteNotice'] = const BiliError.api(code: -400, message: '');
    await open(tester, api);
    await tester.tap(byKey('feed-like-more-1'));
    await settle(tester);
    await tester.tap(byKey('feed-sheet-delete'));
    await settle(tester);
    expect(byKey('feed-like-1'), findsOneWidget);
    expect(find.byKey(const ValueKey('toast')), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('a liked comment opens its video on the thread, a post its comments, else 暂未开放', (tester) async {
    final api = FakeMessageApi(
      likeList: [
        like(
          1,
          nativeUri: 'bilibili://video/170001?comment_root_id=90&comment_secondary_id=91',
          uri: 'https://www.bilibili.com/video/av170001',
        ),
        like(2, business: '弹幕', uri: 'https://www.bilibili.com/video/BV1Ab4y1C7De'),
        like(3, uri: 'https://www.bilibili.com/opus/123456'),
        like(4, business: '专栏', uri: 'https://www.bilibili.com/read/cv1'),
      ],
    );
    await open(tester, api);
    await tester.tap(byKey('feed-like-1'));
    await tester.tap(byKey('feed-like-2'));
    await tester.tap(byKey('feed-like-3'));
    await settle(tester);
    expect([for (final route in opens.videos) route.bvid], ['BV17x411w7KC', 'BV1Ab4y1C7De']);
    expect(opens.videos[0].comment?.root, 90);
    expect(opens.videos[0].comment?.reply, 91);
    expect(opens.videos[1].comment, isNull);
    expect(opens.posts, [('123456', true)]);
    await tester.tap(byKey('feed-like-4'));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('the faces open the newest liker\'s space', (tester) async {
    await open(
      tester,
      FakeMessageApi(
        likeList: [
          like(1, users: [person(7), person(8)], count: 2),
        ],
      ),
    );
    await tester.tap(byKey('feed-like-face-1'));
    await settle(tester);
    expect(opens.spaces.single.mid, 7);
  });

  testWidgets('pages come one after another near the end', (tester) async {
    final api = FakeMessageApi(likeList: [for (var id = 1; id <= 50; id++) like(id)], pageSize: 25);
    await open(tester, api);
    expect(api.calls, ['likes 0']);
    await tester.drag(byKey('feed-likes-list'), const Offset(0, -600));
    await settle(tester);
    expect(api.calls, ['likes 0', 'likes 25']);
    for (var i = 0; i < 3; i++) {
      await tester.drag(byKey('feed-likes-list'), const Offset(0, -2000));
      await settle(tester);
    }
    expect(api.calls, hasLength(2));
    expect(byKey('feed-like-50'), findsOneWidget);
  });

  testWidgets('nobody liked anything: the empty picture', (tester) async {
    await open(tester, FakeMessageApi());
    expect(find.text('这里还什么都没有呢～'), findsOneWidget);
  });

  testWidgets('a pull asks the first page again and shows what came', (tester) async {
    final api = FakeMessageApi(likeList: [like(1)]);
    await open(tester, api);
    api.likeList.insert(0, like(9));
    await tester.fling(byKey('feed-likes-list'), const Offset(0, 300), 1500);
    await settle(tester, 30);
    expect(api.calls, ['likes 0', 'likes 0']);
    expect(byKey('feed-like-9'), findsOneWidget);
  });

  testWidgets('the gear opens 收到喜欢\'s 消息提醒', (tester) async {
    await open(tester, FakeMessageApi(likeList: [like(1)]));
    await tester.tap(byKey('feed-gear'));
    await settle(tester);
    expect(tester.widget<NoticePickerPage>(find.byType(NoticePickerPage)).kind, NoticeSettingKind.likes);
  });
}
