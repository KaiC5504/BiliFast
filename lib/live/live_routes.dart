import 'package:flutter/widgets.dart';

import '../app/swipe_back_route.dart';
import '../app/zoom_back_route.dart';
import 'following/live_following_page.dart';
import 'live_entry.dart';
import 'room/live_room_page.dart';

/// A room (207), pushed plainly; with [source], the card it came from, leaving shrinks it back into that card (225).
Future<void> openLiveRoom(BuildContext context, LiveRoomEntry entry, {ZoomSource? source}) {
  Widget build(BuildContext _) => LiveRoomPage(entry: entry);
  return Navigator.of(context).push(
    source == null
        ? SwipeBackPageRoute<void>(builder: build)
        : ZoomBackPageRoute<void>(builder: build, source: source),
  );
}

/// 206: the followed rooms that are live, from the tab's 查看全部.
Future<void> openLiveFollowing(BuildContext context) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => const LiveFollowingPage()));
