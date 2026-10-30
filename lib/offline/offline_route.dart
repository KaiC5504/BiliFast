import 'package:flutter/widgets.dart';

import '../app/swipe_back_route.dart';
import '../video/video_page.dart';
import '../video/video_route.dart';
import 'offline_models.dart';
import 'page/offline_playback.dart';

/// The route that plays [item] on an offline page, from where the library saw it stop.
VideoRoute offlineRoute(OfflineItem item) =>
    VideoRoute(bvid: item.request.bvid, cid: item.cid, title: item.request.title, offline: true);

/// Plays a finished part on its own page (158): the player over the phone's copy, and below it every cached video
/// (离线缓存 (N个视频)), each row's ⋮ offering 查看详情页 (159). The same online and offline (160, 161).
Future<void> openOfflinePage(BuildContext context, OfflineItem item) => Navigator.of(context).push(
  SwipeBackPageRoute<void>(
    builder: (_) => VideoPage(route: offlineRoute(item), createSession: offlinePageSession),
  ),
);
