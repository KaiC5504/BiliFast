import 'package:bili_core/api.dart' show VideoDetail, VideoView;
import 'package:flutter/widgets.dart';

import '../app/form_factor.dart';
import '../app/swipe_back_route.dart';
import '../app/zoom_back_route.dart';
import 'page_playback.dart';
import 'video_page.dart';

/// What opens a video page (port of VideoRoute.swift). Without a [cid] the page plays the part Bilibili saw this
/// account watch last, or the first. Without a [start] it resumes per ResumePoint: only on the part it was saved on,
/// and not within 5 s of the end. [title] (from the card, link, 最近打开 or 历史记录) shows until the video's own
/// arrives; [cover] (from cards and 最近打开 rows) flies in from the card and covers the player until the video first
/// plays. [view] is the video a pasted link already resolved, so the page doesn't ask Bilibili for it again, and
/// [detail] the signed view that resolved it, when that one answered (its 合集 and counts). [zoomSource] (推荐 cards
/// only) is the card the swipe back, 〈 and system back fly the page into. [playback] is a closed page's, brought back
/// by the small window's restore button: the page takes it over instead of opening the video.
@immutable
final class VideoRoute {
  const VideoRoute({
    required this.bvid,
    this.cid,
    this.start,
    this.title,
    this.cover,
    this.view,
    this.detail,
    this.zoomSource,
    this.playback,
  });

  final String bvid;
  final int? cid;
  final double? start;
  final String? title;
  final String? cover;
  final VideoView? view;
  final VideoDetail? detail;
  final ZoomSource? zoomSource;
  final PagePlayback? playback;

  /// The feed card's cover and the page's player box share it, so the cover flies into the player.
  static String coverTag(String bvid) => 'cover-$bvid';

  String get heroTag => coverTag(bvid);
}

/// Every way of opening a video page from elsewhere (feed cards, pasted links, 最近打开, a space) comes through here.
/// The iPad's page slides in and swipes back as a plain page, from 推荐 too (21).
Future<void> openVideoPage(BuildContext context, VideoRoute route) {
  if (route.cover case final cover? when cover.isNotEmpty) VideoPage.precacheCover(context, cover);
  Widget page(BuildContext _) => VideoPage(route: route);
  final zoom = FormFactor.of(context).isPad ? null : route.zoomSource;
  return Navigator.of(context).push(switch (zoom) {
    final source? => ZoomBackPageRoute<void>(builder: page, source: source),
    null => SwipeBackPageRoute<void>(builder: page),
  });
}

/// A video opened on a video page (a related video, a link in 简介 or a comment, the uploader sheet's videos) takes
/// that page's place, so back goes to what the first page was opened from: video pages never stack (KaiC). The page
/// replaced leaves as a popped one does. [page] builds the new page; tests give theirs.
Future<void> replaceVideoPage(BuildContext context, VideoRoute route, {Widget Function(VideoRoute route)? page}) {
  if (route.cover case final cover? when cover.isNotEmpty) VideoPage.precacheCover(context, cover);
  final build = page ?? (route) => VideoPage(route: route);
  final next = SwipeBackPageRoute<void>(builder: (_) => build(route));
  final navigator = Navigator.of(context);
  // pushReplacement replaces whatever route is on top; with anything over the page it goes on top instead.
  if (ModalRoute.of(context)?.isCurrent ?? false) return navigator.pushReplacement(next);
  return navigator.push(next);
}
