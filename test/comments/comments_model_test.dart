import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/comments/comments_model.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'comment_fixtures.dart';

/// Three top-level comments two to a page, and a pinned one.
FakePageApi pagedApi() => FakePageApi()
  ..commentList = [comment(1, ctime: 10), comment(2, ctime: 30), comment(3, ctime: 20)]
  ..pinnedComment = comment(9, isPinned: true)
  ..commentPageSize = 2;

/// Root 1 with 25 replies, 20 to a page: reply 100 + n is the n-th oldest, and the later ones have more likes.
FakePageApi threadApi() {
  final replies = [for (var n = 1; n <= 25; n++) comment(100 + n, root: 1, parent: 1, ctime: n, likes: n)];
  return FakePageApi()
    ..commentList = [comment(1, replyCount: 25, preview: replies.take(3).toList()), comment(2)]
    ..threadReplies = {1: replies};
}

void main() {
  group('the list', () {
    test('pages by offset, keeps the first page\'s pinned comment, and stops at the end', () async {
      final rig = CommentsRig(api: pagedApi());
      final model = rig.model;
      expect(model.sort, CommentSort.hot);

      await model.loadMore();
      expect(rpids(model.comments), [1, 2]);
      expect(model.pinned?.rpid, 9);
      expect(model.pinned?.isPinned, isTrue);
      expect(model.total, 4);
      expect(model.isEnd, isFalse);

      await model.loadMore();
      expect(rig.callsTo('comments'), ['comments sort=hot offset=', 'comments sort=hot offset=demo-offset-2']);
      expect(rpids(model.comments), [1, 2, 3]);
      expect(model.pinned?.rpid, 9, reason: 'a later page carries no pinned comment and must not clear it');
      expect(model.isEnd, isTrue);

      await model.loadMore();
      expect(rig.callsTo('comments'), hasLength(2), reason: 'nothing is asked for after the end');
    });

    test('takes the pinned comment and the total from the first page only, and drops repeated rpids', () async {
      final api = ScriptedApi()
        ..pages = (sort, offset) => offset == null
            ? CommentPage(
                comments: [comment(1), comment(2)],
                pinned: comment(9),
                nextOffset: 'B',
                isEnd: false,
                total: 50,
              )
            : CommentPage(comments: [comment(2), comment(9), comment(3)], pinned: comment(8), total: 99);
      final model = CommentsRig(api: api).model;

      await model.loadMore();
      await model.loadMore();
      expect(rpids(model.comments), [1, 2, 3], reason: 'the pinned 9 and the repeated 2 are already shown');
      expect(model.pinned?.rpid, 9);
      expect(model.total, 50);
    });

    test('ensureLoaded asks for the first page once', () async {
      final rig = CommentsRig(api: pagedApi());
      await Future.wait([rig.model.ensureLoaded(), rig.model.ensureLoaded()]);
      await rig.model.ensureLoaded();
      expect(rig.callsTo('comments'), hasLength(1));
      expect(rig.model.hasLoaded, isTrue);
    });

    test('a failed first page is not asked again by ensureLoaded, only by loadMore', () async {
      final rig = CommentsRig(api: pagedApi());
      rig.api.failures['comments'] = const BiliError.http(412);
      await rig.model.ensureLoaded();
      expect(rig.model.error, 'B 站暂时拒绝了请求（风控），稍后再试');
      expect(rig.model.loading, isFalse);
      expect(rig.model.comments, isEmpty);

      await rig.model.ensureLoaded();
      expect(rig.callsTo('comments'), hasLength(1), reason: 'no call repeats by itself');

      rig.api.failures.clear();
      await rig.model.loadMore();
      expect(rig.callsTo('comments'), ['comments sort=hot offset=', 'comments sort=hot offset=']);
      expect(rig.model.error, isNull);
      expect(rpids(rig.model.comments), [1, 2]);
    });

    test('a later page that fails keeps the list, and loadMore asks for the same offset again', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      rig.api.failures['comments'] = Exception('offline');
      await rig.model.loadMore();
      expect(rig.model.error, '网络连接失败，请稍后再试');
      expect(rpids(rig.model.comments), [1, 2]);
      expect(rig.model.isEnd, isFalse);

      rig.api.failures.clear();
      await rig.model.loadMore();
      expect(rig.callsTo('comments').last, 'comments sort=hot offset=demo-offset-2');
      expect(rpids(rig.model.comments), [1, 2, 3]);
    });

    test('a closed section shows the server\'s words and is not asked again', () async {
      final rig = CommentsRig(api: pagedApi());
      rig.api.failures['comments'] = const BiliError.api(code: 12061, message: 'UP主已关闭评论区');
      await rig.model.loadMore();
      expect(rig.model.closedMessage, 'UP主已关闭评论区');
      expect(rig.model.error, isNull);
      expect(rig.model.comments, isEmpty);
      expect(rig.model.loading, isFalse);
      expect(rig.model.hasLoaded, isTrue);

      await rig.model.loadMore();
      expect(rig.callsTo('comments'), hasLength(1));
    });

    test('code 12002 with no message reads 评论区已关闭', () async {
      final rig = CommentsRig(api: pagedApi());
      rig.api.failures['comments'] = const BiliError.api(code: 12002, message: '');
      await rig.model.loadMore();
      expect(rig.model.closedMessage, '评论区已关闭');
    });

    test('switching the sort starts again from the first page of the new sort', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      await rig.model.loadMore();

      await rig.model.setSort(CommentSort.time);
      expect(rig.model.sort, CommentSort.time);
      expect(rpids(rig.model.comments), [2, 3], reason: 'newest first, two to a page');
      expect(rig.model.isEnd, isFalse);
      expect(rig.callsTo('comments').last, 'comments sort=time offset=');
    });

    test('the first page for 热门 answering after the switch to 最新 is dropped', () async {
      final api = ScriptedApi()
        ..gated = true
        ..pages = (sort, offset) => sort == CommentSort.time
            ? CommentPage(comments: [comment(7), comment(8)], total: 2)
            : CommentPage(
                comments: [comment(1), comment(2)],
                pinned: comment(9),
                nextOffset: 'B',
                isEnd: false,
                total: 40,
              );
      final model = CommentsRig(api: api).model;
      final hot = model.loadMore();
      final time = model.setSort(CommentSort.time);
      expect(api.gates, hasLength(2));

      api.gates[1].complete();
      await time;
      api.gates[0].complete();
      await hot;
      expect(rpids(model.comments), [7, 8]);
      expect(model.pinned, isNull);
      expect(model.total, 2);
      expect(model.isEnd, isTrue);
      expect(model.loading, isFalse);
    });

    test('reload starts again, and an answer from before it is dropped', () async {
      var answered = 0;
      final api = ScriptedApi()
        ..gated = true
        ..pages = (sort, offset) => CommentPage(comments: [comment(++answered)], total: 1);
      final model = CommentsRig(api: api).model;
      final first = model.loadMore();
      final again = model.reload();
      api.gates[1].complete();
      await again;
      api.gates[0].complete();
      await first;
      expect(rpids(model.comments), [1], reason: 'the second answer is the one from before the reload');
      expect(api.calls, ['comments sort=hot offset=', 'comments sort=hot offset=']);
    });

    test('a server that keeps answering the same offset with nothing new ends the list', () async {
      final api = ScriptedApi()
        ..pages = (sort, offset) => const CommentPage(comments: [], nextOffset: 'same', isEnd: false);
      final model = CommentsRig(api: api).model;
      await model.loadMore();
      await model.loadMore();
      expect(model.isEnd, isTrue);
      await model.loadMore();
      expect(api.calls, hasLength(2));
    });

    test('three empty pages in a row end the list even with new offsets', () async {
      var asked = 0;
      final api = ScriptedApi()
        ..pages = (sort, offset) => CommentPage(comments: const [], nextOffset: 'o${++asked}', isEnd: false);
      final model = CommentsRig(api: api).model;
      for (var tap = 0; tap < 5; tap++) {
        await model.loadMore();
      }
      expect(api.calls, hasLength(3));
      expect(model.isEnd, isTrue);
    });

    test('tells its listeners when a page starts and when it lands', () async {
      final model = CommentsRig(api: pagedApi()).model;
      final seen = <bool>[];
      model.addListener(() => seen.add(model.loading));
      await model.loadMore();
      expect(seen, [true, false]);
    });

    test('an answer after the page let go of the model changes nothing', () async {
      final rig = CommentsRig(api: pagedApi());
      final hold = rig.api.holds['comments'] = Completer<void>();
      final load = rig.model.loadMore();
      rig.model.dispose();
      hold.complete();
      await load;
      expect(rig.model.comments, isEmpty);
    });
  });

  group('reactions', () {
    test('a like shows at once and is taken back with the server\'s words when refused', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      final hold = rig.api.holds['likeComment'] = Completer<void>();
      rig.api.failures['likeComment'] = const BiliError.api(code: 12015, message: '点赞过于频繁');

      final like = rig.model.toggleLike(rig.model.comments.first);
      expect(rig.model.comments.first.likes, 11, reason: 'the count moves before the server answers');
      expect(rig.model.comments.first.action, 1);
      expect(rig.callsTo('likeComment'), ['likeComment rpid=1 on=true']);

      hold.complete();
      await like;
      expect(rig.model.comments.first.likes, 10);
      expect(rig.model.comments.first.action, 0);
      expect(rig.toasts, ['点赞过于频繁']);
      expect(rig.logins, 0);
    });

    test('like and 踩 exclude each other, and the fake keeps what was sent', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      Comment first() => rig.model.comments.first;

      await rig.model.toggleLike(first());
      expect((first().likes, first().action), (11, 1));
      await rig.model.toggleHate(first());
      expect((first().likes, first().action), (10, 2), reason: '踩 takes the like back');
      await rig.model.toggleLike(first());
      expect((first().likes, first().action), (11, 1), reason: 'a like clears the 踩');
      await rig.model.toggleLike(first());
      expect((first().likes, first().action), (10, 0));
      await rig.model.toggleHate(first());
      await rig.model.toggleHate(first());
      expect((first().likes, first().action), (10, 0));
      expect(rig.callsTo('likeComment'), [
        'likeComment rpid=1 on=true',
        'likeComment rpid=1 on=true',
        'likeComment rpid=1 on=false',
      ]);
      expect(rig.callsTo('hateComment'), [
        'hateComment rpid=1 on=true',
        'hateComment rpid=1 on=true',
        'hateComment rpid=1 on=false',
      ]);
      expect(rig.api.commentList.first.action, 0);
      expect(rig.toasts, isEmpty);
    });

    test('a second tap on the same comment while the first is out does nothing', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      final hold = rig.api.holds['likeComment'] = Completer<void>();
      final first = rig.model.toggleLike(rig.model.comments.first);
      await rig.model.toggleLike(rig.model.comments.first);
      await rig.model.toggleHate(rig.model.comments.first);
      hold.complete();
      await first;
      expect(rig.api.calls.where((call) => call.contains('Comment rpid=1')), ['likeComment rpid=1 on=true']);
      expect(rig.model.comments.first.action, 1);
    });

    test('every copy of the comment changes: the list\'s preview and the open thread', () async {
      final rig = CommentsRig(api: threadApi());
      await rig.model.loadMore();
      await rig.model.openThread(rig.model.comments.first);
      final reply = rig.model.thread!.replies.first;
      expect(reply.rpid, 101);

      await rig.model.toggleLike(reply);
      expect(rig.model.thread!.replies.first.likes, 2);
      expect(rig.model.comments.first.previewReplies.first.likes, 2);
      expect(rig.model.comments.first.previewReplies.first.action, 1);
    });

    test('logged out, a reaction or a delete asks for the login and sends nothing', () async {
      final rig = CommentsRig(api: pagedApi(), loggedIn: false);
      await rig.model.loadMore();
      final first = rig.model.comments.first;

      await rig.model.toggleLike(first);
      await rig.model.toggleHate(first);
      expect(await rig.model.delete(first), isFalse);
      expect(rig.logins, 3);
      expect(rig.model.comments.first.likes, 10);
      expect(rig.callsTo('likeComment'), isEmpty);
      expect(rig.callsTo('hateComment'), isEmpty);
      expect(rig.callsTo('deleteComment'), isEmpty);
    });

    test('requireLogin answers true logged in, and asks for the login otherwise', () {
      final rig = CommentsRig();
      expect(rig.model.requireLogin(), isTrue);
      expect(rig.logins, 0);
      rig.loggedIn = false;
      expect(rig.model.requireLogin(), isFalse);
      expect(rig.logins, 1);
    });

    test('an expired login gets the login prompt alone', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      rig.api.failures['likeComment'] = const BiliError.api(code: -101, message: '账号未登录');
      await rig.model.toggleLike(rig.model.comments.first);
      expect(rig.logins, 1);
      expect(rig.toasts, isEmpty);
      expect(rig.model.comments.first.action, 0);
    });

    test('failure words: Bilibili\'s own for its refusals, the app\'s for the rest', () {
      expect(CommentsModel.messageFor(const BiliError.api(code: 12015, message: '评论发送过于频繁')), '评论发送过于频繁');
      expect(CommentsModel.messageFor(const BiliError.api(code: -352, message: '风控校验失败')), '请求过于频繁，请稍后再试');
      expect(CommentsModel.messageFor(const BiliError.api(code: 12022, message: '')), 'B 站返回错误 12022：');
      expect(CommentsModel.messageFor(const BiliError.http(500)), '网络请求失败（HTTP 500）');
      expect(CommentsModel.messageFor(StateError('bug')), '网络连接失败，请稍后再试');
    });

    test('isOwn compares the comment\'s mids with the account\'s', () {
      final rig = CommentsRig(mid: 2001);
      expect(rig.model.isOwn(comment(1)), isTrue);
      expect(rig.model.isOwn(comment(2, mid: 7)), isFalse);
      final byMember = Comment(rpid: 3, member: const CommentMember(mid: 2001), message: '');
      expect(rig.model.isOwn(byMember), isTrue, reason: 'a posted comment may carry its mid on the member alone');
      rig.mid = null;
      expect(rig.model.isOwn(comment(1)), isFalse);
    });
  });

  group('delete', () {
    test('removes the row once the server agrees and lowers the total', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      expect(await rig.model.delete(rig.model.comments[1]), isTrue);
      expect(rpids(rig.model.comments), [1]);
      expect(rig.model.total, 3);
      expect(rig.callsTo('deleteComment'), ['deleteComment rpid=2']);
    });

    test('deleting the pinned comment lowers the total', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      await rig.model.delete(rig.model.pinned!);
      expect(rig.model.pinned, isNull);
      expect(rig.model.total, 3);
    });

    test('a refused delete keeps the row and toasts why', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      rig.api.failures['deleteComment'] = const BiliError.api(code: 12022, message: '已经被删除了');
      expect(await rig.model.delete(rig.model.comments.first), isFalse);
      expect(rpids(rig.model.comments), [1, 2]);
      expect(rig.model.total, 4);
      expect(rig.toasts, ['已经被删除了']);
    });

    test('deleting the open thread\'s root closes the thread', () async {
      final rig = CommentsRig(api: threadApi());
      await rig.model.loadMore();
      await rig.model.openThread(rig.model.comments.first);
      await rig.model.delete(rig.model.thread!.root);
      expect(rig.model.thread, isNull);
      expect(rpids(rig.model.comments), [2]);
    });

    test('a reply goes from the thread and the previews, and its root counts one fewer', () async {
      final rig = CommentsRig(api: threadApi());
      await rig.model.loadMore();
      await rig.model.openThread(rig.model.comments.first);
      final reply = rig.model.thread!.replies.first;

      await rig.model.delete(reply);
      expect(rig.model.thread!.replies.map((reply) => reply.rpid), isNot(contains(101)));
      expect(rig.model.thread!.total, 24);
      expect(rig.model.thread!.root.replyCount, 24);
      expect(rig.model.comments.first.replyCount, 24);
      expect(rpids(rig.model.comments.first.previewReplies), [102, 103]);
      expect(rig.model.total, 27, reason: 'as in Swift, only top-level comments move the total');
    });
  });

  group('a posted comment', () {
    test('a top-level one goes to the top of the list, under the pinned one', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      rig.model.inserted(comment(50));
      expect(rpids(rig.model.comments), [50, 1, 2]);
      expect(rig.model.pinned?.rpid, 9);
      expect(rig.model.total, 5);
      rig.model.inserted(comment(50));
      expect(rpids(rig.model.comments), [50, 1, 2], reason: 'shown once');
    });

    test('a reply in an open thread moves the root\'s count by one each way, in the thread and in the list', () async {
      final rig = CommentsRig(api: threadApi());
      await rig.model.loadMore();
      await rig.model.openThread(rig.model.comments.first);
      final threadCount = rig.model.thread!.root.replyCount;
      final listCount = rig.model.comments.first.replyCount;

      final reply = comment(999, root: 1, parent: 1);
      rig.model.inserted(reply);
      expect(rig.model.thread!.root.replyCount, threadCount + 1);
      expect(rig.model.comments.first.replyCount, listCount + 1);
      expect(rig.model.thread!.total, 26);
      expect(rig.model.thread!.replies.first.rpid, 999);
      expect(rig.model.comments.first.previewReplies.first.rpid, 999);

      await rig.model.delete(reply);
      expect(rig.model.thread!.root.replyCount, threadCount);
      expect(rig.model.comments.first.replyCount, listCount);
      expect(rig.model.thread!.total, 25);
    });

    test('a reply to a comment whose thread isn\'t open counts on the list\'s copy', () async {
      final rig = CommentsRig(api: pagedApi());
      await rig.model.loadMore();
      rig.model.inserted(comment(70, root: 2, parent: 2));
      expect(rig.model.comments[1].replyCount, 1);
      expect(rig.model.thread, isNull);
      expect(rig.model.total, 4);
    });
  });

  group('the thread', () {
    test('shows the root at once, then loads and pages by time', () async {
      final rig = CommentsRig(api: threadApi());
      await rig.model.loadMore();
      final root = rig.model.comments.first;
      final hold = rig.api.holds['thread'] = Completer<void>();

      final open = rig.model.openThread(root);
      expect(rig.model.thread?.root.rpid, 1);
      expect(rig.model.thread?.total, 25);
      expect(rig.model.thread?.loading, isTrue);
      expect(rig.model.thread?.replies, isEmpty);
      hold.complete();
      await open;

      final thread = rig.model.thread!;
      expect(thread.replies, hasLength(20));
      expect(thread.replies.first.rpid, 101);
      expect(thread.total, 25);
      expect(thread.sort, CommentSort.time);
      expect(thread.isEnd, isFalse);
      expect(thread.loading, isFalse);
      expect(rig.callsTo('thread'), ['thread root=1 page=1 sort=time']);

      await rig.model.loadMoreThread();
      expect(rpids(rig.model.thread!.replies), [for (var n = 101; n <= 125; n++) n]);
      expect(rig.model.thread!.page, 2);
      expect(rig.model.thread!.isEnd, isTrue);
      await rig.model.loadMoreThread();
      expect(rig.callsTo('thread'), ['thread root=1 page=1 sort=time', 'thread root=1 page=2 sort=time']);

      rig.model.closeThread();
      expect(rig.model.thread, isNull);
    });

    test('a sort switch starts the thread again from its first page', () async {
      final rig = CommentsRig(api: threadApi());
      await rig.model.loadMore();
      await rig.model.openThread(rig.model.comments.first);
      await rig.model.setThreadSort(CommentSort.hot);
      expect(rig.model.thread!.sort, CommentSort.hot);
      expect(rig.model.thread!.replies.first.rpid, 125, reason: 'most liked first');
      expect(rig.model.thread!.replies, hasLength(20));
      expect(rig.callsTo('thread').last, 'thread root=1 page=1 sort=hot');
    });

    test('an answer for a thread closed or replaced meanwhile is dropped', () async {
      final api = ScriptedApi()
        ..gated = true
        ..threadPages = (root, page, sort) => ThreadPage(
          root: comment(root),
          replies: [comment(root * 10, root: root)],
          total: 1,
          isEnd: true,
        );
      final model = CommentsRig(api: api).model;
      final first = model.openThread(comment(1));
      final second = model.openThread(comment(2));
      api.gates[1].complete();
      await second;
      api.gates[0].complete();
      await first;
      expect(model.thread!.root.rpid, 2);
      expect(rpids(model.thread!.replies), [20]);

      final third = model.openThread(comment(3));
      model.closeThread();
      api.gates[2].complete();
      await third;
      expect(model.thread, isNull);
    });

    test('the thread\'s fresher root replaces the list\'s copy, which still knows it is pinned', () async {
      final api = ScriptedApi()
        ..threadPages = (root, page, sort) =>
            ThreadPage(root: comment(root, likes: 77), replies: const [], total: 0, isEnd: true);
      final model = CommentsRig(api: api).model;
      await model.openThread(comment(9, isPinned: true));
      expect(model.thread!.root.likes, 77);
      expect(model.thread!.root.isPinned, isTrue);
      expect(model.thread!.isEnd, isTrue);
    });

    test('a failed page shows its words, and loadMoreThread asks again', () async {
      final rig = CommentsRig(api: threadApi());
      await rig.model.loadMore();
      rig.api.failures['thread'] = const BiliError.api(code: 12022, message: '评论已被删除');
      await rig.model.openThread(rig.model.comments.first);
      expect(rig.model.thread!.error, '评论已被删除');
      expect(rig.model.thread!.loading, isFalse);

      rig.api.failures.clear();
      await rig.model.loadMoreThread();
      expect(rig.model.thread!.error, isNull);
      expect(rig.model.thread!.replies, hasLength(20));
      expect(rig.callsTo('thread'), ['thread root=1 page=1 sort=time', 'thread root=1 page=1 sort=time']);
    });
  });

  test('debugShow shows a state without asking anything', () {
    final rig = CommentsRig();
    var notified = 0;
    rig.model.addListener(() => notified++);
    rig.model.debugShow(
      comments: [comment(1)],
      pinned: comment(9),
      total: 12,
      isEnd: true,
      thread: ThreadState(root: comment(1), total: 3),
    );
    expect(rpids(rig.model.comments), [1]);
    expect(rig.model.pinned?.rpid, 9);
    expect(rig.model.total, 12);
    expect(rig.model.thread?.total, 3);
    expect(notified, 1);
    expect(rig.api.calls, isEmpty);
  });
}
