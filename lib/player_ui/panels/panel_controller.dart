import 'package:flutter/foundation.dart';

/// The panels over the player (BiliNative `Player/Panels/`): a right-side panel in landscape, a bottom sheet in
/// portrait, both inside the page.
enum PlayerPanel { quality, codec, speed, more, episodes }

/// The open panel, or null. Opening one replaces the last.
class PanelController extends ValueNotifier<PlayerPanel?> {
  PanelController() : super(null);

  void open(PlayerPanel panel) => value = panel;

  void close() => value = null;
}
