import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../room/live_room_model.dart';

/// A room's player: plays [room]'s stream on its own [BiliPlayer], follows its quality and ⟳, and owns full screen,
/// the lock, 弹 (kept between rooms), picture in picture, background sound and the lock screen.
class LivePlayerController extends ChangeNotifier {
  LivePlayerController({required this.room, required this.services});

  final LiveRoomModel room;
  final AppServices services;

  bool get playing => false;

  /// Full screen (209), whether turned by the button or the phone.
  bool get fullScreen => false;

  /// The controls are locked (209's 🔓).
  bool get locked => false;

  /// 弹: danmaku over the video.
  bool get danmakuOn => true;

  /// Starts playing once [room]'s play info is in, and again whenever it changes.
  Future<void> start() async {}

  Future<void> togglePlay() async {}
  Future<void> setFullScreen(bool on) async {}
  void setLocked(bool on) {}
  void setDanmakuOn(bool on) {}

  /// The room's link through iOS's share sheet (221's and 222's 分享).
  Future<void> share(BuildContext context) async {}

  /// 小窗播放.
  Future<void> startPictureInPicture() async {}

  /// The page is covered or shown (pauses and resumes as a video page does).
  void setCovered(bool covered) {}
}
