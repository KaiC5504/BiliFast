import 'package:flutter/foundation.dart';

/// The panels over the player (BiliNative `Player/Panels/`): a right-side panel in landscape, a bottom sheet in
/// portrait, both inside the page.
enum PlayerPanel {
  quality,
  codec,
  speed,
  more,
  episodes,
  danmakuSettings,

  /// 添加屏蔽词 (30), over the whole screen; landscape only.
  blockWords,

  /// 当前弹幕列表 (31); landscape only.
  danmakuList,

  /// 缓存 (141, 144, 153, 154): the light sheet under the player that queues parts for 离线缓存; portrait only.
  download,
}

/// The open panel, or null. Opening one replaces the last.
class PanelController extends ValueNotifier<PlayerPanel?> {
  PanelController() : super(null);

  void open(PlayerPanel panel) => value = panel;

  void close() => value = null;
}
