import 'package:bili_core/api.dart';
import 'package:bili_core/live.dart';

/// A row of a room's chat (207, 208, 228).
sealed class LiveChatItem {
  const LiveChatItem();
}

/// 系统提示's card, first in every room.
final class LiveChatNotice extends LiveChatItem {
  const LiveChatNotice(this.text);

  final String text;
}

/// The room's card: its title, the anchor's announcement and how long it has been live (05:12:37).
final class LiveChatRoomCard extends LiveChatItem {
  const LiveChatRoomCard({required this.title, this.description = '', this.liveTime});

  final String title;
  final String description;
  final DateTime? liveTime;
}

final class LiveChatDanmaku extends LiveChatItem {
  const LiveChatDanmaku(this.message, {this.own = false});

  final LiveChatMessage message;

  /// Sent from this phone (shown at once, before the socket echoes it).
  final bool own;
}

/// 进入直播间, 关注了主播, 分享了直播间, 为主播点赞了.
final class LiveChatInteraction extends LiveChatItem {
  const LiveChatInteraction(this.kind, this.user);

  final LiveInteraction kind;
  final LiveUser user;
}

final class LiveChatSuperChat extends LiveChatItem {
  const LiveChatSuperChat(this.superChat);

  final LiveSuperChat superChat;
}

/// The pink tip (试试双击点赞，让主播被更多人看到吧～).
final class LiveChatTip extends LiveChatItem {
  const LiveChatTip(this.text);

  final String text;
}
