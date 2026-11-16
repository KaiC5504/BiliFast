import 'package:flutter/widgets.dart';

import '../room/live_overlays.dart';
import '../room/live_room_model.dart';

/// The 弹幕 input over the keyboard: 226 and its emote panel 227 in portrait, 223 in full screen. Closes through
/// [overlays] once sent or dismissed.
class LiveSendInput extends StatefulWidget {
  const LiveSendInput({super.key, required this.room, required this.overlays, required this.landscape});

  final LiveRoomModel room;
  final LiveOverlays overlays;
  final bool landscape;

  @override
  State<LiveSendInput> createState() => _LiveSendInputState();
}

class _LiveSendInputState extends State<LiveSendInput> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
