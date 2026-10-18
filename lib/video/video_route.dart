import 'package:flutter/widgets.dart';

import '../app/swipe_back_route.dart';
import 'video_page.dart';

/// What opens a video page (port of VideoRoute.swift). Without a [cid] the page plays the part Bilibili saw this
/// account watch last, or the first; without a [start] it resumes where Bilibili saw it last. [title] and [cover]
/// come from the card that opened it, shown until the video's own details arrive.
@immutable
final class VideoRoute {
  const VideoRoute({required this.bvid, this.cid, this.start, this.title, this.cover});

  final String bvid;
  final int? cid;
  final double? start;
  final String? title;
  final String? cover;

  /// Shared by the feed card's cover and the page's player box, which it flies into.
  String get heroTag => 'cover-$bvid';
}

/// Every way of opening a video page (feed cards, pasted links, 最近打开) comes through here.
Future<void> openVideoPage(BuildContext context, VideoRoute route) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => VideoPage(route: route)));
