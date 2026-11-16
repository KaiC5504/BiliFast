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

  /// The 弹幕 input opens on its emote panel rather than the keyboard (full screen's capsule face).
  bool sendOnEmotes = false;

  void open(LiveOverlay overlay) {
    if (overlay == LiveOverlay.send) sendOnEmotes = false;
    value = overlay;
  }

  void openSend({bool emotes = false}) {
    sendOnEmotes = emotes;
    value = LiveOverlay.send;
  }

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
