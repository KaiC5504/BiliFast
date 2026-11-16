/// 首页's 热门 (204): the website's `/x/web-interface/popular`.
library;

import 'video_models.dart' show VideoCard;

/// A 热门 row: the video, when it was published, and the list's reason tag where it gives one.
final class PopularVideo {
  const PopularVideo({required this.card, this.published, this.reason = ''});

  final VideoCard card;
  final DateTime? published;

  /// `rcmd_reason.content` (百万播放, 很多人点赞…); empty for none.
  final String reason;
}

/// A page of 热门, page [page] from 1; [hasMore] until the answer says `no_more`.
final class PopularPage {
  const PopularPage({required this.videos, required this.page, this.hasMore = true});

  final List<PopularVideo> videos;
  final int page;
  final bool hasMore;
}
