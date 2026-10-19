import 'package:bili_core/api.dart';
import 'package:flutter/foundation.dart';

import '../video/page_api.dart';

/// What a composer replies to: the video itself, a comment (from the list, or a thread's root), or a reply inside a
/// thread, which is posted under the thread's root with "回复 @name :" in front.
sealed class ReplyTarget {
  const ReplyTarget();
}

final class ReplyToVideo extends ReplyTarget {
  const ReplyToVideo();

  @override
  bool operator ==(Object other) => other is ReplyToVideo;

  @override
  int get hashCode => (ReplyToVideo).hashCode;
}

final class ReplyToComment extends ReplyTarget {
  const ReplyToComment(this.comment);

  final Comment comment;

  @override
  bool operator ==(Object other) => other is ReplyToComment && other.comment.rpid == comment.rpid;

  @override
  int get hashCode => comment.rpid.hashCode;
}

final class ReplyInThread extends ReplyTarget {
  const ReplyInThread({required this.root, required this.reply});

  final Comment root;
  final Comment reply;

  @override
  bool operator ==(Object other) =>
      other is ReplyInThread && other.root.rpid == root.rpid && other.reply.rpid == reply.rpid;

  @override
  int get hashCode => Object.hash(root.rpid, reply.rpid);
}

/// Unsent composer text, kept by the page across composers and across the videos it opens.
class CommentDrafts {}

/// 评论详情: the root comment, its replies so far and how they are sorted.
@immutable
class ThreadState {
  const ThreadState({
    required this.root,
    this.replies = const [],
    this.sort = CommentSort.time,
    this.page = 0,
    this.isEnd = false,
    required this.total,
    this.loading = false,
    this.error,
  });

  final Comment root;
  final List<Comment> replies;
  final CommentSort sort;

  /// The last page loaded; 0 before the first.
  final int page;
  final bool isEnd;
  final int total;
  final bool loading;
  final String? error;

  ThreadState copyWith({
    Comment? root,
    List<Comment>? replies,
    CommentSort? sort,
    int? page,
    bool? isEnd,
    int? total,
    bool? loading,
    String? Function()? error,
  }) => ThreadState(
    root: root ?? this.root,
    replies: replies ?? this.replies,
    sort: sort ?? this.sort,
    page: page ?? this.page,
    isEnd: isEnd ?? this.isEnd,
    total: total ?? this.total,
    loading: loading ?? this.loading,
    error: error == null ? this.error : error(),
  );

  @override
  bool operator ==(Object other) =>
      other is ThreadState &&
      other.root == root &&
      listEquals(other.replies, replies) &&
      other.sort == sort &&
      other.page == page &&
      other.isEnd == isEnd &&
      other.total == total &&
      other.loading == loading &&
      other.error == error;

  @override
  int get hashCode => Object.hash(root, Object.hashAll(replies), sort, page, isEnd, total, loading, error);
}

/// One video's comments (BiliNative `CommentsModel`): 评论's list in either sort, paged by offset, the pinned comment
/// on the first page, a section the uploader closed, reactions and deletes rolled back on failure, and the open
/// 评论详情. Nothing loads until [ensureLoaded], which the 评论 tab calls when it first shows.
class CommentsModel extends ChangeNotifier {
  CommentsModel({
    required this.aid,
    required this.upMid,
    required this.api,
    required this.drafts,
    required this._isLoggedIn,
    required this._accountMid,
    required this._requestLogin,
    required this._toast,
  });

  final int aid;

  /// The uploader's mid, for the UP mark on their comments.
  final int upMid;
  final PageApi api;
  final CommentDrafts drafts;

  // ignore: unused_field
  final bool Function() _isLoggedIn;
  final int? Function() _accountMid;
  // ignore: unused_field
  final void Function() _requestLogin;
  // ignore: unused_field
  final void Function(String message) _toast;

  CommentSort _sort = CommentSort.hot;
  List<Comment> _comments = const [];
  Comment? _pinned;
  int _total = 0;
  bool _isEnd = false;
  String? _closedMessage;
  bool _loading = false;
  String? _error;
  ThreadState? _thread;

  CommentSort get sort => _sort;
  List<Comment> get comments => _comments;
  Comment? get pinned => _pinned;
  int get total => _total;
  bool get isEnd => _isEnd;

  /// Set when the uploader closed the section (12002, 12061): the server's words, shown instead of the list.
  String? get closedMessage => _closedMessage;
  bool get loading => _loading;
  String? get error => _error;
  ThreadState? get thread => _thread;

  bool get hasLoaded => _comments.isNotEmpty || _pinned != null || _isEnd || _closedMessage != null || _error != null;

  int? get accountMid => _accountMid();

  bool isOwn(Comment comment) => false;

  /// True when logged in; otherwise asks for the login and answers false.
  bool requireLogin() => false;

  /// Loads the first page once.
  Future<void> ensureLoaded() async {}

  Future<void> loadMore() async {}

  Future<void> setSort(CommentSort sort) async {}

  Future<void> reload() async {}

  /// A comment just posted: at the top of the list, or into the open thread and its root's count.
  void inserted(Comment comment) {}

  Future<void> toggleLike(Comment comment) async {}

  Future<void> toggleHate(Comment comment) async {}

  /// After the page's confirm. True once the server deleted it.
  Future<bool> delete(Comment comment) async => false;

  /// Toasts what went wrong in words for the viewer.
  void fail(Object error) {}

  Future<void> openThread(Comment root) async {}

  void closeThread() {}

  Future<void> setThreadSort(CommentSort sort) async {}

  Future<void> loadMoreThread() async {}

  /// For widget tests: shows this state as if it had loaded.
  @visibleForTesting
  void debugShow({
    List<Comment>? comments,
    Comment? pinned,
    int? total,
    bool? isEnd,
    CommentSort? sort,
    String? closedMessage,
    bool? loading,
    String? error,
    ThreadState? thread,
  }) {
    if (comments != null) _comments = comments;
    if (pinned != null) _pinned = pinned;
    if (total != null) _total = total;
    if (isEnd != null) _isEnd = isEnd;
    if (sort != null) _sort = sort;
    if (closedMessage != null) _closedMessage = closedMessage;
    if (loading != null) _loading = loading;
    if (error != null) _error = error;
    if (thread != null) _thread = thread;
    notifyListeners();
  }
}
