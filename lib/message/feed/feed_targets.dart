import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../dynamic/post/post_route.dart';
import '../../space/space_route.dart' as space;
import '../../space/uploader_tap.dart';
import '../../video/video_route.dart';

/// What a tapped row opens.
sealed class FeedTarget {
  const FeedTarget();
}

/// A video's page, on the thread when [comment] is set.
final class FeedVideo extends FeedTarget {
  const FeedVideo({required this.bvid, this.comment});

  final String bvid;
  final CommentFocus? comment;
}

/// A 动态 post, scrolled to its comments when [toComments].
final class FeedPost extends FeedTarget {
  const FeedPost({required this.id, required this.toComments});

  final String id;
  final bool toComments;
}

/// Nothing the app shows yet (an article, a 番剧, an unknown link): 暂未开放.
final class FeedNowhere extends FeedTarget {
  const FeedNowhere();
}

final _bvidPattern = RegExp(r'BV1[0-9A-Za-z]{9}');
final _aidPattern = RegExp(r'/video/av(\d+)');
final _postPattern = RegExp(r'(?:t\.bilibili\.com/|/opus/|opus/detail/|following/detail/)(\d+)');
final _rootPattern = RegExp(r'comment_root_id=(\d+)');
final _secondaryPattern = RegExp(r'comment_secondary_id=(\d+)');

/// Comment area types (`business_id`) that are a 动态: 11 a picture post, 17 a text one.
const _postAreas = {11, 17};

int? _first(RegExp pattern, Iterable<String> links) {
  for (final link in links) {
    if (pattern.firstMatch(link)?.group(1) case final digits?) return int.tryParse(digits);
  }
  return null;
}

String? _bvid(Iterable<String> links) {
  for (final link in links) {
    if (_bvidPattern.firstMatch(link)?.group(0) case final bvid?) return bvid;
  }
  return null;
}

/// A reply or @ on a video opens its page on the reply's thread; on a 动态 the post, on its comments unless an @ was
/// in the post itself. The same as NotifyHost.swift's NotifyRoutes.comment for a notification.
FeedTarget replyTarget(ReplyNotice notice) {
  final links = [notice.uri, notice.nativeUri];
  final thread = notice.rootId > 0 ? notice.rootId : notice.sourceId;
  final focus = thread > 0 ? CommentFocus(root: thread, reply: notice.sourceId > 0 ? notice.sourceId : null) : null;
  switch (notice.businessId) {
    case 1:
      final aid = _first(_aidPattern, links) ?? (notice.subjectId > 0 ? notice.subjectId : null);
      final bvid = _bvid(links) ?? (aid == null ? null : avToBv(aid));
      return bvid == null ? const FeedNowhere() : FeedVideo(bvid: bvid, comment: focus);
    case final area when _postAreas.contains(area):
      // 17's subject_id is the post's own id; 11's is its picture album's, so only the link names the post.
      final linked = _first(_postPattern, links);
      final id = linked ?? (area == 17 && notice.subjectId > 0 ? notice.subjectId : null);
      if (id == null) return const FeedNowhere();
      final onComment =
          notice.feed == NoticeFeed.reply ||
          notice.business == 'reply' ||
          notice.rootId > 0 ||
          links.any((link) => link.contains('#reply') || link.contains('comment_root_id'));
      return FeedPost(id: '$id', toComments: onComment);
    default:
      return const FeedNowhere();
  }
}

/// A like opens what was liked where its link names a video or a post: a liked comment on its thread when the link
/// says which.
FeedTarget likeTarget(LikeNotice notice) {
  final links = [notice.nativeUri, notice.uri];
  final comment = notice.business == '评论';
  final bvid =
      _bvid(links) ??
      switch (_first(_aidPattern, links)) {
        final aid? => avToBv(aid),
        null => null,
      };
  if (bvid != null) {
    final root = comment ? _first(_rootPattern, links) : null;
    final reply = comment ? _first(_secondaryPattern, links) : null;
    return FeedVideo(
      bvid: bvid,
      comment: root == null ? null : CommentFocus(root: root, reply: reply),
    );
  }
  if (_first(_postPattern, links) case final id?) return FeedPost(id: '$id', toComments: comment);
  return const FeedNowhere();
}

/// The pages a row opens; tests stand in for them (a video page needs a player).
class FeedOpeners {
  const FeedOpeners();

  Future<void> openVideo(BuildContext context, VideoRoute route) => openVideoPage(context, route);

  Future<void> openPost(BuildContext context, {required String id, required bool toComments}) =>
      openDynamicPost(context, id: id, toComments: toComments);

  Future<void> openSpace(BuildContext context, UploaderRef uploader) => space.openSpace(context, uploader);
}
