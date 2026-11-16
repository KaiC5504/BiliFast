import '../api/live_models.dart';

/// What the danmaku socket tells a room, one per command it understands.
sealed class LiveEvent {
  const LiveEvent();
}

/// `DANMU_MSG`.
final class LiveDanmakuEvent extends LiveEvent {
  const LiveDanmakuEvent(this.message);

  final LiveChatMessage message;
}

/// `SUPER_CHAT_MESSAGE`.
final class LiveSuperChatEvent extends LiveEvent {
  const LiveSuperChatEvent(this.superChat);

  final LiveSuperChat superChat;
}

/// `SUPER_CHAT_MESSAGE_DELETE`.
final class LiveSuperChatDeletedEvent extends LiveEvent {
  const LiveSuperChatDeletedEvent(this.ids);

  final List<int> ids;
}

/// `WATCHED_CHANGE`: the 看过 words.
final class LiveWatchedEvent extends LiveEvent {
  const LiveWatchedEvent(this.text);

  final String text;
}

/// `ONLINE_RANK_COUNT`: the number after the header's three faces.
final class LiveOnlineCountEvent extends LiveEvent {
  const LiveOnlineCountEvent(this.count);

  final int count;
}

/// `ONLINE_RANK_V2` / `ONLINE_RANK_TOP3`: the header's three faces.
final class LiveTopFacesEvent extends LiveEvent {
  const LiveTopFacesEvent(this.faces);

  final List<String> faces;
}

/// `LIKE_INFO_V3_UPDATE`: the 点赞 total under the anchor's name.
final class LiveLikeCountEvent extends LiveEvent {
  const LiveLikeCountEvent(this.count);

  final int count;
}

enum LiveInteraction { entered, followed, shared, liked }

/// `INTERACT_WORD` (进入直播间, 关注了主播, 分享了直播间) and `LIKE_INFO_V3_CLICK` (为主播点赞了).
final class LiveInteractEvent extends LiveEvent {
  const LiveInteractEvent(this.kind, this.user);

  final LiveInteraction kind;
  final LiveUser user;
}

/// `ROOM_CHANGE`: the title (or area) changed.
final class LiveRoomChangedEvent extends LiveEvent {
  const LiveRoomChangedEvent({required this.title, this.areaName = ''});

  final String title;
  final String areaName;
}

/// `LIVE` / `PREPARING`: the room started or ended.
final class LiveStatusEvent extends LiveEvent {
  const LiveStatusEvent({required this.live});

  final bool live;
}

enum LiveSocketState { connecting, open, closed, failed }
