import Flutter
import UIKit

/// What every native turn line carries besides its own fields (docs/reference/turn-log.md). The method is
/// `quietRequest` for a taken-over turn: the rotation requested with UIView animations already off.
struct TurnTag: Sendable {
  let turn: Int
  /// A turn iOS animates itself (takeover off), logged as method `system`.
  var system = false
}

/// The native side of a turn for the phone's log (docs/reference/turn-log.md): the request, what UIKit did and when
/// the picture went, sent to Dart as `turn native …` lines.
@MainActor
enum TurnProbe {
  /// Sends to Dart that failed since the last line that got through, carried by the next line as `lost`.
  private static var lost = 0
  private static var failureLogged = false

  /// One line for the phone's log, sent from a task so it never runs inside a turn's setup. `fields` hold strings,
  /// ints, doubles and bools only; `wUs` is now unless given.
  static func log(_ kind: String, _ tag: TurnTag, _ fields: [String: any Sendable] = [:], at wUs: Int64? = nil) {
    var line = fields
    line["wUs"] = wUs ?? wallUs()
    line["turn"] = tag.turn
    line["method"] = tag.system ? "system" : "quietRequest"
    Task { @MainActor [line] in
      guard let events = DeviceChannel.events else { return }
      var sent: [String: Any?] = [:]
      for (key, value) in line {
        sent.updateValue(value, forKey: key)
      }
      // Taken as the line goes, so a count rides on one line only; a line that fails hands it back.
      let carried = lost
      lost = 0
      if carried > 0 { sent.updateValue(carried, forKey: "lost") }
      do {
        try await events.onTurnLog(kind: kind, fields: sent)
      } catch {
        lost += carried
        failed("onTurnLog", error)
      }
    }
  }

  /// A turn event for Dart, sent from a task; a failure counts towards the next line's `lost`.
  static func send(_ name: String, _ call: @escaping @MainActor () async throws -> Void) {
    Task { @MainActor in
      do {
        try await call()
      } catch {
        failed(name, error)
      }
    }
  }

  private static func failed(_ name: String, _ error: any Error) {
    lost += 1
    guard !failureLogged else { return }
    failureLogged = true
    NSLog("TurnProbe: %@ failed: %@", name, String(describing: error))
  }

  static func wallUs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000_000)
  }

  static func name(_ orientation: UIInterfaceOrientation) -> String {
    switch orientation {
    case .portrait: return "portrait"
    case .portraitUpsideDown: return "portraitUpsideDown"
    case .landscapeLeft: return "landscapeLeft"
    case .landscapeRight: return "landscapeRight"
    default: return "unknown"
    }
  }
}
