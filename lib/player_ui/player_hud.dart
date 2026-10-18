import 'package:flutter/widgets.dart';

import 'player_ui.dart';

/// The gesture HUD in the middle of the player: 倍速中, the seek time, brightness and volume (BiliNative
/// `PlayerHUD.swift`). It fills the player and takes no touches.
class PlayerHud extends StatelessWidget {
  const PlayerHud({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
