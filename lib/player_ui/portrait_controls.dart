import 'package:flutter/widgets.dart';

import 'player_ui.dart';

/// The small player's controls, filling the player (BiliNative `PortraitControls.swift`): back, ⋮, play, the bar
/// with the TV face, the time, 竖屏 and full screen, and the thin line left while they are hidden.
class PortraitControls extends StatelessWidget {
  const PortraitControls({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
