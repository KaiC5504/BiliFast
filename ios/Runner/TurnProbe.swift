import Flutter
import UIKit

/// The native side of a drawn turn for the phone's log (docs/reference/turn-log.md): what UIKit did, every screen
/// frame's layer angles while the turn runs, sent to Dart as `turn native …` lines.
@MainActor
enum TurnProbe {
  /// One line for the phone's log; [fields] hold strings, ints, doubles and bools only.
  static func log(_ kind: String, _ fields: [String: Any?]) {
    Task { @MainActor in try? await DeviceChannel.events?.onTurnLog(kind: kind, fields: fields) }
  }
}
