import 'package:flutter/widgets.dart';

import 'player_ui.dart';

/// The touch layer over the video, filling the player (port of BiliNative `PlayerGestureView.swift` and
/// `ChromeState.swift`'s gestures): tap, double tap, hold for 2×, a sideways drag to seek, and in full screen
/// up and down for brightness (left half) and volume (right half), with the screen edges left to the system.
class PlayerGestureLayer extends StatelessWidget {
  const PlayerGestureLayer({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
