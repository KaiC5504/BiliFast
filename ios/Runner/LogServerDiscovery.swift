import Flutter
import Foundation
import Network

/// Finds the PC's log server (`uv run tools/logserver.py` in BiliNative) over Bonjour for Dart's
/// LogServerDiscovery. Dart's sink speaks plain HTTP, so each service is resolved to an address and port by a
/// short connection. Every change sends the whole list; everything runs on the main queue.
final class LogServerDiscovery: NSObject, FlutterStreamHandler {
  private static let serviceType = "_bilinative-log._tcp"

  private var browser: NWBrowser?
  private var sink: FlutterEventSink?
  private var resolving: [String: NWConnection] = [:]
  private var found: [String: [String: Any]] = [:]

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterEventChannel(name: "bilifast/log_servers", binaryMessenger: messenger)
    channel.setStreamHandler(LogServerDiscovery())
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    start()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stop()
    sink = nil
    return nil
  }

  private func start() {
    guard browser == nil else { return }
    let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      self?.update(results)
    }
    browser.start(queue: .main)
    self.browser = browser
    publish()
  }

  private func stop() {
    browser?.cancel()
    browser = nil
    resolving.values.forEach { $0.cancel() }
    resolving = [:]
    found = [:]
  }

  private func update(_ results: Set<NWBrowser.Result>) {
    var names = Set<String>()
    for result in results {
      guard case .service(let name, _, _, _) = result.endpoint else { continue }
      names.insert(name)
      if found[name] == nil, resolving[name] == nil { resolve(name, endpoint: result.endpoint) }
    }
    for name in Array(resolving.keys) where !names.contains(name) {
      resolving.removeValue(forKey: name)?.cancel()
    }
    let count = found.count
    found = found.filter { names.contains($0.key) }
    if found.count != count { publish() }
  }

  private func resolve(_ name: String, endpoint: NWEndpoint) {
    let parameters = NWParameters.tcp
    // logserver.py advertises IPv4 addresses only, and a link-local IPv6 one would need a zone in the URL.
    if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
      ip.version = .v4
    }
    let connection = NWConnection(to: endpoint, using: parameters)
    resolving[name] = connection
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection else { return }
      self.connection(connection, named: name, changedTo: state)
    }
    connection.start(queue: .main)
  }

  private func connection(_ connection: NWConnection, named name: String, changedTo state: NWConnection.State) {
    switch state {
    case .ready:
      if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
        found[name] = ["name": name, "host": Self.address(host), "port": Int(port.rawValue)]
        publish()
      }
      finish(connection, named: name)
    case .failed, .cancelled:
      finish(connection, named: name)
    default:
      break
    }
  }

  private func finish(_ connection: NWConnection, named name: String) {
    if resolving[name] === connection { resolving[name] = nil }
    connection.cancel()
  }

  private func publish() {
    sink?(found.keys.sorted().compactMap { found[$0] })
  }

  private static func address(_ host: NWEndpoint.Host) -> String {
    switch host {
    case .ipv4(let address):
      return address.rawValue.map { String($0) }.joined(separator: ".")
    case .ipv6(let address):
      return "\(address)"
    case .name(let name, _):
      return name
    @unknown default:
      return "\(host)"
    }
  }
}
