import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/feed/replies_page.dart';
import 'package:bilifast/message/settings/notice_picker_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home/fake_login_gate.dart';
import 'feed_support.dart';

void main() {
  late RecordingOpeners opens;

  setUp(() => opens = RecordingOpeners());

  Future<RecordingPageApi> open(
    WidgetTester tester,
    FakeMessageApi api, {
    bool mentions = false,
    bool loggedIn = true,
    FakeLoginGate? gate,
    void Function(RecordingMessages messages)? messages,
  }) async {
    final page = RecordingPageApi();
    final services = await feedServices(api, page: page, loggedIn: loggedIn, loginGate: gate);
    messages?.call(services.messages as RecordingMessages);
    await pumpFeed(tester, services, RepliesPage(mentions: mentions, opens: opens));
    return page;
  }

  String textOf(WidgetTester tester, String key) => tester.widget<Text>(byKey(key)).data!;

  /// Lets a toast go, so no timer is left at the end.
  Future<void> toastGone(WidgetTester tester) => settle(tester, 60);

  testWidgets('each reply says what it was: a reply, a comment on a video or on a post', (tester) async {
    final api = FakeMessageApi(
      replyList: [
        reply(1, fromUploader: true),
        reply(2, business: 'video'),
        reply(3, business: 'dynamic', businessId: 11),
      ],
    );
    await open(tester, api);
    expect(textOf(tester, 'feed-reply-action-1'), '回复了我的评论');
    expect(textOf(tester, 'feed-reply-action-2'), '评论了我的视频');
    expect(textOf(tester, 'feed-reply-action-3'), '评论了我的动态');
    expect(byKey('feed-reply-up-1'), findsOneWidget);
    expect(byKey('feed-reply-up-2'), findsNothing);
    expect(find.text('演示回复'), findsNWidgets(3), reason: 'what they wrote, emote codes as text');
    expect(api.calls, ['replies 0']);
  });

  testWidgets('@我 lists mentions in its own words, asked once its chip is chosen', (tester) async {
    final api = FakeMessageApi(
      replyList: [reply(1)],
      mentionList: [
        reply(5, feed: NoticeFeed.at, business: 'reply'),
        reply(6, feed: NoticeFeed.at, business: 'dynamic', businessId: 17),
      ],
    );
    await open(tester, api);
    expect(api.calls, ['replies 0']);
    await tester.tap(byKey('feed-chip-at'));
    await settle(tester);
    expect(textOf(tester, 'feed-reply-action-5'), '在评论中@了我');
    expect(textOf(tester, 'feed-reply-action-6'), '在动态中@了我');
    expect(api.calls, ['replies 0', 'mentions 0']);
    await tester.tap(byKey('feed-chip-all'));
    await settle(tester);
    expect(byKey('feed-reply-1'), findsOneWidget);
    expect(api.calls, ['replies 0', 'mentions 0'], reason: 'a list shown before is kept');
  });

  testWidgets('feedOpened is called for 回复与@ once', (tester) async {
    late RecordingMessages model;
    await open(tester, FakeMessageApi(replyList: [reply(1)]), messages: (messages) => model = messages);
    expect(model.opened, [NoticeFeed.reply]);
  });

  testWidgets('@我 with nothing shows the empty picture', (tester) async {
    await open(tester, FakeMessageApi(), mentions: true);
    expect(find.text('这里还什么都没有呢～'), findsOneWidget);
    expect(find.descendant(of: byKey('feed-mentions-list'), matching: find.byType(Image)), findsOneWidget);
  });

  testWidgets('回复 posts into the reply\'s comment area: a root is answered, a reply in a thread under its root', (
    tester,
  ) async {
    final api = FakeMessageApi(
      replyList: [
        reply(1, subjectId: 777, businessId: 1, rootId: 0, sourceId: 50),
        reply(2, subjectId: 888, businessId: 17, rootId: 60, sourceId: 61, user: person(2, name: '演示乙')),
      ],
    );
    final page = await open(tester, api);
    await tester.tap(byKey('feed-reply-reply-1'));
    await settle(tester);
    expect(find.text('回复 演示用户1 :'), findsOneWidget);
    await tester.enterText(byKey('composer-field'), '谢谢');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('发布'));
    await settle(tester, 20);
    expect(page.posts.last.root, 50);
    expect(page.posts.last.parent, 50);
    expect(page.posts.last.message, '谢谢');
    expect(page.areas.last, (call: 'post', aid: 777, type: 1));
    expect(find.text('发送成功'), findsOneWidget);
    expect(byKey('composer-field'), findsNothing, reason: 'a post closes the composer');
    await toastGone(tester);

    await tester.tap(byKey('feed-reply-reply-2'));
    await settle(tester);
    await tester.enterText(byKey('composer-field'), '好的');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('发布'));
    await settle(tester, 20);
    expect(page.posts.last.root, 60);
    expect(page.posts.last.parent, 61);
    expect(page.posts.last.message, '回复 @演示乙 :好的');
    expect(page.areas.last, (call: 'post', aid: 888, type: 17));
    await toastGone(tester);
  });

  testWidgets('logged out, the page asks nothing and offers 登录 through the login gate', (tester) async {
    final gate = FakeLoginGate();
    final api = FakeMessageApi(replyList: [reply(1)]);
    await open(tester, api, loggedIn: false, gate: gate);
    expect(byKey('feed-logged-out'), findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.tap(byKey('feed-login'));
    await settle(tester);
    expect(gate.requests, 1);
  });

  testWidgets('点赞 turns pink at once and is sent on the reply\'s area', (tester) async {
    final api = FakeMessageApi(replyList: [reply(1, subjectId: 777, businessId: 1, sourceId: 50)]);
    final page = await open(tester, api);
    expect(byKey('feed-reply-thumb-1-off'), findsOneWidget);
    await tester.tap(byKey('feed-reply-like-1'));
    await tester.pump();
    expect(byKey('feed-reply-thumb-1-on'), findsOneWidget);
    await settle(tester);
    expect(page.calls.last, 'likeComment rpid=50 on=true');
    expect(page.areas.last, (call: 'like', aid: 777, type: 1));
    await tester.tap(byKey('feed-reply-like-1'));
    await settle(tester);
    expect(byKey('feed-reply-thumb-1-off'), findsOneWidget);
    expect(page.calls.last, 'likeComment rpid=50 on=false');
  });

  testWidgets('a refused 点赞 goes back, with Bilibili\'s reason', (tester) async {
    final api = FakeMessageApi(replyList: [reply(1)]);
    final page = await open(tester, api);
    final answer = Completer<void>();
    page
      ..holds['likeComment'] = answer
      ..failures['likeComment'] = const BiliError.api(code: 12051, message: '操作过于频繁');
    await tester.tap(byKey('feed-reply-like-1'));
    await tester.pump();
    expect(byKey('feed-reply-thumb-1-on'), findsOneWidget);
    await tester.tap(byKey('feed-reply-like-1'));
    await tester.pump();
    expect(page.calls.where((call) => call.startsWith('likeComment')), hasLength(1), reason: 'one at a time');
    answer.complete();
    await settle(tester);
    expect(byKey('feed-reply-thumb-1-off'), findsOneWidget);
    expect(find.text('操作过于频繁'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('⋮: 不再通知 mutes the reply, 删除 removes its row once Bilibili agrees', (tester) async {
    final api = FakeMessageApi(replyList: [reply(1), reply(2)]);
    await open(tester, api);
    await tester.tap(byKey('feed-reply-more-1'));
    await settle(tester);
    expect(byKey('feed-sheet'), findsOneWidget);
    await tester.tap(byKey('feed-sheet-mute'));
    await settle(tester);
    expect(api.muted, [(feed: NoticeFeed.reply, id: 1)]);
    expect(find.text('设置成功'), findsOneWidget);
    expect(byKey('feed-sheet'), findsNothing);
    await toastGone(tester);

    await tester.tap(byKey('feed-reply-more-2'));
    await settle(tester);
    await tester.tap(byKey('feed-sheet-delete'));
    await settle(tester);
    expect(api.calls.last, 'deleteNotice reply 2');
    expect(byKey('feed-reply-2'), findsNothing);
    expect(byKey('feed-reply-1'), findsOneWidget);
    expect(find.text('删除成功'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('a tap on the dim puts the sheet away, and so does back', (tester) async {
    await open(tester, FakeMessageApi(replyList: [reply(1)]));
    await tester.tap(byKey('feed-reply-more-1'));
    await settle(tester);
    await tester.tapAt(const Offset(220, 300));
    await settle(tester);
    expect(byKey('feed-sheet'), findsNothing);
    await tester.tap(byKey('feed-reply-more-1'));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(byKey('feed-sheet'), findsNothing);
    expect(byKey('feed-reply-1'), findsOneWidget, reason: 'back closed the sheet, not the page');
  });

  testWidgets('a row opens its video on the reply\'s thread, by the link\'s BV or the aid', (tester) async {
    final api = FakeMessageApi(
      replyList: [
        reply(1, rootId: 70, sourceId: 71, uri: 'https://www.bilibili.com/video/BV1Ab4y1C7De'),
        reply(2, subjectId: 170001, rootId: 0, sourceId: 80),
      ],
    );
    await open(tester, api);
    await tester.tap(byKey('feed-reply-1'));
    await tester.tap(byKey('feed-reply-2'));
    await settle(tester);
    expect([for (final route in opens.videos) route.bvid], ['BV1Ab4y1C7De', 'BV17x411w7KC']);
    expect(opens.videos[0].comment?.root, 70);
    expect(opens.videos[0].comment?.reply, 71);
    expect(opens.videos[1].comment?.root, 80);
    expect(opens.videos[1].comment?.reply, 80);
  });

  testWidgets('a row on a post opens it on its comments; anything else isn\'t open yet', (tester) async {
    final api = FakeMessageApi(
      replyList: [
        reply(1, businessId: 11, subjectId: 5, uri: 'https://t.bilibili.com/9876543210'),
        reply(2, businessId: 17, subjectId: 1234567),
        reply(3, business: 'article', businessId: 12),
      ],
    );
    await open(tester, api);
    await tester.tap(byKey('feed-reply-1'));
    await tester.tap(byKey('feed-reply-2'));
    await settle(tester);
    expect(opens.posts, [('9876543210', true), ('1234567', true)]);
    await tester.tap(byKey('feed-reply-3'));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('the face opens the replier\'s space', (tester) async {
    await open(
      tester,
      FakeMessageApi(
        replyList: [reply(1, user: person(42, name: '演示丙'))],
      ),
    );
    await tester.tap(byKey('feed-reply-face-1'));
    await settle(tester);
    expect(opens.spaces.single.mid, 42);
    expect(opens.spaces.single.name, '演示丙');
    expect(opens.videos, isEmpty);
  });

  testWidgets('near the end the next page is asked, one call at a time', (tester) async {
    final api = FakeMessageApi(replyList: [for (var id = 1; id <= 30; id++) reply(id)], pageSize: 10);
    await open(tester, api);
    expect(api.calls, ['replies 0', 'replies 10'], reason: 'ten rows leave the end within a screen');
    await tester.drag(byKey('feed-replies-list'), const Offset(0, -600));
    await settle(tester);
    expect(api.calls, ['replies 0', 'replies 10', 'replies 20']);
    for (var i = 0; i < 3; i++) {
      await tester.drag(byKey('feed-replies-list'), const Offset(0, -2000));
      await settle(tester);
    }
    expect(api.calls, hasLength(3), reason: 'the list has ended');
    expect(byKey('feed-reply-30'), findsOneWidget);
  });

  testWidgets('a first page that fails offers 重试', (tester) async {
    final api = FakeMessageApi(replyList: [reply(1)]);
    api.failures['replies'] = const BiliError.http(500);
    await open(tester, api);
    expect(byKey('feed-replies-failed'), findsOneWidget);
    api.failures.clear();
    await tester.tap(byKey('feed-replies-retry'));
    await settle(tester);
    expect(byKey('feed-reply-1'), findsOneWidget);
  });

  testWidgets('to accessibility the row is one button and its face, 回复, 点赞 and ⋮ stay buttons of their own', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final api = FakeMessageApi(replyList: [reply(1, user: person(1, name: '演示甲'), text: '演示内容')]);
    final page = await open(tester, api);
    expect(find.bySemanticsLabel(RegExp('^演示甲回复了我的评论：演示内容')), findsOneWidget);
    for (final label in ['演示甲', '回复', '点赞', '更多']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    tester.semantics.tap(find.semantics.byLabel('点赞'));
    await settle(tester);
    expect(page.calls.last, 'likeComment rpid=10 on=true');
    semantics.dispose();
  });

  testWidgets('the gear opens 回复与@\'s 消息提醒', (tester) async {
    await open(tester, FakeMessageApi(replyList: [reply(1)]));
    await tester.tap(byKey('feed-gear'));
    await settle(tester);
    expect(tester.widget<NoticePickerPage>(find.byType(NoticePickerPage)).kind, NoticeSettingKind.replies);
  });
}
