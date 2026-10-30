import BackgroundTasks
import Flutter
import UIKit

/// 离线缓存's host (lib/offline/ios/offline_api.g.dart): Pigeon's OfflineHostApi (OfflineApi.g.swift), the continued
/// processing task that keeps the app running after it leaves, and the background URLSessions that keep a download
/// going once it is suspended.
enum OfflineHost {
  /// Set once at registration; the sessions' and the continued task's callbacks reach Dart through it while Flutter
  /// runs.
  @MainActor static var events: OfflineEventApi?

  static func register(with messenger: FlutterBinaryMessenger) {
    let events = OfflineEventApi(binaryMessenger: messenger)
    MainActor.assumeIsolated { OfflineHost.events = events }
    OfflineHostApiSetup.setUp(binaryMessenger: messenger, api: OfflineHostApiImpl())
  }
}

/// Pigeon calls in on the main thread.
final class OfflineHostApiImpl: OfflineHostApi {
  func freeBytes() throws -> Int64? {
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage
  }

  func inBackground() throws -> Bool {
    MainActor.assumeIsolated { UIApplication.shared.applicationState == .background }
  }

  func excludeFromBackup(path: String) throws {
    var url = URL(fileURLWithPath: path, isDirectory: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  func beginGrace() throws {
    MainActor.assumeIsolated { OfflineGrace.shared.begin() }
  }

  func endGrace() throws {
    MainActor.assumeIsolated { OfflineGrace.shared.end() }
  }

  func handOff(ranges: [NativeBackgroundRange], connections: Int64) throws {
    OfflineTransfers.shared.handOff(ranges, connections: Int(connections))
  }

  func takeBack() async throws -> [NativeBackgroundRangeResult] {
    await OfflineTransfers.shared.takeBack()
  }

  func beginContinued(title: String, subtitle: String) throws -> String? {
    MainActor.assumeIsolated { ContinuedDownloads.shared.begin(title: title, subtitle: subtitle) }
  }

  func updateContinued(done: Int64, total: Int64, subtitle: String) throws {
    MainActor.assumeIsolated { ContinuedDownloads.shared.update(done: done, total: total, subtitle: subtitle) }
  }

  func endContinued(success: Bool) throws {
    MainActor.assumeIsolated { ContinuedDownloads.shared.end(success: success) }
  }
}

/// iOS 26's continued processing: asked for as the user starts downloads, the task keeps the app running after it
/// leaves, the engine downloading at full speed, under a Live Activity with the progress where the user can cancel it.
/// One at a time.
@MainActor final class ContinuedDownloads {
  static let shared = ContinuedDownloads()
  static let identifier = "com.kaichuan.bilifast.offline.continued"

  /// A request whose launch hasn't come by then no longer holds back a new one.
  private static let pendingLimit: TimeInterval = 10

  /// Registering an identifier twice raises, so the first answer is kept for the process.
  private var registered: Bool?
  private var task: BGContinuedProcessingTask?
  private var pendingSince: Date?
  /// Dart ended a request before it started: its launch, if it still comes, completes at once.
  private var withdrawn = false
  private var subtitle = ""

  private init() {}

  /// Nil when iOS took the request (or one is already running or on its way), else why not.
  func begin(title: String, subtitle: String) -> String? {
    if let task {
      task.updateTitle(title, subtitle: subtitle)
      self.subtitle = subtitle
      return nil
    }
    if let pendingSince, Date().timeIntervalSince(pendingSince) < Self.pendingLimit { return nil }
    guard register() else { return "not registered" }
    let request = BGContinuedProcessingTaskRequest(identifier: Self.identifier, title: title, subtitle: subtitle)
    request.strategy = .fail
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      let failure = error as NSError
      return "\(failure.domain) \(failure.code)"
    }
    // The launch handler runs on the main queue, so it comes only after this returns.
    pendingSince = Date()
    withdrawn = false
    self.subtitle = subtitle
    return nil
  }

  func update(done: Int64, total: Int64, subtitle: String) {
    guard let task else { return }
    let total = max(total, 1)
    task.progress.totalUnitCount = total
    task.progress.completedUnitCount = min(max(done, 0), total)
    if subtitle != self.subtitle {
      self.subtitle = subtitle
      task.updateTitle(task.title, subtitle: subtitle)
    }
  }

  func end(success: Bool) {
    if let task {
      self.task = nil
      task.setTaskCompleted(success: success)
    } else if pendingSince != nil {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
      pendingSince = nil
      withdrawn = true
    }
  }

  /// Continued processing handlers may be registered when the user asks for the work, not only at launch.
  private func register() -> Bool {
    if let registered { return registered }
    let done = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
      MainActor.assumeIsolated { ContinuedDownloads.shared.launched(task) }
    }
    registered = done
    return done
  }

