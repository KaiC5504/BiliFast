import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'comment_fixtures.dart';

/// Root 1 with 25 replies, 20 to a page: reply 100 + n is the n-th oldest.
FakePageApi threadApi() {
  final replies = [for (var n = 1; n <= 25; n++) comment(100 + n, root: 1, parent: 1, ctime: n, likes: n)];
  return FakePageApi()
    ..commentList = [comment(1, replyCount: 25, preview: replies.take(3).toList()), comment(2)]
    ..threadReplies = {1: replies};
}

void main() {
  group('a thread opened by its root\'s rpid (a reply notification\'s)', () {
    test('asks for the first page by time and shows the root that page brings, with its replies', () async {
      final rig = CommentsRig(api: threadApi());
      expect(await rig.model.openThreadByRoot(1, reply: 105), isTrue);
      expect(rig.callsTo('thread'), ['thread root=1 page=1 sort=time']);
      final thread = rig.model.thread!;
      expect(thread.root.rpid, 1);
      expect(thread.root.message, '第1条评论');
      expect(rpids(thread.replies), [for (var n = 1; n <= 20; n++) 100 + n]);
      expect((thread.page, thread.total, thread.isEnd, thread.sort), (1, 25, false, CommentSort.time));
      expect(thread.focus, 105);
      expect(rig.toasts, isEmpty);
    });

    test('a reply not on the first page is no focus; the thread still opens', () async {
      final rig = CommentsRig(api: threadApi());
      expect(await rig.model.openThreadByRoot(1, reply: 124), isTrue);
      expect(rig.model.thread!.focus, isNull);
      expect(await rig.model.openThreadByRoot(1), isTrue);
      expect(rig.model.thread!.focus, isNull);
    });

    test('pages on from there and keeps the focus; another sort drops it', () async {
      final rig = CommentsRig(api: threadApi());
      await rig.model.openThreadByRoot(1, reply: 105);
      await rig.model.loadMoreThread();
      expect(rpids(rig.model.thread!.replies), [for (var n = 1; n <= 25; n++) 100 + n]);
      expect(rig.model.thread!.focus, 105);
      await rig.model.setThreadSort(CommentSort.hot);
      expect(rig.model.thread!.focus, isNull);
    });

    test('keeps the list\'s word that the root is pinned', () async {
      final api = threadApi()
        ..commentList = []
        ..pinnedComment = comment(1, isPinned: true, replyCount: 25);
      final rig = CommentsRig(api: api);
      await rig.model.ensureLoaded();
      api.pinnedComment = comment(1, replyCount: 25);
      await rig.model.openThreadByRoot(1);
      expect(rig.model.thread!.root.isPinned, isTrue);
    });

    test('a root deleted opens nothing and toasts Bilibili\'s words', () async {
      final api = threadApi()..failures['thread'] = const BiliError.api(code: 12022, message: '已经被删除了');
      final rig = CommentsRig(api: api);
      expect(await rig.model.openThreadByRoot(1, reply: 105), isFalse);
      expect(rig.model.thread, isNull);
      expect(rig.toasts, ['已经被删除了']);
    });

    test('a failed call opens nothing and toasts the network\'s wording', () async {
      final api = threadApi()..failures['thread'] = const BiliError.network('SocketException');
      final rig = CommentsRig(api: api);
      expect(await rig.model.openThreadByRoot(1), isFalse);
      expect(rig.model.thread, isNull);
      expect(rig.toasts, ['网络连接失败，请稍后再试']);
    });

    test('an answer that comes after another thread opened, or after a close, is dropped', () async {
      final api = threadApi();
      final rig = CommentsRig(api: api);
      final hold = api.holds['thread'] = Completer<void>();
      final late = rig.model.openThreadByRoot(1);
      final other = rig.model.openThread(comment(2));
      api.holds.remove('thread');
      hold.complete();
      expect(await late, isFalse);
      await other;
      expect(rig.model.thread!.root.rpid, 2);

      rig.model.closeThread();
      final held = api.holds['thread'] = Completer<void>();
      final closed = rig.model.openThreadByRoot(1);
      rig.model.closeThread();
      held.complete();
      expect(await closed, isFalse);
      expect(rig.model.thread, isNull);
      expect(rig.toasts, isEmpty);
    });

    test('a failure that comes after the model went says nothing', () async {
      final api = threadApi()..failures['thread'] = const BiliError.api(code: 12022, message: '已经被删除了');
      final rig = CommentsRig(api: api);
      final hold = api.holds['thread'] = Completer<void>();
      final open = rig.model.openThreadByRoot(1);
      rig.model.dispose();
      hold.complete();
      expect(await open, isFalse);
      expect(rig.toasts, isEmpty);
    });
  });

  group('the --fake-account demo', () {
    test('answers its notification\'s thread by the root\'s rpid, the reply on the first page by time', () async {
      final api = FakePageApi.demo()..delay = Duration.zero;
      final page = await api.thread(aid: 1, root: FakePageApi.demoFocusRoot, page: 1, sort: CommentSort.time);
      expect(page.root.rpid, FakePageApi.demoFocusRoot);
      expect(page.root.message, startsWith('前方高能'));
      final index = page.replies.indexWhere((reply) => reply.rpid == FakePageApi.demoFocusReply);
      expect(index, greaterThan(10), reason: 'far enough down to need the scroll');
      expect(page.replies, hasLength(20));
    });

    test('answers a root it doesn\'t hold as deleted, as Bilibili does', () async {
      final api = FakePageApi.demo()..delay = Duration.zero;
      await expectLater(
        api.thread(aid: 1, root: 1, page: 1, sort: CommentSort.time),
        throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', 12022)),
      );
    });
  });
}
