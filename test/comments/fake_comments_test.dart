import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bilifast/comments/comments_model.dart';
import 'package:bilifast/comments/composer_model.dart';
import 'package:bilifast/comments/emote_store.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'comment_fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 10, 19, 12);
  FakePageApi demo() => FakePageApi.demo(now: now)..delay = Duration.zero;

  Iterable<Comment> everyComment(FakePageApi api) sync* {
    for (final comment in [?api.pinnedComment, ...api.commentList]) {
      yield comment;
      yield* comment.previewReplies;
    }
    for (final replies in api.threadReplies.values) {
      yield* replies;
    }
  }

  group('the demo', () {
    test('has a pinned comment and 25 more over two pages in either sort', () async {
      final api = demo();
      for (final sort in CommentSort.values) {
        final first = await api.comments(aid: testAid, sort: sort);
        expect(first.comments, hasLength(20));
        expect(first.pinned?.isPinned, isTrue);
        expect(first.isEnd, isFalse);
        final second = await api.comments(aid: testAid, sort: sort, offset: first.nextOffset);
        expect(second.comments, hasLength(5));
        expect(second.pinned, isNull);
        expect(second.isEnd, isTrue);
        expect(second.nextOffset, isNull);
        expect({...rpids(first.comments), ...rpids(second.comments)}, hasLength(25));
      }
      final byTime = (await api.comments(aid: testAid, sort: CommentSort.time)).comments;
      expect([
        for (final comment in byTime) comment.ctime,
      ], [...byTime.map((comment) => comment.ctime)]..sort((a, b) => b - a));
    });

    test('shows what the list has to draw', () {
      final api = demo();
      final members = [for (final comment in everyComment(api)) comment.member];
      expect({for (final member in members) member.level}, containsAll([2, 3, 4, 5, 6]));
      expect(members.any((member) => member.isVip), isTrue);
      expect(members.any((member) => !member.isVip), isTrue);
      expect(members.any((member) => member.fanCardNumber != null), isTrue);

      final runs = [for (final comment in everyComment(api)) ...comment.runs];
      expect(runs.whereType<TimestampRun>(), isNotEmpty);
      expect(runs.whereType<VideoRun>().map((run) => run.id), contains('BV1GJ411x7h7'));
      expect(runs.whereType<MentionRun>(), isNotEmpty);
      expect(runs.whereType<EmoteRun>().where((run) => run.size == 2), isNotEmpty, reason: 'a large 小电视 emote');

      expect(api.commentList.where((comment) => comment.pictures.length > 1), isNotEmpty);
      expect(api.commentList.where((comment) => comment.pictures.length == 1), isNotEmpty);
      expect(api.commentList.where((comment) => comment.message.length > 100), isNotEmpty);
      expect(api.commentList.where((comment) => comment.message.length <= 2), isNotEmpty);
      expect(api.commentList.where((comment) => comment.upLiked), isNotEmpty);
      expect(
        api.commentList.where((comment) => comment.mid == FakePageApi.accountMember.mid),
        isNotEmpty,
        reason: '测试账号 has a comment to delete',
      );
      for (final comment in [?api.pinnedComment, ...api.commentList]) {
        if (comment.replyCount > 0) {
          expect(comment.previewReplies, isNotEmpty);
          expect(api.threadReplies[comment.rpid], hasLength(comment.replyCount));
        }
      }
    });

    test('fetches nothing: every picture and emote is on example.invalid', () {
      final api = demo();
      final urls = [
        for (final comment in everyComment(api)) ...[
          for (final picture in comment.pictures) picture.url,
          for (final run in comment.runs.whereType<EmoteRun>()) run.url,
          ?comment.member.pendant,
          ?comment.member.fanCardImage,
          if (comment.member.face.isNotEmpty) comment.member.face,
        ],
        for (final package in api.emotes) ...[package.icon, for (final emote in package.emotes) emote.url],
      ];
      expect(urls, isNotEmpty);
      for (final url in urls.where((url) => url.isNotEmpty)) {
        expect(Uri.parse(url).host, 'example.invalid', reason: url);
      }
    });

    test('has a thread that pages in both sorts, with a reply to a reply', () async {
      final api = demo();
      final root = api.commentList.first;
      expect(root.replyCount, greaterThan(20));
      for (final sort in CommentSort.values) {
        final first = await api.thread(aid: testAid, root: root.rpid, page: 1, sort: sort);
        expect(first.replies, hasLength(20));
        expect(first.isEnd, isFalse);
        final second = await api.thread(aid: testAid, root: root.rpid, page: 2, sort: sort);
        expect(second.replies, hasLength(root.replyCount - 20));
        expect(second.isEnd, isTrue);
      }
      final replies = api.threadReplies[root.rpid]!;
      expect(replies.where((reply) => reply.parent != root.rpid && reply.message.startsWith('回复 @')), isNotEmpty);
    });

    test('has emote packages with a 颜文字 one, and people to @', () async {
      final api = demo();
      final packages = await api.emotePackages();
      expect(packages, hasLength(3));
      expect(packages.where((package) => package.isText).single.emotes.every((emote) => emote.url.isEmpty), isTrue);
      expect(packages.every((package) => package.emotes.isNotEmpty), isTrue);
      expect(await api.mentionCandidates(mid: 1), isNotEmpty);
      expect(await api.mentionCandidates(mid: 1, query: '小'), hasLength(2));
    });

    test('the model reads both pages without a repeat, and a thread to its end', () async {
      final rig = CommentsRig(api: demo());
      await rig.model.ensureLoaded();
      await rig.model.loadMore();
      expect(rig.model.comments, hasLength(25));
      expect(rig.model.isEnd, isTrue);
      expect(rig.model.pinned, isNotNull);
      await rig.model.openThread(rig.model.comments.first);
      await rig.model.loadMoreThread();
      expect(rig.model.thread!.replies, hasLength(rig.model.comments.first.replyCount));
      expect(rig.model.thread!.isEnd, isTrue);
    });
  });

  group('the fake keeps what was done', () {
    test('likes, 踩 and deletes change its comments and are in its calls', () async {
      final api = demo();
      final first = api.commentList.first;
      final reply = first.previewReplies.first;
      await api.likeComment(aid: testAid, rpid: reply.rpid, on: true);
      expect(api.commentList.first.previewReplies.first.likes, reply.likes + 1);
      expect(api.threadReplies[first.rpid]!.firstWhere((each) => each.rpid == reply.rpid).action, 1);
      await api.hateComment(aid: testAid, rpid: reply.rpid, on: true);
      expect(api.commentList.first.previewReplies.first.likes, reply.likes);
      expect(api.commentList.first.previewReplies.first.action, 2);

      await api.deleteComment(aid: testAid, rpid: reply.rpid);
      expect(rpids(api.commentList.first.previewReplies), isNot(contains(reply.rpid)));
      expect(rpids(api.threadReplies[first.rpid]!), isNot(contains(reply.rpid)));
      expect(api.commentList.first.replyCount, first.replyCount - 1);

      await api.deleteComment(aid: testAid, rpid: first.rpid);
      expect(rpids(api.commentList), isNot(contains(first.rpid)));
      expect(api.threadReplies.containsKey(first.rpid), isFalse);
      expect(api.calls, [
        'likeComment rpid=${reply.rpid} on=true',
        'hateComment rpid=${reply.rpid} on=true',
        'deleteComment rpid=${reply.rpid}',
        'deleteComment rpid=${first.rpid}',
      ]);
    });

    test('a post comes back with its root and parent, as 测试账号, in the list or its thread', () async {
      final api = demo();
      final root = api.commentList[2];
      final reply = api.threadReplies[root.rpid]!.first;
      final posted = await api.postComment(
        aid: testAid,
        message: '回复 @${reply.member.name} :好',
        root: root.rpid,
        parent: reply.rpid,
      );
      expect((posted.root, posted.parent), (root.rpid, reply.rpid));
      expect(posted.member, FakePageApi.accountMember);
      expect(api.threadReplies[root.rpid]!.last, posted);
      expect(api.commentList[2].replyCount, root.replyCount + 1);

      final top = await api.postComment(
        aid: testAid,
        message: '新评论[doge]',
        pictures: [const UploadedPicture(url: 'https://example.invalid/a.jpg', width: 3, height: 4, sizeKb: 1)],
      );
      expect(api.commentList.first, top);
      expect(top.pictures.single.width, 3);
      expect(top.runs.whereType<EmoteRun>().single.token, '[doge]');
      expect(top.rpid, isNot(posted.rpid));
      expect(rpids(everyComment(api)).where((rpid) => rpid == top.rpid), hasLength(1));
    });

    test('a first page set by a test is answered as given, with what has happened since', () async {
      final api = FakePageApi()
        ..commentPage = CommentPage(
          comments: [comment(1), comment(2)],
          pinned: comment(9),
          nextOffset: 'x',
          isEnd: false,
          total: 30,
        );
      await api.likeComment(aid: testAid, rpid: 2, on: true);
      final first = await api.comments(aid: testAid, sort: CommentSort.hot);
      expect(rpids(first.comments), [1, 2]);
      expect(first.comments[1].likes, 11);
      expect((first.pinned?.rpid, first.nextOffset, first.isEnd, first.total), (9, 'x', false, 30));
      expect((await api.comments(aid: testAid, sort: CommentSort.hot, offset: 'x')).comments, isEmpty);
      expect(api.commentPage.comments, hasLength(2));
      final thread = await api.thread(aid: testAid, root: 9, page: 1, sort: CommentSort.time);
      expect(thread.root.rpid, 9);
    });

    test('the --fake-account run can post with a picture and an @ through the composer', () async {
      final rig = CommentsRig(api: demo());
      await rig.model.ensureLoaded();
      final model =
          ComposerModel(
              comments: rig.model,
              target: const ReplyToVideo(),
              recent: RecentEmotes.memory(),
              catalog: EmoteCatalog(),
            )
            ..mentioned(const MentionCandidate(mid: 3003, name: '小明'))
            ..addPictures([PickedPicture(bytes: Uint8List(4), name: 'shot.png')])
            ..text = '@小明 看这个';
      expect(await model.post(), isTrue);
      final posted = rig.model.comments.first;
      expect(rig.model.isOwn(posted), isTrue);
      expect(posted.pictures, hasLength(1));
      expect(posted.runs.first, const RichRun.mention(name: '小明', mid: 3003));
    });
  });
}
