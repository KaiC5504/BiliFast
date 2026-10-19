import 'dart:math' show max;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../video/page_api.dart';
import 'composer_model.dart' show PickedPicture;

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

/// One reply target's unsent composer content.
@immutable
class CommentDraft {
  const CommentDraft({this.text = '', this.mentions = const {}, this.pictures = const []});

  static const empty = CommentDraft();

  final String text;

  /// Every @name picked so far with its mid, including names since deleted from [text].
  final Map<String, int> mentions;
  final List<PickedPicture> pictures;

  bool get isEmpty => text.isEmpty && mentions.isEmpty && pictures.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is CommentDraft &&
      other.text == text &&
      mapEquals(other.mentions, mentions) &&
      listEquals(other.pictures, pictures);

  @override
  int get hashCode => Object.hash(
    text,
    Object.hashAllUnordered(mentions.entries.map((e) => (e.key, e.value))),
    Object.hashAll(pictures),
  );
}

/// Unsent composer text, kept by the page across composers and across the videos it opens, keyed by
/// `ComposerModel.draftKey`, and the keys being posted to. Notifies when a post starts or ends and when a draft is
/// cleared, not on every keystroke.
class CommentDrafts extends ChangeNotifier {
  final Map<String, CommentDraft> _drafts = {};
  final Set<String> _posting = {};

  CommentDraft operator [](String key) => _drafts[key] ?? CommentDraft.empty;

  void save(String key, CommentDraft draft) {
    if (draft.isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = draft;
    }
  }

  void clear(String key) {
    if (_drafts.remove(key) != null) notifyListeners();
  }

  /// A composer closed while posting must not let a reopened one post the same text again.
  bool isPosting(String key) => _posting.contains(key);

  /// A composer is posting somewhere on the page, so closing it now would hide how the post went.
  bool get anyPosting => _posting.isNotEmpty;

  void setPosting(String key, bool on) {
    final changed = on ? _posting.add(key) : _posting.remove(key);
    if (changed) notifyListeners();
  }
}

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
/// on the first page, a section the uploader closed, reactions rolled back on failure, deletes made once the server
/// agrees, and the open 评论详情. Nothing loads until [ensureLoaded], which the 评论 tab calls when it first shows.
class CommentsModel extends ChangeNotifier {
  CommentsModel({
    required this.aid,
    required this._upMid,
    required this.api,
    required this.drafts,
    required this._isLoggedIn,
    required this._accountMid,
    required this._requestLogin,
    required this._toast,
    Logger? logger,
  }) : _logger = logger ?? Logger.shared;

  /// The server's codes for a comment section that is switched off; its message replaces the list.
  static const closedCodes = {12002, 12061};

  /// Pages in a row that may add nothing before the list counts as ended, so a server that keeps answering empty
  /// pages can't keep the list asking.
  static const _emptyPagesAllowed = 3;

  final int aid;

  /// The uploader's mid, for the UP mark on their comments.
  int _upMid;

  /// Set again once the video's detail arrives, for a page opened from a view without one.
  int get upMid => _upMid;
  set upMid(int value) {
    if (value == _upMid) return;
    _upMid = value;
    notifyListeners();
  }
  final PageApi api;
  final CommentDrafts drafts;

  final bool Function() _isLoggedIn;
  final int? Function() _accountMid;
  final void Function() _requestLogin;
  final void Function(String message) _toast;
  final Logger _logger;

  CommentSort _sort = CommentSort.hot;
  List<Comment> _comments = const [];
  Comment? _pinned;
  int _total = 0;
  bool _isEnd = false;
  String? _closedMessage;
  bool _loading = false;
  String? _error;
  ThreadState? _thread;

  String? _nextOffset;
  int _emptyPages = 0;

  /// A first page came back, even one with nothing on it, so the list is shown rather than spun for.
  bool _answered = false;

  /// Bumped by every reset, so an answer for the old sort or an old thread is dropped.
  int _generation = 0;
  int _threadGeneration = 0;

  /// Comments with a 点赞 or 踩 on its way; another tap on one is ignored until the answer.
  final Set<int> _reacting = {};
  bool _disposed = false;

