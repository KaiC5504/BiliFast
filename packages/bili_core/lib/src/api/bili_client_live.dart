part of 'bili_client.dart';

/// 直播's calls, on `api.live.bilibili.com` (the website's) apart from the tab's feed, which is the official app's.
extension BiliClientLive on BiliClient {
  /// The 直播 tab's feed (`xlive/app-interface/v2/index/feed`) under the held identity, page [page] from 1.
  Future<LiveFeedPage> liveFeed({required int page}) => throw UnimplementedError('liveFeed');

  /// An area tab's rooms, page [page] from 1.
  Future<LiveCardPage> liveArea(LiveArea area, {required int page}) => throw UnimplementedError('liveArea');

  /// 206: the followed rooms that are live, page [page] from 1.
  Future<LiveCardPage> liveFollowing({required int page}) => throw UnimplementedError('liveFollowing');

  /// The room's status and its HLS stream at [qn] (the room's default when null).
  Future<LivePlayInfo> livePlayInfo(int roomId, {int? qn}) => throw UnimplementedError('livePlayInfo');

  /// The header's and the chat's room card's words.
  Future<LiveRoomInfo> liveRoomInfo(int roomId) => throw UnimplementedError('liveRoomInfo');

  /// The danmaku socket's token and hosts.
  Future<LiveDanmuInfo> liveDanmuInfo(int roomId) => throw UnimplementedError('liveDanmuInfo');

  /// The chat's last lines before the socket's.
  Future<List<LiveChatMessage>> liveHistory(int roomId) => throw UnimplementedError('liveHistory');

  /// The 醒目留言 still showing.
  Future<List<LiveSuperChat>> liveSuperChats(int roomId) => throw UnimplementedError('liveSuperChats');

  /// 房间观众's 在线榜, page [page] from 1; [anchorUid] is the room's `uid`.
  Future<LiveRankPage> liveRank(int roomId, {required int anchorUid, required int page}) =>
      throw UnimplementedError('liveRank');

  /// 大航海's [tab], page [page] from 1.
  Future<LiveGuardPage> liveGuards(int roomId, {required int anchorUid, required LiveGuardTab tab, required int page}) =>
      throw UnimplementedError('liveGuards');

  /// The emote packages the viewer may send in the room.
  Future<List<LiveEmotePackage>> liveEmotes(int roomId) => throw UnimplementedError('liveEmotes');

  /// Sends [text] as a danmaku.
  Future<void> liveSend(int roomId, String text) => throw UnimplementedError('liveSend');

  /// Sends [emote] as a whole-message danmaku.
  Future<void> liveSendEmote(int roomId, LiveEmote emote) => throw UnimplementedError('liveSendEmote');

  /// [clicks] double taps' 点赞, sent as one.
  Future<void> liveLike(int roomId, {required int anchorUid, required int uid, required int clicks}) =>
      throw UnimplementedError('liveLike');

  /// `roomEntryAction`: the room goes into 历史记录.
  Future<void> liveEnter(int roomId) => throw UnimplementedError('liveEnter');
}
