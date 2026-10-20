import Flutter
import Network

/// The phone's network path for the engine (port of PlaybackController.swift's NWPathMonitor), reported through
/// DeviceEventApi.onNetworkChanged: bans and backoffs earned on the old path would keep the engine off nodes that
/// work on the new one. The path's kind also feeds the status bar landscape full screen draws (StatusEvents).
@MainActor
enum NetworkMonitor {
  /// One for the app's life.
  private static var monitor: NWPathMonitor?
  private static var changes = NetworkPathChanges()
  private static var lastKind: NativeNetwork?

  /// Set while status events are on.
  static var kindChanged: (@MainActor () -> Void)?

  /// The kind of the last path reported, or of the monitor's current one before the first report.
  static var kind: NativeNetwork {
    if let lastKind { return lastKind }
    return monitor.map { NativeNetwork($0.currentPath) } ?? NativeNetwork.none
  }

  static func start() {
    guard monitor == nil else { return }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
      let now = NetworkPath(up: path.status == .satisfied, interfaces: path.availableInterfaces.map(\.name),
                            gateways: path.gateways.map { "\($0)" })
      let kind = NativeNetwork(path)
      MainActor.assumeIsolated { NetworkMonitor.pathUpdated(now, kind: kind) }
    }
    monitor.start(queue: .main)
    self.monitor = monitor
  }

  private static func pathUpdated(_ path: NetworkPath, kind: NativeNetwork) {
    if kind != lastKind {
      lastKind = kind
      kindChanged?()
    }
    guard let interfaceChanged = changes.next(path) else { return }
    Task { @MainActor in try? await DeviceChannel.events?.onNetworkChanged(interfaceChanged: interfaceChanged) }
  }
}

extension NativeNetwork {
  /// What the status bar shows for `path`. Anything else that is up (a wired adapter) shows as Wi-Fi, its other
  /// connected state.
  init(_ path: NWPath) {
    if path.status != .satisfied {
      self = .none
    } else if path.usesInterfaceType(.wifi) {
      self = .wifi
    } else if path.usesInterfaceType(.cellular) {
      self = .cellular
    } else if path.availableInterfaces.first(where: { $0.type == .wifi || $0.type == .cellular })?.type == .cellular {
      // A VPN's path can use only its tunnel; the first real interface in the list is the one under it.
      self = .cellular
    } else {
      self = .wifi
    }
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
