import 'package:bili_core/api.dart' show VideoDetail, VideoView;
import 'package:flutter/widgets.dart';

import '../app/swipe_back_route.dart';
import 'video_page.dart';

/// What opens a video page (port of VideoRoute.swift). Without a [cid] the page plays the part Bilibili saw this
/// account watch last, or the first. Without a [start] it resumes per ResumePoint: only on the part it was saved on,
/// and not within 5 s of the end. [title] (from the card, link or 最近打开) shows until the video's own arrives;
/// [cover] (feed cards only) flies in from the card and covers the player until the video first plays. [view] is the
/// video a pasted link already resolved, so the page doesn't ask Bilibili for it again, and [detail] the signed view
/// that resolved it, when that one answered (its 合集 and counts).
@immutable
final class VideoRoute {
  const VideoRoute({required this.bvid, this.cid, this.start, this.title, this.cover, this.view, this.detail});

  final String bvid;
  final int? cid;
  final double? start;
  final String? title;
  final String? cover;
  final VideoView? view;
  final VideoDetail? detail;

  /// The feed card's cover and the page's player box share it, so the cover flies into the player.
  static String coverTag(String bvid) => 'cover-$bvid';

  String get heroTag => coverTag(bvid);
}

/// Every way of opening a video page (feed cards, pasted links, 最近打开) comes through here.
Future<void> openVideoPage(BuildContext context, VideoRoute route) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => VideoPage(route: route)));
