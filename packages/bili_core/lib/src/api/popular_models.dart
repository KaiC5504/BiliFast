/// 首页's 热门 (204): the website's `/x/web-interface/popular`.
library;

import 'json.dart';
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

abstract final class PopularDecode {
  /// The envelope's `data`; a row that won't decode as a video costs only itself, and an empty page ends the list
  /// whatever `no_more` says.
  static PopularPage page(Object? json, {required int page}) {
    final data = JsonObject.from(json, 'popular page');
    final videos = data.lenientList('list', _video);
    return PopularPage(videos: videos, page: page, hasMore: videos.isNotEmpty && !data.flag('no_more'));
  }
}

PopularVideo _video(Object? json) {
  final card = VideoCard.fromJson(json);
  final row = JsonObject.from(json);
  final pubdate = asInt(row.map['pubdate']) ?? 0;
  return PopularVideo(
    card: card,
    published: pubdate > 0 ? DateTime.fromMillisecondsSinceEpoch(pubdate * 1000) : null,
    reason: row.nested('rcmd_reason')?.text('content') ?? '',
  );
}
