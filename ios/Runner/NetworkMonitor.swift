import Flutter
import Network

/// The phone's network path for the engine (port of PlaybackController.swift's NWPathMonitor), reported through
/// DeviceEventApi.onNetworkChanged: bans and backoffs earned on the old path would keep the engine off nodes that
/// work on the new one.
@MainActor
enum NetworkMonitor {
  /// One for the app's life.
  private static var monitor: NWPathMonitor?
  private static var changes = NetworkPathChanges()

  static func start() {
    guard monitor == nil else { return }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
      let now = NetworkPath(up: path.status == .satisfied, interfaces: path.availableInterfaces.map(\.name),
                            gateways: path.gateways.map { "\($0)" })
      MainActor.assumeIsolated { NetworkMonitor.pathUpdated(now) }
    }
    monitor.start(queue: .main)
    self.monitor = monitor
  }

  private static func pathUpdated(_ path: NetworkPath) {
    guard let interfaceChanged = changes.next(path) else { return }
    Task { @MainActor in try? await DeviceChannel.events?.onNetworkChanged(interfaceChanged: interfaceChanged) }
  }
}

/// A path as the engine cares about it, apart from Network's types.
struct NetworkPath: Equatable {
  let up: Bool
  let interfaces: [String]
  let gateways: [String]
}

/// Which path updates are reported: not the first (the path the monitor starts on), not an unchanged one, and only
/// a change to a path that is up.
struct NetworkPathChanges {
  private var last: NetworkPath?
  private var lastUp: NetworkPath?

  /// nil when `path` is not reported; otherwise whether its interfaces or gateways differ from the last path that
  /// was up (true when none was).
  mutating func next(_ path: NetworkPath) -> Bool? {
    let previous = last
    let previousUp = lastUp
    last = path
    if path.up { lastUp = path }
    guard let previous, previous != path, path.up else { return nil }
    return previousUp.map { $0.interfaces != path.interfaces || $0.gateways != path.gateways } ?? true
  }
}
