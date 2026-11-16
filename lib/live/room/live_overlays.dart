import 'package:flutter/foundation.dart';

/// The in-page layer a room shows over itself; one at a time, back closes it first.
enum LiveOverlay {
  none,

  /// 221 in portrait, 222 in landscape.
  more,

  /// 210 (and its portrait sheet).
  quality,

  /// The existing 弹幕设置 panel.
  danmakuSettings,

  /// 高能榜: 230-233.
  rank,

  /// The 弹幕 input: 226, 227, 223.
  send,

  /// A 醒目留言's card (228), [LiveOverlays.superChatId] naming which.
  superChat,
}

/// Which layer the room page shows; the player, the sheets and the chat open and close them through it.
class LiveOverlays extends ValueNotifier<LiveOverlay> {
  LiveOverlays() : super(LiveOverlay.none);

  int? superChatId;

  void open(LiveOverlay overlay) => value = overlay;

  void openSuperChat(int id) {
    superChatId = id;
    value = LiveOverlay.superChat;
  }

  /// Whether a layer was open to close (back closes it, not the page).
  bool close() {
    if (value == LiveOverlay.none) return false;
    value = LiveOverlay.none;
    return true;
  }
}