  private func launched(_ given: BGTask) {
    pendingSince = nil
    guard let continued = given as? BGContinuedProcessingTask else {
      given.setTaskCompleted(success: false)
      return
    }
    if withdrawn || task != nil {
      withdrawn = false
      continued.setTaskCompleted(success: true)
      return
    }
    task = continued
    // Apple DTS: a bar whose progress never moved shows as indeterminate until the first update.
    continued.progress.totalUnitCount = 101
    continued.progress.completedUnitCount = 0
    continued.progress.completedUnitCount = 1
    let id = ObjectIdentifier(continued)
    // iOS may call it off the main thread.
    continued.expirationHandler = { @Sendable in
      DispatchQueue.main.async {
        MainActor.assumeIsolated { ContinuedDownloads.shared.expired(id) }
      }
    }
    Task { @MainActor in try? await OfflineHost.events?.onContinuedStarted() }
  }

  /// The time was up or the user cancelled it in the Live Activity; iOS doesn't say which.
  private func expired(_ id: ObjectIdentifier) {
    guard let task, ObjectIdentifier(task) == id else { return }
    // Without the task an app already away would be suspended before Dart hands its downloads to the sessions.
    if UIApplication.shared.applicationState != .active {
      OfflineGrace.shared.begin()
    }
    let locked = !UIApplication.shared.isProtectedDataAvailable
    self.task = nil
    Task { @MainActor in try? await OfflineHost.events?.onContinuedEnded(locked: locked) }
    task.setTaskCompleted(success: false)
  }
}

/// The time iOS gives after the app leaves the foreground (beginBackgroundTask). Dart hears onGraceEnding a few
/// seconds before it runs out, so the engine can stop and flush, and then ends it; the expiration handler is the
/// backstop, ending it at once so iOS never kills the app for overrunning.
@MainActor final class OfflineGrace {
  static let shared = OfflineGrace()

  private static let warning: TimeInterval = 8

  private var task: UIBackgroundTaskIdentifier = .invalid
  private var watch: Timer?
  private var warned = false

  private init() {}

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

/// The background sessions live as long as the app: iOS hands a session's events to a session of the same identifier,
/// which must exist by the time `handleEventsForBackgroundURLSession` arrives. Each range is one download task; a
/// finished one is written into its part file here, so it lands even while Flutter isn't running, and its result is
/// kept on disk until Dart takes it back.
final class OfflineTransfers: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  static let shared = OfflineTransfers()

  /// A session's connections per host are fixed by its configuration, so each count Dart tries has its own. 3 keeps
  /// the identifier older builds handed off on, so their transfers reattach.
  private static let sessions = [
    (identifier: "com.kaichuan.bilifast.offline", connections: 3),
    (identifier: "com.kaichuan.bilifast.offline.c2", connections: 2),
    (identifier: "com.kaichuan.bilifast.offline.c6", connections: 6),
  ]
  static let identifiers = sessions.map { $0.identifier }

  private static func identifier(connections: Int) -> String {
    sessions.first { $0.connections == connections }?.identifier ?? identifiers[0]
  }

  private static func connections(of identifier: String) -> Int {
    sessions.first { $0.identifier == identifier }?.connections ?? 3
  }

  /// Task identifiers are unique only within their session.
  private static func key(_ session: URLSession, _ task: URLSessionTask) -> String {
    "\(session.configuration.identifier ?? "")#\(task.taskIdentifier)"
  }

  /// Results kept for Dart at most; older ones drop off first.
  private static let maxResults = 4000

  /// A result's status besides the HTTP one: the part file couldn't be written (or was gone), or the answer wasn't
  /// the range asked for (its Content-Range or the track's total).
  private static let writeFailed = -2
  private static let wrongAnswer = -3

  /// A shorter answer than asked (the CDN capping a range): what came is written, the rest left to the engine.
  private static let shortAnswer = -4

  /// The part files, the `.bg-ranges` files and the results, one write at a time.
  private let queue = DispatchQueue(label: "com.kaichuan.bilifast.offline.transfers")
  private let lock = NSLock()
  private var made: [String: URLSession] = [:]

