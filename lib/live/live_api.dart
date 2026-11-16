import 'package:bili_core/api.dart';
import 'package:bili_core/live.dart';

/// 直播's calls: the tab's lists, a room's stream, info, chat, 醒目留言, 高能榜, emotes and writes, and its danmaku
/// socket.
abstract interface class LiveApi {
  Future<LiveFeedPage> feed({required int page});
  Future<LiveCardPage> area(LiveArea area, {required int page});
  Future<LiveCardPage> following({required int page});

  Future<LivePlayInfo> playInfo(int roomId, {int? qn});

  /// Sent with every request for the stream (User-Agent and Referer).
  Map<String, String> get streamHeaders;

  Future<LiveRoomInfo> roomInfo(int roomId);
  Future<List<LiveChatMessage>> history(int roomId);
  Future<List<LiveSuperChat>> superChats(int roomId);
  Future<LiveRankPage> rank(int roomId, {required int anchorUid, required int page});
  Future<LiveGuardPage> guards(int roomId, {required int anchorUid, required LiveGuardTab tab, required int page});
  Future<List<LiveEmotePackage>> emotes(int roomId);

  /// The room's danmaku feed, not yet started.
  Future<LiveChannel> channel(int roomId);

  Future<void> send(int roomId, String text);
  Future<void> sendEmote(int roomId, LiveEmote emote);
  Future<void> like(int roomId, {required int anchorUid, required int clicks});
  Future<void> enter(int roomId);

  /// 关注 in the header, through `/x/relation/modify`.
  Future<void> follow(int mid, {required bool on});
}

/// [LiveApi] on [BiliClient]; [mid] is the logged-in account's (0 logged out), for the socket and 点赞.
class ClientLiveApi implements LiveApi {
  ClientLiveApi(this._client, {required this.mid});

  final BiliClient _client;
  final int Function() mid;

  @override
  Future<LiveFeedPage> feed({required int page}) => _client.liveFeed(page: page);

  @override
  Future<LiveCardPage> area(LiveArea area, {required int page}) => _client.liveArea(area, page: page);

  @override
  Future<LiveCardPage> following({required int page}) => _client.liveFollowing(page: page);

  @override
  Future<LivePlayInfo> playInfo(int roomId, {int? qn}) => _client.livePlayInfo(roomId, qn: qn);

  @override
  Map<String, String> get streamHeaders => const {
    'User-Agent': BiliClient.userAgent,
    'Referer': 'https://live.bilibili.com/',
  };

  @override
  Future<LiveRoomInfo> roomInfo(int roomId) => _client.liveRoomInfo(roomId);

  @override
  Future<List<LiveChatMessage>> history(int roomId) => _client.liveHistory(roomId);

  @override
  Future<List<LiveSuperChat>> superChats(int roomId) => _client.liveSuperChats(roomId);

  @override
  Future<LiveRankPage> rank(int roomId, {required int anchorUid, required int page}) =>
      _client.liveRank(roomId, anchorUid: anchorUid, page: page);

  @override
  Future<LiveGuardPage> guards(int roomId, {required int anchorUid, required LiveGuardTab tab, required int page}) =>
      _client.liveGuards(roomId, anchorUid: anchorUid, tab: tab, page: page);

  @override
  Future<List<LiveEmotePackage>> emotes(int roomId) => _client.liveEmotes(roomId);

  @override
  Future<LiveChannel> channel(int roomId) async {
    final info = await _client.liveDanmuInfo(roomId);
    final buvid = _client.cookies.value('buvid3');
    return LiveSocket(
      roomId: roomId,
      uid: mid(),
      info: info,
      headers: {
        'User-Agent': BiliClient.userAgent,
        'Origin': 'https://live.bilibili.com',
        if (buvid != null && buvid.isNotEmpty) 'Cookie': 'buvid3=$buvid',
      },
    );
  }

  @override
  Future<void> send(int roomId, String text) => _client.liveSend(roomId, text);

  @override
  Future<void> sendEmote(int roomId, LiveEmote emote) => _client.liveSendEmote(roomId, emote);

  @override
  Future<void> like(int roomId, {required int anchorUid, required int clicks}) =>
      _client.liveLike(roomId, anchorUid: anchorUid, uid: mid(), clicks: clicks);

  @override
  Future<void> enter(int roomId) => _client.liveEnter(roomId);

  @override
  Future<void> follow(int mid, {required bool on}) => _client.follow(mid: mid, on: on);
}
