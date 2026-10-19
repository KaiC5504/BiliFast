import Flutter
import UIKit

/// The video page's turns drawn by Flutter instead of the scene (lib/video/video_page.dart): with the system's
/// rotation animation off, Flutter gets the turned size at once instead of halfway through, so the page can turn
/// while the player grows past the upright page's sides, as the official app's does.
@MainActor
enum TurnTakeover {
  /// Set from Dart's 开发者 switch 旋转动画 (DeviceHostApi.setTurnTakeover).
  static var enabled = false

  /// Flutter drew the turn's first frame; the still picture goes.
  static func drawn() {}
}

/// Main.storyboard's root view controller.
class TurnViewController: FlutterViewController {}
