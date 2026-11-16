import 'package:flutter/widgets.dart';

import '../room/live_overlays.dart';
import '../room/live_room_model.dart';
import 'live_player_controller.dart';

/// 222: full screen's ⋮ panel on the right.
class LiveMorePanel extends StatelessWidget {
  const LiveMorePanel({super.key, required this.controller, required this.room, required this.overlays});

  final LivePlayerController controller;
  final LiveRoomModel room;
  final LiveOverlays overlays;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 210: the room's qualities, on the right in full screen, as a sheet from the bottom in portrait.
class LiveQualityPicker extends StatelessWidget {
  const LiveQualityPicker({
    super.key,
    required this.controller,
    required this.room,
    required this.overlays,
    required this.landscape,
  });

  final LivePlayerController controller;
  final LiveRoomModel room;
  final LiveOverlays overlays;
  final bool landscape;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 弹幕设置: the video page's panel over the live danmaku's settings.
class LiveDanmakuSettingsPanel extends StatelessWidget {
  const LiveDanmakuSettingsPanel({super.key, required this.controller, required this.overlays, required this.landscape});

  final LivePlayerController controller;
  final LiveOverlays overlays;
  final bool landscape;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