  CommentSort get sort => _sort;
  List<Comment> get comments => _comments;
  Comment? get pinned => _pinned;
  int get total => _total;
  bool get isEnd => _isEnd;

  /// Set when the uploader closed the section (12002, 12061): the server's words, shown instead of the list.
  String? get closedMessage => _closedMessage;
  bool get loading => _loading;

  /// Why the last page failed. Nothing asks again by itself: the footer's 重试 calls [loadMore].
  String? get error => _error;
  ThreadState? get thread => _thread;

  bool get hasLoaded =>
      _answered || _comments.isNotEmpty || _pinned != null || _isEnd || _closedMessage != null || _error != null;

  int? get accountMid => _accountMid();

  bool isOwn(Comment comment) {
    final mid = accountMid;
    if (mid == null) return false;
    return comment.mid == mid || comment.member.mid == mid;
  }

  /// True when logged in; otherwise asks for the login and answers false.
  bool requireLogin() {
    if (_isLoggedIn()) return true;
    if (!_disposed) _requestLogin();
    return false;
  }

  /// Loads the first page once.
  Future<void> ensureLoaded() async {
    if (hasLoaded || _loading) return;
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_isEnd || _loading || _closedMessage != null || _disposed) return;
    final started = _generation;
    final offset = _nextOffset;
    final first = !_answered;
    var again = false;
    _loading = true;
    _error = null;
    _notify();
    try {
      final page = await api.comments(aid: aid, sort: _sort, offset: offset);
      if (started != _generation || _disposed) return;
      _loading = false;
      _answered = true;
      if (first) {
        _pinned = page.pinned;
        _total = page.total;
      }
      final seen = {for (final comment in _comments) comment.rpid, ?_pinned?.rpid};
      final added = [
        for (final comment in page.comments)
          if (seen.add(comment.rpid)) comment,
      ];
      _comments = [..._comments, ...added];
      _nextOffset = page.nextOffset;
      _emptyPages = added.isEmpty ? _emptyPages + 1 : 0;
      // No next offset would ask for the first page again.
      final stuck = page.nextOffset == null || page.nextOffset == offset || _emptyPages >= _emptyPagesAllowed;
      if (!page.isEnd && stuck) {
        _logger.warn(LogCategory.api, 'comments stopped paging', {'emptyPages': _emptyPages});
      }
      _isEnd = page.isEnd || stuck;
      // The list scrolls on only when its content grows, so a page that adds nothing asks for the next itself.
      again = !_isEnd && added.isEmpty;
    } catch (error, stack) {
      if (started != _generation || _disposed) return;
      _loading = false;
      if (error is BiliAPIError && closedCodes.contains(error.code)) {
        _closedMessage = error.message.isEmpty ? '评论区已关闭' : error.message;
      } else {
        _logger.warn(LogCategory.api, 'comments failed', {
          'error': '$error',
          if (error is! BiliError) 'stack': '$stack',
        });
        _error = messageFor(error);
      }
    }
    _notify();
    if (again) await loadMore();
  }

  Future<void> setSort(CommentSort sort) async {
    _sort = sort;
    _resetList();
    await loadMore();
  }

  /// Starts the list again from its first page.
  Future<void> reload() async {
    _resetList();
    await loadMore();
  }

  void _resetList() {
    _generation += 1;
    _comments = const [];
    _pinned = null;
    _total = 0;
    _nextOffset = null;
    _emptyPages = 0;
    _answered = false;
    _isEnd = false;
    _closedMessage = null;
    _loading = false;
    _error = null;
    _notify();
  }

  /// A comment just posted: at the top of the list, or into the open thread and its root's count.
  void inserted(Comment comment) {
    if (comment.root == 0) {
      if (_comments.any((shown) => shown.rpid == comment.rpid)) return;
      _comments = [comment, ..._comments];
      _total += 1;
      _notify();
      return;
    }
    // all_count counts replies too.
    _total += 1;
    if (_thread case final thread? when thread.root.rpid == comment.root) {
      if (!thread.replies.any((reply) => reply.rpid == comment.rpid)) {
        _thread = thread.copyWith(replies: [comment, ...thread.replies], total: thread.total + 1);
      }
    }
    // The list's copy of the root, and the thread's own.
    _update(
      comment.root,
      (root) => root.copyWith(
        replyCount: root.replyCount + 1,
        previewReplies: [comment, ...root.previewReplies.where((reply) => reply.rpid != comment.rpid)],
      ),
    );
    _notify();
  }

  Future<void> toggleLike(Comment comment) async {
    final before = _current(comment.rpid);
    if (before == null || !requireLogin() || !_reacting.add(comment.rpid)) return;
    final on = before.action != 1;
    _update(
      comment.rpid,
      (target) => on
          ? target.copyWith(likes: target.likes + (target.action == 1 ? 0 : 1), action: 1)
          : target.copyWith(likes: max(0, target.likes - 1), action: 0),
    );
    await _send(before, () => api.likeComment(aid: aid, rpid: comment.rpid, on: on));
  }

  Future<void> toggleHate(Comment comment) async {
    final before = _current(comment.rpid);
    if (before == null || !requireLogin() || !_reacting.add(comment.rpid)) return;
    final on = before.action != 2;
    _update(
      comment.rpid,
      (target) => target.copyWith(
        likes: on && target.action == 1 ? max(0, target.likes - 1) : target.likes,
        action: on ? 2 : 0,
      ),
    );
    await _send(before, () => api.hateComment(aid: aid, rpid: comment.rpid, on: on));
  }

  /// Shown already; taken back with the server's words if it fails.
  Future<void> _send(Comment before, Future<void> Function() call) async {
    _notify();
    try {
      await call();
    } catch (error, stack) {
      _update(before.rpid, (target) => target.copyWith(likes: before.likes, action: before.action));
      fail(error, stack);
    } finally {
      _reacting.remove(before.rpid);
      _notify();
    }
  }

  /// After the page's confirm: the row goes only once the server agrees. True once it is deleted.
  Future<bool> delete(Comment comment) async {
    if (!requireLogin()) return false;
    try {
      await api.deleteComment(aid: aid, rpid: comment.rpid);
    } catch (error, stack) {
      fail(error, stack);
      return false;
    }
    final rpid = comment.rpid;
    if (_thread?.root.rpid == rpid) closeThread();
    final before = _comments.length + (_pinned == null ? 0 : 1);
    if (_pinned?.rpid == rpid) _pinned = null;
    _comments = [
      for (final shown in _comments)
        if (shown.rpid != rpid) shown,
    ];
    // all_count counts replies too: a comment goes with its replies, a reply alone.
    if (comment.root != 0) {
      _total = max(0, _total - 1);
    } else if (_comments.length + (_pinned == null ? 0 : 1) < before) {
      _total = max(0, _total - 1 - comment.replyCount);
    }
    if (_thread case final thread? when thread.replies.any((reply) => reply.rpid == rpid)) {
      _thread = thread.copyWith(
        replies: [
          for (final reply in thread.replies)
            if (reply.rpid != rpid) reply,
        ],
        total: max(0, thread.total - 1),
      );
    }
    if (comment.root != 0) {
      _update(
        comment.root,
        (root) => root.copyWith(
          replyCount: max(0, root.replyCount - 1),
          previewReplies: [
            for (final reply in root.previewReplies)
              if (reply.rpid != rpid) reply,
          ],
        ),
      );
    }
    _notify();
    return true;
  }

  /// Toasts what went wrong in words for the viewer; an expired login gets the login prompt alone. Also the
  /// composer's. Anything but a [BiliError] is logged with its stack, so a bug in the app isn't read as the network.
  void fail(Object error, [StackTrace? stack]) {
    _logger.warn(LogCategory.api, 'comment action failed', {
      'error': '$error',
      if (error is! BiliError) 'stack': '${stack ?? StackTrace.current}',
    });
    if (_disposed) return;
    if (error is BiliError && error.needsLogin) {
      _requestLogin();
    } else {
      _toast(messageFor(error));
    }
  }

  /// A toast of the app's own, such as the composer's picture limit.
  void say(String message) {
    if (!_disposed) _toast(message);
  }

  /// Bilibili words its refusals for the user (too frequent, already deleted); those are shown as sent.
  static String messageFor(Object error) {
    if (error is! BiliError) return '网络连接失败，请稍后再试';
    if (error case BiliAPIError(:final code, :final message) when message.isNotEmpty && code > 0) return message;
    return error.userMessage;
  }

  /// The comment as shown now, wherever it is: the same rpid can be in the list, a preview and the thread.
  Comment? _current(int rpid) {
    if (_thread case final thread?) {
      if (thread.root.rpid == rpid) return thread.root;
      for (final reply in thread.replies) {
        if (reply.rpid == rpid) return reply;
      }
    }
    for (final comment in [?_pinned, ..._comments]) {
      if (comment.rpid == rpid) return comment;
      for (final reply in comment.previewReplies) {
        if (reply.rpid == rpid) return reply;
      }
    }
    return null;
  }

  /// Changes every copy of [rpid]: in the list, the pinned comment, the previews and the thread.
  void _update(int rpid, Comment Function(Comment comment) change) {
    Comment apply(Comment comment) {
      var changed = comment.rpid == rpid ? change(comment) : comment;
      if (changed.previewReplies.any((reply) => reply.rpid == rpid)) {
        changed = changed.copyWith(
          previewReplies: [for (final reply in changed.previewReplies) reply.rpid == rpid ? change(reply) : reply],
        );
      }
      return changed;
    }

    _comments = [for (final comment in _comments) apply(comment)];
    if (_pinned case final pinned?) _pinned = apply(pinned);
    if (_thread case final thread?) {
      _thread = thread.copyWith(root: apply(thread.root), replies: [for (final reply in thread.replies) apply(reply)]);
    }
  }

  /// Shows [root] at once and asks for its first page of replies, by time.
  Future<void> openThread(Comment root) async {
    _threadGeneration += 1;
    _thread = ThreadState(root: root, total: root.replyCount);
    await _loadThread();
  }

  void closeThread() {
    _threadGeneration += 1;
    if (_thread == null) return;
    _thread = null;
    _notify();
  }

  Future<void> setThreadSort(CommentSort sort) async {
    final thread = _thread;
    if (thread == null) return;
    _threadGeneration += 1;
    _thread = ThreadState(root: thread.root, sort: sort, total: thread.total);
    await _loadThread();
  }

  Future<void> loadMoreThread() async {
    if (_thread case final thread? when !thread.loading) await _loadThread();
  }

  Future<void> _loadThread() async {
    final state = _thread;
    if (state == null || state.isEnd || _disposed) return;
    final started = _threadGeneration;
    _thread = state.copyWith(loading: true, error: () => null);
    _notify();
    try {
      final page = await api.thread(aid: aid, root: state.root.rpid, page: state.page + 1, sort: state.sort);
      final thread = _thread;
      if (started != _threadGeneration || thread == null || _disposed) return;
      final seen = {for (final reply in thread.replies) reply.rpid};
      final added = [
        for (final reply in page.replies)
          if (seen.add(reply.rpid)) reply,
      ];
      var root = thread.root;
      if (state.page == 0) {
        // The thread's own copy is fresher, but the list's knows it is pinned, and a 点赞 still out is the viewer's.
        final shown = root;
        root = page.root.copyWith(isPinned: shown.isPinned);
        if (_reacting.contains(root.rpid)) root = root.copyWith(likes: shown.likes, action: shown.action);
      }
      _thread = thread.copyWith(
        root: root,
        replies: [...thread.replies, ...added],
        page: state.page + 1,
        total: page.total,
        // A page that adds nothing would only be asked for again.
        isEnd: page.isEnd || added.isEmpty,
        loading: false,
      );
    } catch (error, stack) {
      final thread = _thread;
      if (started != _threadGeneration || thread == null || _disposed) return;
      _logger.warn(LogCategory.api, 'comment thread failed', {
        'error': '$error',
        if (error is! BiliError) 'stack': '$stack',
      });
      _thread = thread.copyWith(loading: false, error: () => messageFor(error));
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

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
