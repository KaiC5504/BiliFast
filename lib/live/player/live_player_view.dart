import 'package:flutter/widgets.dart';

import '../room/live_overlays.dart';
import '../room/live_room_model.dart';
import 'live_player_controller.dart';

/// The picture with its controls: the 16:9 box with 弹 and the full-screen button in portrait (207, 208), the whole
/// screen with 209's controls when [fullScreen]. The danmaku over the video sit inside it. Opens [overlays]' layers
/// (⋮, 画质, 高能榜, the 弹幕 input); [onBack] is 209's ‹.
class LivePlayerView extends StatelessWidget {
  const LivePlayerView({
    super.key,
    required this.controller,
    required this.room,
    required this.overlays,
    required this.fullScreen,
    required this.onBack,
  });

  final LivePlayerController controller;
  final LiveRoomModel room;
  final LiveOverlays overlays;
  final bool fullScreen;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
