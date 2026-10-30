import Flutter
import UIKit

/// 离线缓存's host (lib/offline/ios/offline_api.g.dart): Pigeon's OfflineHostApi (OfflineApi.g.swift) and the
/// background URLSession that keeps a download going after the app leaves the foreground.
enum OfflineHost {
  /// Set once at registration; the session's callbacks reach Dart through it while Flutter runs.
  @MainActor static var events: OfflineEventApi?

  static func register(with messenger: FlutterBinaryMessenger) {
    let events = OfflineEventApi(binaryMessenger: messenger)
    MainActor.assumeIsolated { OfflineHost.events = events }
    OfflineHostApiSetup.setUp(binaryMessenger: messenger, api: OfflineHostApiImpl())
  }
}

/// Pigeon calls in on the main thread.
final class OfflineHostApiImpl: OfflineHostApi {
  private let grace = MainActor.assumeIsolated { OfflineGrace() }

  func freeBytes() throws -> Int64? {
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage
  }

  func excludeFromBackup(path: String) throws {
    var url = URL(fileURLWithPath: path, isDirectory: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  func beginGrace() throws {
    let grace = self.grace
    MainActor.assumeIsolated { grace.begin() }
  }

  func endGrace() throws {
    let grace = self.grace
    MainActor.assumeIsolated { grace.end() }
  }

  func handOff(ranges: [NativeBackgroundRange]) throws {
    OfflineTransfers.shared.handOff(ranges)
  }

  func takeBack() async throws -> [NativeBackgroundRangeResult] {
    await OfflineTransfers.shared.takeBack()
  }
}

/// The time iOS gives after the app leaves the foreground (beginBackgroundTask). Dart hears onGraceEnding a few
/// seconds before it runs out, so the engine can stop and flush, and then ends it; the expiration handler is the
/// backstop, ending it at once so iOS never kills the app for overrunning.
@MainActor final class OfflineGrace {
  private static let warning: TimeInterval = 8

  private var task: UIBackgroundTaskIdentifier = .invalid
  private var watch: Timer?
  private var warned = false

  func begin() {
    guard task == .invalid else { return }
    warned = false
    task = UIApplication.shared.beginBackgroundTask(withName: "offline") { [weak self] in
      MainActor.assumeIsolated {
        self?.warn()
        self?.end()
      }
    }
    guard task != .invalid else { return }
    watch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.check() }
    }
  }

  func end() {
    watch?.invalidate()
    watch = nil
    guard task != .invalid else { return }
    UIApplication.shared.endBackgroundTask(task)
    task = .invalid
  }

  private func check() {
    // greatestFiniteMagnitude while the app is still in the foreground.
    if UIApplication.shared.backgroundTimeRemaining < Self.warning { warn() }
  }

  private func warn() {
    guard !warned, task != .invalid else { return }
    warned = true
    Task { @MainActor in try? await OfflineHost.events?.onGraceEnding() }
  }
}

