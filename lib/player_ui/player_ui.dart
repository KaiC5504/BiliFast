import 'package:flutter/foundation.dart';

import '../device/device_controls.dart';
import '../danmaku/danmaku_session.dart';
import '../device/orientation.dart';
import '../device/status_bar.dart';
import '../video/page_details.dart';
import '../video/player_session.dart';
import '../video/story/story_drag.dart';
import '../video/story/story_feed.dart';
import 'chrome_state.dart';
import 'panels/panel_controller.dart';
import 'speed_lock.dart';

/// Everything a piece of the player's interface works with, handed to each as one value.
@immutable
final class PlayerUi {
  const PlayerUi({
    required this.session,
    required this.chrome,
    required this.panels,
    required this.orientation,
    required this.device,
    required this.onBack,
    this.details,
    this.onComments,
    this.overlay,
    this.edgeTaken,
    this.danmaku,
    this.layout,
    this.statusBar,
    this.replyCount,
    this.story,
    this.storyDrag,
    this.clean,
    this.speedLock,
  });

  final PlayerSession session;
  final ChromeState chrome;
  final PanelController panels;
  final OrientationController orientation;
  final DeviceControls device;

  /// The back arrow: from full screen to the small player, from the small player off the page.
  final VoidCallback onBack;

  /// The page body's uploader, N人正在看 and actions, for the full-screen chrome and the end screens; null outside
  /// a video page.
  final PageDetails? details;

  /// 评论 in full screen: back to the small player on the 评论 tab.
  final VoidCallback? onComments;

  /// What the page's action overlays have up, null when nothing; the chrome stands aside while it isn't.
  final ValueListenable<Object?>? overlay;

  /// True while something on the page (评论详情) closes on the left-edge swipe in place of the route: the small
  /// player's drag leaves that edge to it, as it does to the route's own swipe back.
  final ValueListenable<bool>? edgeTaken;

  /// The page's danmaku: settings, 屏蔽词, sending; null outside a video page.
  final DanmakuSession? danmaku;

  /// What the page has laid out, which trails the orientation through a turn until the screen has its new shape;
  /// null outside a video page, where the orientation's presentation is the layout.
  final ValueListenable<Presentation>? layout;

  /// The battery and network for the status bar landscape full screen draws (04); null draws none.
  final StatusBarFeed? statusBar;

  /// 评论's count as the page's tab row shows it, following posts and deletes once the list is in; null until then,
  /// when the video's own count stands.
  final ValueListenable<int?>? replyCount;

  /// 竖屏's feed while 竖屏 is up, null otherwise; null outside a video page.
  final ValueListenable<StoryFeed?>? story;

  /// 竖屏's page under the finger; null outside a video page.
  final StoryDrag? storyDrag;

  /// 竖屏's 清屏: the controls hidden but for 人正在看, play or pause with the time, the progress line and the bottom
  /// bar (180, 186); null outside a video page.
  final ValueNotifier<bool>? clean;

  /// 竖屏's held 2× and its lock; null outside a video page.
  final SpeedLock? speedLock;

  /// The count beside 评论 in full screen.
  int? get replies => replyCount?.value ?? session.detail?.stat.reply;

  /// The presentation the player is drawn in: what panels and gestures fit themselves to. What the user asked for is
  /// [orientation]'s.
  Presentation get presentation => layout?.value ?? orientation.presentation;

  /// Fires when [presentation] may have changed.
  Listenable get presentationChanges => layout ?? orientation;
}
