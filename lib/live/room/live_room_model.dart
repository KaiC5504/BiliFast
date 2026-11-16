import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:flutter/foundation.dart';

import '../live_api.dart';
import '../live_entry.dart';
import 'live_chat_item.dart';

enum LiveRoomState {
  /// The first calls are out.
  loading,
  live,

  /// The room wasn't live when opened, or ended while watched (PREPARING).
  ended,

  /// The play info failed; [LiveRoomModel.retry] asks again.
  failed,
}

/// One open room: its info, stream, chat, 醒目留言 and counts, the danmaku socket's life, sending and 点赞.
/// Every page and widget of the room reads it; the player plays [play]'s stream.
class LiveRoomModel extends ChangeNotifier {
  LiveRoomModel({required this.api, required this.entry, required this.loggedIn, DateTime Function()? now})
    : now = now ?? DateTime.now;

  final LiveApi api;
  final LiveRoomEntry entry;
  final bool Function() loggedIn;
  final DateTime Function() now;

  LiveRoomState get state => LiveRoomState.loading;

  /// The real room id once the play info answers, else the entry's.
  int get roomId => entry.roomId;

  LiveRoomInfo? get info => null;
  LivePlayInfo? get play => null;

  /// The 点赞 total under the anchor's name, following the socket.
  int get likeCount => 0;

  /// The number after the header's three faces, following the socket.
  int get onlineCount => 0;
  List<String> get topFaces => const [];

  bool get following => false;

  /// The chat, oldest first, at most 500 rows.
  ValueListenable<List<LiveChatItem>> get chat => _chat;
  final _chat = ValueNotifier<List<LiveChatItem>>(const []);

  /// The 醒目留言 still showing, for the strip under the video, newest first.
  ValueListenable<List<LiveSuperChat>> get superChats => _superChats;
  final _superChats = ValueNotifier<List<LiveSuperChat>>(const []);

  /// Each danmaku as it arrives (the socket's and this phone's own), for the danmaku over the video.
  Stream<LiveChatMessage> get flying => const Stream.empty();

  /// Asks the info, the play info and the history, then opens the socket while [setShown] says shown.
  Future<void> start() async {}

  Future<void> retry() async {}

  /// The page is on screen (true) or covered / the app away (false): the socket closes away and comes back on return.
  void setShown(bool shown) {}

  /// Asks the play info again at [qn]; [play] follows.
  Future<void> setQuality(int qn) async {}

  /// ⟳: asks the play info again at the current quality.
  Future<void> refreshStream() async {}

  /// Sends [text]; the row shows at once, a failure throws (the caller toasts it).
  Future<void> send(String text) async {}

  Future<void> sendEmote(LiveEmote emote) async {}

  /// A double tap's 点赞; taps are gathered and sent as one.
  void like() {}

  Future<void> setFollowing(bool on) async {}

  @override
  void dispose() {
    _chat.dispose();
    _superChats.dispose();
    super.dispose();
  }
}