/// The background session lives as long as the app: iOS hands its events to a session of the same identifier, which
/// must exist by the time `handleEventsForBackgroundURLSession` arrives. Each range is one download task; a finished
/// one is written into its part file here, so it lands even while Flutter isn't running, and its result is kept on
/// disk until Dart takes it back.
final class OfflineTransfers: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  static let shared = OfflineTransfers()
  static let identifier = "com.kaichuan.bilifast.offline"

  /// Results kept for Dart at most; older ones drop off first.
  private static let maxResults = 4000

  /// The part files, the `.bg-ranges` files and the results, one write at a time.
  private let queue = DispatchQueue(label: "com.kaichuan.bilifast.offline.transfers")
  private let lock = NSLock()
  private var made: URLSession?

  /// On `queue`: the results not yet taken back (nil until read from disk), and the tasks recorded or taken back in
  /// this run of the app, whose later callbacks are ignored.
  private var results: [RecordedResult]?
  private var recorded = Set<Int>()
  private var takenBack = Set<Int>()

  /// On the main thread.
  private var completion: (() -> Void)?

  private var session: URLSession {
    lock.lock()
    defer { lock.unlock() }
    if let made { return made }
    let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
    configuration.isDiscretionary = false
    configuration.sessionSendsLaunchEvents = true
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    made = session
    return session
  }

  /// Called from didFinishLaunching, so a relaunch in the background reattaches to its transfers.
  func resume() {
    _ = session
  }

  /// iOS woke or relaunched the app for the session's events; [completion] runs once they are all handled.
  func handleEvents(identifier: String, completion: @escaping () -> Void) {
    self.completion = completion
    resume()
  }

  func handOff(_ ranges: [NativeBackgroundRange]) {
    let session = self.session
    for range in ranges {
      guard let url = URL(string: range.url), let description = TransferRange(range).encoded() else { continue }
      var request = URLRequest(url: url)
      for (name, value) in range.headers {
        request.setValue(value, forHTTPHeaderField: name)
      }
      request.setValue("bytes=\(range.start)-\(range.end)", forHTTPHeaderField: "Range")
      let task = session.downloadTask(with: request)
      // The range itself rides on the task, so it survives the app being closed.
      task.taskDescription = description
      task.resume()
    }
  }

  /// Cancels every task still going (each reported as cancelled, status 0) and returns every result since the last
  /// call, those from while the app was closed included.
  func takeBack() async -> [NativeBackgroundRangeResult] {
    let session = self.session
    let tasks = await withCheckedContinuation { (continuation: CheckedContinuation<[URLSessionTask], Never>) in
      session.getAllTasks { continuation.resume(returning: $0) }
    }
    let going = tasks.filter { $0.state == .running || $0.state == .suspended }
    queue.sync {
      for task in going where !recorded.contains(task.taskIdentifier) {
        takenBack.insert(task.taskIdentifier)
        if let range = TransferRange.decode(task.taskDescription) {
          record(range, done: false, status: 0)
        }
      }
    }
    for task in going {
      task.cancel()
    }
    // Callbacks already queued for the delegate are handled before the results are read.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      session.delegateQueue.addOperation { continuation.resume() }
    }
    return queue.sync {
      let taken = loadResults()
      results = []
      persistResults()
      return taken.map(\.native)
    }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let range = TransferRange.decode(downloadTask.taskDescription) else { return }
    let response = downloadTask.response as? HTTPURLResponse
    let status = response?.statusCode ?? -1
    let id = downloadTask.taskIdentifier
    // Synchronously: iOS removes the file at `location` once this returns.
    queue.sync {
      guard !takenBack.contains(id) else { return }
      recorded.insert(id)
      var done = false
      if status == 206, let content = ContentRange(response?.value(forHTTPHeaderField: "Content-Range")),
         content.start == range.start, content.end == range.end {
        done = write(location, into: range, total: content.total)
      }
      send(record(range, done: done, status: status))
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error, let range = TransferRange.decode(task.taskDescription) else { return }
    let id = task.taskIdentifier
    let cancelled = (error as? URLError)?.code == .cancelled
    queue.sync {
      guard !takenBack.contains(id), !recorded.contains(id) else { return }
      recorded.insert(id)
      send(record(range, done: false, status: cancelled ? 0 : -1))
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      let completion = self.completion
      self.completion = nil
      completion?()
    }
  }

  /// The range's bytes into its part file at their offset (the file made if it isn't there, never its folder: a part
  /// deleted meanwhile stays deleted), then the range listed in its `.bg-ranges`.
  private func write(_ location: URL, into range: TransferRange, total: Int64) -> Bool {
    let manager = FileManager.default
    let part = range.partURL
    do {
      let size = (try manager.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? -1
      guard size == range.end - range.start + 1 else { return false }
      if !manager.fileExists(atPath: part.path) {
        // Finished by the engine meanwhile: nothing to add, and no stray part file beside it.
        guard !manager.fileExists(atPath: part.deletingPathExtension().path),
              manager.createFile(atPath: part.path, contents: nil) else { return false }
      }
      let input = try FileHandle(forReadingFrom: location)
      defer { try? input.close() }
      let output = try FileHandle(forWritingTo: part)
      defer { try? output.close() }
      try output.seek(toOffset: UInt64(range.start))
      while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
        try output.write(contentsOf: chunk)
      }
      try output.synchronize()
      try addDone(range, total: total)
      return true
    } catch {
      return false
    }
  }

  /// `{"total": N, "done": [[start, end], ...]}`, sorted and merged as the engine keeps its `.ranges`.
  private func addDone(_ range: TransferRange, total: Int64) throws {
    let url = range.backgroundRangesURL
    var done: [[Int64]] = [[range.start, range.end]]
    var known = total
    if let data = try? Data(contentsOf: url),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      if let pairs = json["done"] as? [[NSNumber]] {
        done += pairs.compactMap { $0.count == 2 ? [$0[0].int64Value, $0[1].int64Value] : nil }
      }
      if known <= 0, let saved = (json["total"] as? NSNumber)?.int64Value {
        known = saved
      }
    }
    let json: [String: Any] = ["total": known, "done": Self.merge(done)]
    try JSONSerialization.data(withJSONObject: json).write(to: url, options: .atomic)
  }

  static func merge(_ ranges: [[Int64]]) -> [[Int64]] {
    var merged: [[Int64]] = []
    for range in ranges.sorted(by: { $0[0] < $1[0] }) {
      if let last = merged.last, range[0] <= last[1] + 1 {
        merged[merged.count - 1][1] = max(last[1], range[1])
      } else {
        merged.append(range)
      }
    }
    return merged
  }

  @discardableResult
  private func record(_ range: TransferRange, done: Bool, status: Int) -> RecordedResult {
    let result = RecordedResult(
      id: range.id,
      video: range.video,
      start: range.start,
      end: range.end,
      done: done,
      status: Int64(status)
    )
    var all = loadResults()
    all.append(result)
    if all.count > Self.maxResults {
      all.removeFirst(all.count - Self.maxResults)
    }
    results = all
    persistResults()
    return result
  }

  private func send(_ result: RecordedResult) {
    let native = result.native
    Task { @MainActor in try? await OfflineHost.events?.onRangeFinished(result: native) }
  }

  private lazy var resultsURL: URL = {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    return support.appendingPathComponent("offline-transfers.json")
  }()

  private func loadResults() -> [RecordedResult] {
    if let results { return results }
    let loaded = (try? Data(contentsOf: resultsURL)).flatMap { try? JSONDecoder().decode([RecordedResult].self, from: $0) }
    results = loaded ?? []
    return results ?? []
  }

  private func persistResults() {
    do {
      try FileManager.default.createDirectory(
        at: resultsURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try JSONEncoder().encode(results ?? []).write(to: resultsURL, options: .atomic)
    } catch {
      // Only the report is lost; what was written is in the part files and their `.bg-ranges`.
    }
  }
}

