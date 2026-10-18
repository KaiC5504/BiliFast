import 'package:flutter/foundation.dart';

import '../device/device_controls.dart';
import '../device/orientation.dart';
import '../video/player_session.dart';
import 'chrome_state.dart';
import 'panels/panel_controller.dart';

/// Everything a piece of the player's interface works with, handed to each as one value.
@immutable
final class PlayerUi {
  const PlayerUi({
    required this.session,
    required this.chrome,
    required this.panels,
    required this.orientation,
    required this.device,
    required this.onBack,
  });

  final PlayerSession session;
  final ChromeState chrome;
  final PanelController panels;
  final OrientationController orientation;
  final DeviceControls device;

  /// The back arrow: from full screen to the small player, from the small player off the page.
  final VoidCallback onBack;

  Presentation get presentation => orientation.presentation;
}
