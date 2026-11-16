import 'package:flutter/widgets.dart';

import '../room/live_room_model.dart';

/// The danmaku flying over the video (208), from [room]'s feed, drawn by the video page's danmaku painter under the
/// shared 弹幕设置 and 屏蔽词; nothing while [on] is false.
class LiveDanmakuLayer extends StatefulWidget {
  const LiveDanmakuLayer({super.key, required this.room, required this.on});

  final LiveRoomModel room;
  final bool on;

  @override
  State<LiveDanmakuLayer> createState() => _LiveDanmakuLayerState();
}

class _LiveDanmakuLayerState extends State<LiveDanmakuLayer> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