/// A range as its task's description keeps it. Paths inside the app's container are kept from its home folder, which
/// moves with every update of the app.
private struct TransferRange: Codable {
  let id: String
  let video: Bool
  let partPath: String
  let backgroundRangesPath: String
  let start: Int64
  let end: Int64

  init(_ range: NativeBackgroundRange) {
    id = range.id
    video = range.video
    partPath = Self.fromHome(range.partPath)
    backgroundRangesPath = Self.fromHome(range.backgroundRangesPath)
    start = range.start
    end = range.end
  }

  var partURL: URL { URL(fileURLWithPath: Self.inHome(partPath)) }
  var backgroundRangesURL: URL { URL(fileURLWithPath: Self.inHome(backgroundRangesPath)) }

  func encoded() -> String? {
    (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
  }

  static func decode(_ text: String?) -> TransferRange? {
    guard let data = text?.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(TransferRange.self, from: data)
  }

  private static let homeMark = "~/"

  private static func fromHome(_ path: String) -> String {
    let home = NSHomeDirectory() + "/"
    return path.hasPrefix(home) ? homeMark + String(path.dropFirst(home.count)) : path
  }

  private static func inHome(_ path: String) -> String {
    path.hasPrefix(homeMark) ? NSHomeDirectory() + "/" + String(path.dropFirst(homeMark.count)) : path
  }
}

private struct RecordedResult: Codable {
  let id: String
  let video: Bool
  let start: Int64
  let end: Int64
  let done: Bool
  let status: Int64

  var native: NativeBackgroundRangeResult {
    NativeBackgroundRangeResult(id: id, video: video, start: start, end: end, done: done, status: status)
  }
}

/// `bytes <start>-<end>/<total>`; the total is required, as the engine's `.ranges` need it.
private struct ContentRange {
  let start: Int64
  let end: Int64
  let total: Int64

  init?(_ header: String?) {
    guard let header, header.hasPrefix("bytes ") else { return nil }
    let spec = header.dropFirst("bytes ".count)
    let halves = spec.split(separator: "/", maxSplits: 1)
    guard halves.count == 2, let total = Int64(halves[1]) else { return nil }
    let bounds = halves[0].split(separator: "-", maxSplits: 1)
    guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]), start <= end else { return nil }
    self.start = start
    self.end = end
    self.total = total
  }
}
