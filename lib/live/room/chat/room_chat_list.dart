import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../shared/theme.dart';
import '../live_chat_item.dart';
import 'room_chat_rows.dart';

/// The chat, newest at the bottom and stuck there. Scrolled up, it holds the rows it shows (new ones wait, so nothing
/// moves under the finger or the eye); back at the bottom it takes the latest and sticks again. Its top fades out.
class RoomChatList extends StatefulWidget {
  const RoomChatList({super.key, required this.chat, required this.now});

  final ValueListenable<List<LiveChatItem>> chat;
  final DateTime Function() now;

  @override
  State<RoomChatList> createState() => _RoomChatListState();
}

class _RoomChatListState extends State<RoomChatList> {
  final _scroll = ScrollController();
  late List<LiveChatItem> _shown = widget.chat.value;

  /// The list is reversed, so the bottom is offset 0.
  bool get _atBottom => !_scroll.hasClients || _scroll.offset <= 1;

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_chatChanged);
    _scroll.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(RoomChatList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat != widget.chat) {
      oldWidget.chat.removeListener(_chatChanged);
      widget.chat.addListener(_chatChanged);
      _shown = widget.chat.value;
    }
  }

  @override
  void dispose() {
    widget.chat.removeListener(_chatChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _chatChanged() {
    if (_atBottom) setState(() => _shown = widget.chat.value);
  }

  void _scrolled() {
    if (_atBottom && !identical(_shown, widget.chat.value)) setState(() => _shown = widget.chat.value);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0x00000000), Color(0xFF000000)],
        stops: [0, (LiveRoomTheme.chatFade / bounds.height).clamp(0, 1)],
      ).createShader(bounds),
      child: ListView.builder(
        key: const ValueKey('live-chat'),
        controller: _scroll,
        reverse: true,
        padding: EdgeInsets.zero,
        itemCount: shown.length,
        itemBuilder: (context, index) {
          final item = shown[shown.length - 1 - index];
          return Padding(
            padding: EdgeInsets.only(
              left: LiveRoomTheme.chatLeft,
              top: index == shown.length - 1 ? 0 : LiveRoomTheme.rowGap,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: LiveRoomTheme.chatRight - LiveRoomTheme.chatLeft),
                child: RoomChatRow(item: item, now: widget.now),
              ),
            ),
          );
        },
      ),
    );
  }
}
