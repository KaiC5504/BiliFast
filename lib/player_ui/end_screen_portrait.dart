import 'package:flutter/widgets.dart';

import 'player_ui.dart';

/// The small player's end screen (BiliNative `EndScreens.swift`): 推荐视频 with the first related video and
/// 立即播放, 重播 and 分享. It fills the player.
class EndScreenPortrait extends StatelessWidget {
  const EndScreenPortrait({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