  /// On `queue`: the results not yet taken back (nil until read from disk), the tasks recorded in this run of the
  /// app (by `key`), and whether Dart took the sessions back since the last hand-off (every later callback is then
  /// ignored).
  private var results: [RecordedResult]?
  private var recorded = Set<String>()
  private var closed = false
  private var persistFailureLogged = false

  /// On the main thread, by session identifier. iOS may report a session's events done before it hands over the
  /// completion.
  private var completions: [String: () -> Void] = [:]
  private var eventsFinished = Set<String>()

  private func session(_ identifier: String) -> URLSession {
    lock.lock()
    defer { lock.unlock() }
    if let existing = made[identifier] { return existing }
    let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
    configuration.isDiscretionary = false
    configuration.sessionSendsLaunchEvents = true
    // Left to itself iOS ran ~30 ranges at once (1.3.0 (2)'s log), each crawling: in two minutes 62 MB finished and
    // 434 MB were thrown away unfinished on the return. A few at a time finish one after another.
    configuration.httpMaximumConnectionsPerHost = Self.connections(of: identifier)
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    made[identifier] = session
    return session
  }

  private var allSessions: [URLSession] {
    Self.identifiers.map { session($0) }
  }

  /// Called from didFinishLaunching, so a relaunch in the background reattaches to whichever has transfers.
  func resume() {
    _ = allSessions
  }

  /// iOS woke or relaunched the app for a session's events; [completion] runs once they are all handled.
  func handleEvents(identifier: String, completion: @escaping () -> Void) {
    resume()
    if eventsFinished.remove(identifier) != nil {
      completion()
    } else {
      // A second wake before the first one's events finished: the first is owed its call.
      completions[identifier]?()
      completions[identifier] = completion
    }
  }

  func handOff(_ ranges: [NativeBackgroundRange], connections: Int) {
    let identifier = Self.identifier(connections: connections)
    let session = self.session(identifier)
    queue.sync { closed = false }
    // A finish that came with no wake to answer belongs to transfers before these.
    DispatchQueue.main.async { _ = self.eventsFinished.remove(identifier) }
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

  /// Cancels every task still going (each reported as cancelled, status 0, with the bytes it had) and returns every
  /// result since the last call, those from while the app was closed included.
  func takeBack() async -> [NativeBackgroundRangeResult] {
    let sessions = allSessions
    var tasks = await Self.allTasks(sessions)
    var seen = tasks
    if tasks.values.contains(where: Self.isGoing) {
      // A range iOS finished while the app was suspended reaches the delegate only once the app is back, and until
      // then its task still reads as running: cancelled, its bytes would be thrown away. So the sessions get a moment
      // to deliver, then a few seconds more for any task whose bytes are all in.
      try? await Task.sleep(nanoseconds: Self.settle)
      tasks = await Self.allTasks(sessions)
      let deadline = Date().addingTimeInterval(Self.finishingWait)
      while Date() < deadline, tasks.values.contains(where: Self.isFinishing) {
        try? await Task.sleep(nanoseconds: 100_000_000)
        tasks = await Self.allTasks(sessions)
      }
      seen.merge(tasks) { _, last in last }
    }
    for task in tasks.values where Self.isGoing(task) {
      task.cancel()
    }
    // A range finishing as it is cancelled is still written: callbacks already queued for the delegate run before the
    // sessions close. Any later one is dropped unwritten, and its range reported cancelled.
    for session in sessions {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        session.delegateQueue.addOperation { continuation.resume() }
      }
    }
    return queue.sync {
      closed = true
      // Canceling and completed tasks whose callbacks come after the barrier are reported too.
      for (key, task) in seen where !recorded.contains(key) {
        recorded.insert(key)
        if let range = TransferRange.decode(task.taskDescription) {
          record(range, done: false, status: 0, received: task.countOfBytesReceived)
        }
      }
      let taken = loadResults()
      results = []
      persistResults()
      return taken.map(\.native)
    }
  }

  private static let settle: UInt64 = 1_000_000_000
  private static let finishingWait: TimeInterval = 3

  private static func isGoing(_ task: URLSessionTask) -> Bool {
    task.state == .running || task.state == .suspended
  }

  private static func isFinishing(_ task: URLSessionTask) -> Bool {
    task.state == .running && task.countOfBytesExpectedToReceive > 0
      && task.countOfBytesReceived >= task.countOfBytesExpectedToReceive
  }

