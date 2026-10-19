import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/comments/comments_model.dart';
import 'package:bilifast/video/fake_page_api.dart';

const testAid = 900000001;

Comment comment(
  int rpid, {
  int likes = 10,
  int action = 0,
  int root = 0,
  int parent = 0,
  int replyCount = 0,
  int ctime = 0,
  int mid = 2001,
  String? name,
  bool isPinned = false,
  List<Comment> preview = const [],
}) => Comment(
  rpid: rpid,
  oid: testAid,
  mid: mid,
  root: root,
  parent: parent,
  ctime: ctime,
  likes: likes,
  action: action,
  replyCount: replyCount,
  member: CommentMember(mid: mid, name: name ?? '测试用户$rpid', level: 5),
  message: '第$rpid条评论',
  isPinned: isPinned,
  previewReplies: preview,
);

List<int> rpids(Iterable<Comment> comments) => [for (final comment in comments) comment.rpid];

/// A [FakePageApi] whose comment and thread pages come from the test, each call able to wait at its own gate.
class ScriptedApi extends FakePageApi {
  CommentPage Function(CommentSort sort, String? offset) pages = (_, _) => const CommentPage(comments: []);
  ThreadPage Function(int root, int page, CommentSort sort)? threadPages;

  /// While true, each comments or thread call waits on a gate of its own, opened by the test in any order.
  bool gated = false;
  final gates = <Completer<void>>[];

  Future<void> _gate() async {
    if (!gated) return;
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
  }

  @override
  Future<CommentPage> comments({required int aid, required CommentSort sort, String? offset}) async {
    calls.add('comments sort=${sort.name} offset=${offset ?? ''}');
    await _gate();
    if (failures['comments'] case final failure?) throw failure;
    return pages(sort, offset);
  }

  @override
  Future<ThreadPage> thread({required int aid, required int root, required int page, required CommentSort sort}) async {
    final answer = threadPages;
    if (answer == null) return super.thread(aid: aid, root: root, page: page, sort: sort);
    calls.add('thread root=$root page=$page sort=${sort.name}');
    await _gate();
    if (failures['thread'] case final failure?) throw failure;
    return answer(root, page, sort);
  }
}

/// One video's [CommentsModel] over [api], with what it toasted and how often it asked for the login.
class CommentsRig {
  CommentsRig({FakePageApi? api, this.loggedIn = true, this.mid = 1, CommentDrafts? drafts, int aid = testAid})
    : api = api ?? FakePageApi(),
      drafts = drafts ?? CommentDrafts() {
    model = CommentsModel(
      aid: aid,
      upMid: 42,
      api: this.api,
      drafts: this.drafts,
      isLoggedIn: () => loggedIn,
      accountMid: () => mid,
      requestLogin: () => logins++,
      toast: toasts.add,
      logger: Logger(session: 'test'),
    );
  }

  final FakePageApi api;
  final CommentDrafts drafts;
  bool loggedIn;
  int? mid;
  late final CommentsModel model;
  final toasts = <String>[];
  var logins = 0;

  List<String> callsTo(String method) => [
    for (final call in api.calls)
      if (call == method || call.startsWith('$method ')) call,
  ];
}
