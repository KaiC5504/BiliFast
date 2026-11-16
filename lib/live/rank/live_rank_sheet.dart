import 'package:flutter/widgets.dart';

import '../room/live_overlays.dart';
import '../room/live_room_model.dart';

/// 高能榜: 房间观众 and 大航海, a sheet from the bottom in portrait (230, 231), a panel on the right in full screen
/// (232, 233).
class LiveRankSheet extends StatefulWidget {
  const LiveRankSheet({super.key, required this.room, required this.overlays, required this.landscape});

  final LiveRoomModel room;
  final LiveOverlays overlays;
  final bool landscape;

  @override
  State<LiveRankSheet> createState() => _LiveRankSheetState();
}

class _LiveRankSheetState extends State<LiveRankSheet> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
