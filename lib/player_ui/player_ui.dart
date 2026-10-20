import 'package:flutter/foundation.dart';

import '../device/device_controls.dart';
import '../danmaku/danmaku_session.dart';
import '../device/orientation.dart';
import '../device/status_bar.dart';
import '../video/page_details.dart';
import '../video/player_session.dart';
import 'chrome_state.dart';
import 'panels/panel_controller.dart';

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

  /// The presentation the player is drawn in: what panels and gestures fit themselves to. What the user asked for is
  /// [orientation]'s.
  Presentation get presentation => layout?.value ?? orientation.presentation;

  /// Fires when [presentation] may have changed.
  Listenable get presentationChanges => layout ?? orientation;
}