  /// Every session's tasks, by `key`.
  private static func allTasks(_ sessions: [URLSession]) async -> [String: URLSessionTask] {
    var all: [String: URLSessionTask] = [:]
    for session in sessions {
      let tasks = await withCheckedContinuation { (continuation: CheckedContinuation<[URLSessionTask], Never>) in
        session.getAllTasks { continuation.resume(returning: $0) }
      }
      for task in tasks {
        all[key(session, task)] = task
      }
    }
    return all
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let range = TransferRange.decode(downloadTask.taskDescription) else { return }
    let response = downloadTask.response as? HTTPURLResponse
    let status = response?.statusCode ?? -1
    let id = Self.key(session, downloadTask)
    // Synchronously: iOS removes the file at `location` once this returns.
    queue.sync {
      guard !closed, !recorded.contains(id) else { return }
      recorded.insert(id)
      var done = false
      var outcome = status
      if status == 206 {
        // A part restarted at another size meanwhile must never take the old one's bytes.
        if let content = ContentRange(response?.value(forHTTPHeaderField: "Content-Range")),
           content.start == range.start, content.end <= range.end,
           let total = range.total, content.total == total {
          let written = write(location, into: range, end: content.end, total: total)
          done = written && content.end == range.end
          if !written {
            outcome = Self.writeFailed
          } else if !done {
            outcome = Self.shortAnswer
          }
        } else {
          outcome = Self.wrongAnswer
        }
      }
      send(record(range, done: done, status: outcome))
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error, let range = TransferRange.decode(task.taskDescription) else { return }
    let id = Self.key(session, task)
    let cancelled = (error as? URLError)?.code == .cancelled
    queue.sync {
      guard !closed, !recorded.contains(id) else { return }
      recorded.insert(id)
      send(record(range, done: false, status: cancelled ? 0 : -1, received: task.countOfBytesReceived))
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    guard let identifier = session.configuration.identifier else { return }
    DispatchQueue.main.async {
      guard let completion = self.completions.removeValue(forKey: identifier) else {
        self.eventsFinished.insert(identifier)
        return
      }
      completion()
    }
  }

  /// The range's bytes into its part file at their offset, then the range listed in its `.bg-ranges`. A missing part
  /// is never made: the part was finished, restarted or deleted meanwhile, and a new file would read as zeros where
  /// the engine's own ranges vouch for bytes.
  private func write(_ location: URL, into range: TransferRange, end: Int64, total: Int64) -> Bool {
    let manager = FileManager.default
    let part = range.partURL
    do {
      let size = (try manager.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? -1
      guard size == end - range.start + 1 else {
        NSLog("%@", "offline background write: \(size) bytes for a range of \(end - range.start + 1)")
        return false
      }
      guard manager.fileExists(atPath: part.path) else {
        NSLog("%@", "offline background write: part missing")
        return false
      }
      if let data = try? Data(contentsOf: range.backgroundRangesURL),
         let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let saved = (json["total"] as? NSNumber)?.int64Value, saved > 0, saved != total {
        NSLog("%@", "offline background write: listed ranges are for another size")
        return false
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
      try addDone(range.start, end, of: range, total: total)
      return true
    } catch {
      let failure = error as NSError
      NSLog("%@", "offline background write failed: \(failure.domain) \(failure.code)")
      return false
    }
  }

  /// `{"total": N, "done": [[start, end], ...]}`, sorted and merged as the engine keeps its `.ranges`.
  private func addDone(_ start: Int64, _ end: Int64, of range: TransferRange, total: Int64) throws {
    let url = range.backgroundRangesURL
    var done: [[Int64]] = [[start, end]]
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
  private func record(_ range: TransferRange, done: Bool, status: Int, received: Int64 = 0) -> RecordedResult {
    let result = RecordedResult(
      id: range.id,
      video: range.video,
      start: range.start,
      end: range.end,
      done: done,
      status: Int64(status),
      received: done ? 0 : received
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
      guard !persistFailureLogged else { return }
      persistFailureLogged = true
      let failure = error as NSError
      NSLog("%@", "offline transfer results not saved: \(failure.domain) \(failure.code)")
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

  /// The track's size; nil in a task handed off by an older build, whose answers are then refused.
  let total: Int64?

  init(_ range: NativeBackgroundRange) {
    id = range.id
    video = range.video
    partPath = Self.fromHome(range.partPath)
    backgroundRangesPath = Self.fromHome(range.backgroundRangesPath)
    start = range.start
    end = range.end
    total = range.total
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

  /// Nil in a result kept by an older build.
  let received: Int64?

  var native: NativeBackgroundRangeResult {
    NativeBackgroundRangeResult(
      id: id,
      video: video,
      start: start,
      end: end,
      done: done,
      status: status,
      received: received ?? 0
    )
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
