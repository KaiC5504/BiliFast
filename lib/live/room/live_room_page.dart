import 'package:flutter/widgets.dart';

import '../live_entry.dart';

/// A room (207-209, 221-233): its header, the player, the chat and the bottom bar in portrait; the full-screen player
/// in landscape; the overlays over both.
class LiveRoomPage extends StatefulWidget {
  const LiveRoomPage({super.key, required this.entry});

  final LiveRoomEntry entry;

  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
