import BackgroundTasks
import CryptoKit
import Flutter
import UIKit
import UserNotifications

/// 推送设置's notifications without a server: iOS's app refresh wakes the app now and then, the check asks Bilibili's
/// unread counts with the keychain's login, and anything new is posted as a local notification. It runs natively
/// because a background launch may bring up no Flutter engine at all. Ids, names and comment text never reach a log.
final class NotifyHost: NotifyHostApi {
  static let shared = NotifyHost()
  static let refreshIdentifier = "com.kaichuan.bilifast.notify.refresh"

  /// UNUserNotificationCenter holds its delegate weakly.
  private let taps = NotifyTapDelegate()

  static func register(with messenger: FlutterBinaryMessenger) {
    let events = NotifyEventApi(binaryMessenger: messenger)
    MainActor.assumeIsolated { NotifyTaps.events = events }
    NotifyHostApiSetup.setUp(binaryMessenger: messenger, api: shared)
  }

  /// From didFinishLaunching: BGTaskScheduler takes handlers only before launch ends, and a tap that launched the
  /// app reaches the delegate set here.
  func launch() {
    UNUserNotificationCenter.current().delegate = taps
    MainActor.assumeIsolated { NotifyRefresh.shared.launch() }
  }

  func kinds() throws -> NativeNotifyKinds {
    NotifyStore.kinds()
  }

  func setKinds(kinds: NativeNotifyKinds) throws {
    MainActor.assumeIsolated {
      NotifyStore.setKinds(kinds)
      NotifyRefresh.shared.reschedule()
    }
  }

  func permission() async throws -> NativeNotifyPermission {
    switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
    case .notDetermined: .notDetermined
    case .authorized, .provisional, .ephemeral: .allowed
    default: .denied
    }
  }

  func requestPermission() async throws -> Bool {
    do {
      return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    } catch {
      // Only the domain and code reach Dart, never the error's localized text.
      let failure = error as NSError
      throw NotifyApiError(code: "notifications", message: "\(failure.domain) \(failure.code)", details: nil)
    }
  }

  func takeLaunchRoute() throws -> NativeNotifyRoute? {
    MainActor.assumeIsolated { NotifyTaps.take() }
  }

  func takeTrips() throws -> [NativeNotifyTrip] {
    MainActor.assumeIsolated { NotifyStore.takeTrips() }
  }
}

enum NotifyKind: String, CaseIterable {
  case replies, mentions, likes, messages, uploads
}

extension NativeNotifyKinds {
  func isOn(_ kind: NotifyKind) -> Bool {
    switch kind {
    case .replies: replies
    case .mentions: mentions
    case .likes: likes
    case .messages: messages
    case .uploads: uploads
    }
  }

  var any: Bool { NotifyKind.allCases.contains(where: isOn) }
}

extension NativeNotifyRoute {
  static let app = NativeNotifyRoute(target: .app, toComments: false)
}

/// iOS's app refresh: one request pending while any switch is on, each launch one check. earliestBeginDate is only a
/// floor; iOS picks the time from how the app is used.
@MainActor final class NotifyRefresh {
  static let shared = NotifyRefresh()

  private static let interval: TimeInterval = 15 * 60

  /// A launch for an identifier without a handler raises, so nothing is submitted unless registering took.
  private var registered = false
  private var background: NSObjectProtocol?
  private var current: Run?

  private struct Run {
    let task: BGTask
    let work: Task<NotifyResult, Never>
    let calls: NotifyCalls
    let started: Date
  }

  private init() {}

  func launch() {
    guard background == nil else { return }
    let identifier = NotifyHost.refreshIdentifier
    registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
      MainActor.assumeIsolated { NotifyRefresh.shared.start(task) }
    }
    background = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                        object: nil, queue: .main) { _ in
      MainActor.assumeIsolated { NotifyRefresh.shared.reschedule() }
    }
  }

  /// Submitting again replaces the pending request, so its floor moves to 15 minutes from now.
  func reschedule() {
    guard registered else { return }
    guard NotifyStore.kinds().any else {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: NotifyHost.refreshIdentifier)
      return
    }
    let request = BGAppRefreshTaskRequest(identifier: NotifyHost.refreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: Self.interval)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      let failure = error as NSError
      NSLog("%@", "notify refresh not scheduled: \(failure.domain) \(failure.code)")
    }
  }

  private func start(_ given: BGTask) {
    guard current == nil else {
      given.setTaskCompleted(success: false)
      return
    }
    let calls = NotifyCalls()
    let work = Task.detached { await NotifyCheck(calls: calls).run() }
    current = Run(task: given, work: work, calls: calls, started: Date())
    let id = ObjectIdentifier(given)
    // iOS may call it off the main thread. Cancelling the check cancels its request in flight; it then neither saves
    // nor posts anything.
    given.expirationHandler = { @Sendable in
      work.cancel()
      DispatchQueue.main.async {
        MainActor.assumeIsolated { NotifyRefresh.shared.finish(id, .outOfTime) }
      }
    }
    Task { @MainActor in
      let result = await work.value
      NotifyRefresh.shared.finish(id, result)
    }
  }

  private func finish(_ id: ObjectIdentifier, _ result: NotifyResult) {
    guard let run = current, ObjectIdentifier(run.task) == id else { return }
    current = nil
    let calls = run.calls.value
    NotifyStore.record(NativeNotifyTrip(atMs: Int64(run.started.timeIntervalSince1970 * 1000), outcome: result.outcome,
                                        calls: Int64(calls), posted: Int64(result.posted)))
    NSLog("%@", "notify check: \(result.outcome), \(calls) calls, \(result.posted) posted")
    reschedule()
    run.task.setTaskCompleted(success: !result.outcome.hasPrefix("failed"))
  }
}

/// Taps reach Dart once it has asked for the launch's route (it does at start); until then only the latest is kept.
@MainActor enum NotifyTaps {
  static var events: NotifyEventApi?

  private static var dartReady = false
  private static var pending: NativeNotifyRoute?

  static func tapped(_ route: NativeNotifyRoute) {
    guard dartReady, events != nil else {
      pending = route
      return
    }
    Task { @MainActor in try? await NotifyTaps.events?.onTap(route: route) }
  }

  static func take() -> NativeNotifyRoute? {
    dartReady = true
    defer { pending = nil }
    return pending
  }
}

/// Every notification the app posts comes through here, the sideload reminder's (DeviceChannel.swift) too; that one
/// carries no route and only opens the app. iOS may call in on any thread.
final class NotifyTapDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions)
                                -> Void) {
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
       let route = NotifyRoutes.route(response.notification.request.content.userInfo) {
      Task { @MainActor in NotifyTaps.tapped(route) }
    }
    completionHandler()
  }
}

/// The switches, the check's cursors and its trips, in UserDefaults: like the keychain's login, readable in the
/// background once the phone has been unlocked since it started. Writes that race a check (setKinds, the check's
/// save) happen on the main actor.
enum NotifyStore {
  private static let kindsKey = "notify.kinds"
  private static let stateKey = "notify.state"
  private static let tripsKey = "notify.trips"
  private static let riskKey = "notify.riskUntil"
  private static let maxTrips = 50
  private static let riskPause: TimeInterval = 6 * 60 * 60

  static func kinds() -> NativeNotifyKinds {
    let saved = UserDefaults.standard.dictionary(forKey: kindsKey) ?? [:]
    func on(_ kind: NotifyKind) -> Bool { saved[kind.rawValue] as? Bool ?? false }
    return NativeNotifyKinds(replies: on(.replies), mentions: on(.mentions), likes: on(.likes),
                             messages: on(.messages), uploads: on(.uploads))
  }

  /// A switch turned off loses its cursor, so turning it on again seeds afresh and never brings back what came while
  /// it was off.
  @MainActor static func setKinds(_ kinds: NativeNotifyKinds) {
    let saved = Dictionary(uniqueKeysWithValues: NotifyKind.allCases.map { ($0.rawValue, kinds.isOn($0)) })
    UserDefaults.standard.set(saved, forKey: kindsKey)
    save(pruned(state(), to: kinds))
  }

  static func state() -> NotifyState {
    guard let data = UserDefaults.standard.data(forKey: stateKey),
          let state = try? JSONDecoder().decode(NotifyState.self, from: data) else { return NotifyState(account: "") }
    return state
  }

  /// A check's cursors, less those of switches turned off while it ran; nil (nothing kept) once it is out of time.
  /// Returns the switches as they are now, which decide what it may still post.
  @MainActor static func keep(_ state: NotifyState) -> NativeNotifyKinds? {
    guard !Task.isCancelled else { return nil }
    let now = kinds()
    save(pruned(state, to: now))
    return now
  }

  private static func pruned(_ state: NotifyState, to kinds: NativeNotifyKinds) -> NotifyState {
    var kept = state
    kept.cursors = state.cursors.filter { key, _ in NotifyKind(rawValue: key).map(kinds.isOn) ?? false }
    return kept
  }

  private static func save(_ state: NotifyState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    UserDefaults.standard.set(data, forKey: stateKey)
  }

  /// The mid itself is never kept; the cursors only need to know the account changed.
  static func account(_ mid: String) -> String {
    SHA256.hash(data: Data(mid.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
  }

  static func riskHeld() -> Bool {
    Date().timeIntervalSince1970 < UserDefaults.standard.double(forKey: riskKey)
  }

  static func holdForRisk() {
    UserDefaults.standard.set(Date().timeIntervalSince1970 + riskPause, forKey: riskKey)
  }

  @MainActor static func record(_ trip: NativeNotifyTrip) {
    var trips = UserDefaults.standard.array(forKey: tripsKey) as? [[String: Any]] ?? []
    trips.append(["atMs": trip.atMs, "outcome": trip.outcome, "calls": trip.calls, "posted": trip.posted])
    UserDefaults.standard.set(Array(trips.suffix(maxTrips)), forKey: tripsKey)
  }

  @MainActor static func takeTrips() -> [NativeNotifyTrip] {
    let trips = UserDefaults.standard.array(forKey: tripsKey) as? [[String: Any]] ?? []
    UserDefaults.standard.removeObject(forKey: tripsKey)
    return trips.compactMap { entry in
      guard let atMs = NotifyJSON.int(entry["atMs"]), let outcome = entry["outcome"] as? String else { return nil }
      return NativeNotifyTrip(atMs: atMs, outcome: outcome, calls: NotifyJSON.int(entry["calls"]) ?? 0,
                              posted: NotifyJSON.int(entry["posted"]) ?? 0)
    }
  }
}

/// One account's cursors, by NotifyKind's raw value; another account's login starts over.
struct NotifyState: Codable {
  var account: String
  var cursors: [String: NotifyCursor] = [:]
}

struct NotifyCursor: Codable {
  /// The newest item's time seen (unix seconds); a seed's is when it was made, so only later items count.
  var time: Int64
  /// The items seen at `time`: another one in the same second is still new.
  var keys: [String] = []
  /// The unread count as last seen (回复, @, 赞, 私信).
  var count: Int64 = 0
  /// 关注的UP主投稿: the video feed's update_baseline, the newest card it showed.
  var baseline: String?

  /// The items past the cursor, oldest first, with the cursor moved to the newest.
  mutating func take(_ items: [NotifyItem]) -> [NotifyItem] {
    var seen = Set<String>()
    let fresh = items
      .filter { ($0.time > time || ($0.time == time && !keys.contains($0.key))) && seen.insert($0.key).inserted }
      .sorted { $0.time < $1.time }
    guard let newest = fresh.last?.time else { return fresh }
    if newest > time {
      time = newest
      keys = []
    }
    keys += fresh.filter { $0.time == newest }.map(\.key)
    return fresh
  }
}

/// How a check ended, for its trip.
struct NotifyResult: Sendable {
  let outcome: String
  let posted: Int

  static let outOfTime = NotifyResult(outcome: "failed out of time", posted: 0)
}

/// The calls a check made, read by the expiration handler from another thread.
final class NotifyCalls: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  func add() { lock.withLock { count += 1 } }

  var value: Int { lock.withLock { count } }
}

/// One background check: the unread counts first, then only the lists whose count moved, so a quiet run costs one
/// to three calls and a busy one at most seven (3 counts, 3 lists, the video feed). Nothing is retried; the next run
/// asks again. A kind's first run after it is turned on (or under a new account) only seeds its cursor.
final class NotifyCheck {
  private static let perKind = 5

  private let calls: NotifyCalls
  private var state = NotifyState(account: "")
  private var found: [NotifyPost] = []
  private var seeded = false

  init(calls: NotifyCalls) {
    self.calls = calls
  }

  func run() async -> NotifyResult {
    let kinds = NotifyStore.kinds()
    guard kinds.any else { return NotifyResult(outcome: "all off", posted: 0) }
    guard !NotifyStore.riskHeld() else { return NotifyResult(outcome: "failed risk hold", posted: 0) }
    let allowed: [UNAuthorizationStatus] = [.authorized, .provisional, .ephemeral]
    guard allowed.contains(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus) else {
      return NotifyResult(outcome: "not allowed", posted: 0)
    }
    guard let cookies = KeychainChannel.storedCookies() else {
      return NotifyResult(outcome: "failed keychain", posted: 0)
    }
    guard cookies["SESSDATA"]?.isEmpty == false, let mid = cookies["DedeUserID"], !mid.isEmpty else {
      return NotifyResult(outcome: "logged out", posted: 0)
    }
    let account = NotifyStore.account(mid)
    state = NotifyStore.state()
    if state.account != account { state = NotifyState(account: account) }

    let web = NotifyWeb(cookies: cookies, calls: calls)
    defer { web.close() }
    var failure: NotifyFailure?
    do {
      try await checkComments(kinds, web)
      if kinds.messages { try await checkMessages(web) }
      if kinds.uploads { try await checkUploads(web) }
    } catch let stopped as NotifyFailure {
      failure = stopped
    } catch {
      failure = .decode
    }
    switch failure {
    case .expired?:
      return NotifyResult(outcome: "expired", posted: 0)
    case .risk?:
      NotifyStore.holdForRisk()
      return NotifyResult(outcome: "failed risk", posted: 0)
    case .cancelled?:
      return .outOfTime
    default:
      break
    }

    // Any other failure keeps what the kinds before it found: each cursor moved only once its own calls answered.
    let state = self.state
    guard let kindsNow = await MainActor.run(body: { NotifyStore.keep(state) }) else { return .outOfTime }
    let posts = found.filter { kindsNow.isOn($0.kind) }
    let posted = await Self.post(posts)
    if let failure { return NotifyResult(outcome: "failed \(failure.reason)", posted: posted) }
    if posted > 0 { return NotifyResult(outcome: "posted", posted: posted) }
    if !posts.isEmpty { return NotifyResult(outcome: "failed post", posted: 0) }
    return NotifyResult(outcome: seeded ? "seeded" : "nothing new", posted: 0)
  }

  private static var now: Int64 { Int64(Date().timeIntervalSince1970) }

  private func seed(_ kind: NotifyKind, _ cursor: NotifyCursor) {
    state.cursors[kind.rawValue] = cursor
    seeded = true
  }

  /// 回复我的, @我的 and 收到的赞 share one count call.
  private func checkComments(_ kinds: NativeNotifyKinds, _ web: NotifyWeb) async throws {
    let wanted = [NotifyKind.replies, .mentions, .likes].filter(kinds.isOn)
    guard !wanted.isEmpty else { return }
    let unread = try await web.get("https://api.bilibili.com/x/msgfeed/unread", ["build": "0", "mobi_app": "web"])
    for kind in wanted {
      let count: Int64 = switch kind {
      case .mentions: NotifyJSON.int(unread["at"]) ?? 0
      case .likes: NotifyJSON.int(unread["recv_like"]) ?? NotifyJSON.int(unread["like"]) ?? 0
      default: NotifyJSON.int(unread["reply"]) ?? 0
      }
      guard var cursor = state.cursors[kind.rawValue] else {
        seed(kind, NotifyCursor(time: Self.now, count: count))
        continue
      }
      guard count > 0, count != cursor.count else {
        cursor.count = count
        state.cursors[kind.rawValue] = cursor
        continue
      }
      let items = try await list(kind, web)
      let fresh = cursor.take(items)
      // Reading the list may clear the count on Bilibili's side, so the next new item can bring it back to the
      // same number; remembering 0 makes that one count as moved.
      cursor.count = 0
      state.cursors[kind.rawValue] = cursor
      plan(kind, fresh)
    }
  }

  private func list(_ kind: NotifyKind, _ web: NotifyWeb) async throws -> [NotifyItem] {
    let query: KeyValuePairs = ["platform": "web", "build": "0", "mobi_app": "web"]
    switch kind {
    case .replies:
      let data = try await web.get("https://api.bilibili.com/x/msgfeed/reply", query)
      return NotifyJSON.objects(data["items"]).compactMap { NotifyItems.comment($0, kind: .replies, at: "reply_time") }
    case .mentions:
      let data = try await web.get("https://api.bilibili.com/x/msgfeed/at", query)
      return NotifyJSON.objects(data["items"]).compactMap { NotifyItems.comment($0, kind: .mentions, at: "at_time") }
    case .likes:
      // `latest` holds the newest, `total` the rest; one item may be in both.
      let data = try await web.get("https://api.bilibili.com/x/msgfeed/like", query)
      let latest = NotifyJSON.objects((data["latest"] as? [String: Any])?["items"])
      let total = NotifyJSON.objects((data["total"] as? [String: Any])?["items"])
      return (latest + total).compactMap(NotifyItems.like)
    case .messages, .uploads:
      return []
    }
  }

  /// Counts only: no message is fetched, so 私信's text never reaches the phone through here.
  private func checkMessages(_ web: NotifyWeb) async throws {
    let data = try await web.get("https://api.vc.bilibili.com/session_svr/v1/session_svr/single_unread",
                                 ["unread_type": "0", "show_dustbin": "0", "build": "0", "mobi_app": "web"])
    let count = (NotifyJSON.int(data["follow_unread"]) ?? 0) + (NotifyJSON.int(data["unfollow_unread"]) ?? 0)
    guard var cursor = state.cursors[NotifyKind.messages.rawValue] else {
      return seed(.messages, NotifyCursor(time: Self.now, count: count))
    }
    if count > cursor.count { found.append(NotifyWording.messages(count)) }
    cursor.count = count
    state.cursors[NotifyKind.messages.rawValue] = cursor
  }

  /// The polymer feed's update count against the last page's baseline; the first page of 视频 only when it says
  /// there is something. Neither call is WBI-signed (bili_core's dynamicFeed isn't either).
  private func checkUploads(_ web: NotifyWeb) async throws {
    let key = NotifyKind.uploads.rawValue
    if let baseline = state.cursors[key]?.baseline {
      let update = try await web.get("https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all/update",
                                     ["type": "video", "update_baseline": baseline, "web_location": "333.1365"])
      guard (NotifyJSON.int(update["update_num"]) ?? 0) > 0 else { return }
    }
    let data = try await web.get("https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all",
                                 ["type": "video", "timezone_offset": "-480", "features": NotifyWeb.feedFeatures])
    let items = NotifyJSON.objects(data["items"]).compactMap(NotifyItems.upload)
    let baseline = NotifyJSON.nonEmpty(data["update_baseline"]) ?? items.first?.key
    guard var cursor = state.cursors[key] else {
      return seed(.uploads, NotifyCursor(time: Self.now, baseline: baseline))
    }
    let fresh = cursor.take(items)
    cursor.baseline = baseline ?? cursor.baseline
    state.cursors[key] = cursor
    plan(.uploads, fresh)
  }

  /// One post per new item, newest last; past five, the older ones become one summary ahead of them.
  private func plan(_ kind: NotifyKind, _ fresh: [NotifyItem]) {
    let shown = fresh.suffix(Self.perKind)
    if fresh.count > shown.count { found.append(NotifyWording.summary(kind, more: fresh.count - shown.count)) }
    found.append(contentsOf: shown.map(NotifyWording.post))
  }

  private static func post(_ posts: [NotifyPost]) async -> Int {
    let center = UNUserNotificationCenter.current()
    var posted = 0
    for post in posts {
      guard !Task.isCancelled else { break }
      let content = UNMutableNotificationContent()
      content.title = post.title
      content.body = post.body
      content.sound = .default
      content.threadIdentifier = "com.kaichuan.bilifast.notify.\(post.kind.rawValue)"
      content.userInfo = NotifyRoutes.userInfo(post.route, kind: post.kind)
      let identifier = post.identifier ?? "com.kaichuan.bilifast.notify.\(UUID().uuidString)"
      do {
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        posted += 1
      } catch {
        continue
      }
    }
    return posted
  }
}

/// Why a check stopped. Only these words and numbers reach the trip and the log.
enum NotifyFailure: Error {
  case expired, risk, cancelled, decode
  case http(Int)
  case code(Int)
  case network(String, Int)

  var reason: String {
    switch self {
    case .expired: "expired"
    case .risk: "risk"
    case .cancelled: "out of time"
    case .decode: "decode"
    case .http(let status): "http \(status)"
    case .code(let code): "code \(code)"
    case .network(let domain, let code): "network \(domain) \(code)"
    }
  }
}

/// The website's calls as bili_core's BiliClient sends them (bili_client.dart): its User-Agent and Referer, the web
/// login's cookies as one header, no cache and no cookie store of its own.
final class NotifyWeb {
  private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    + "(KHTML, like Gecko) Version/26.0 Safari/605.1.15"
  private static let referer = "https://www.bilibili.com/"

  /// bili_core's dynamicFeed's (bili_client_dynamic.dart).
  static let feedFeatures =
    "itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,"
    + "ugcDelete,onlyfansQaCard,commentsNewVersion,avatarAutoTheme,sunflowerStyle,cardsEnhance,eva3CardOpus,"
    + "eva3CardVideo,eva3CardComment,eva3CardVote,eva3CardUser"

  private let session: URLSession
  private let cookie: String
  private let calls: NotifyCalls

  init(cookies: [String: String], calls: NotifyCalls) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 10
    session = URLSession(configuration: configuration)
    // In bili_core's CookieJar order: SESSDATA first, then by name.
    let names = cookies.keys.sorted { a, b in
      let aFirst = a.lowercased() == "sessdata", bFirst = b.lowercased() == "sessdata"
      return aFirst != bFirst ? aFirst : a < b
    }
    cookie = names.map { "\($0)=\(cookies[$0] ?? "")" }.joined(separator: "; ")
    self.calls = calls
  }

  func close() {
    session.invalidateAndCancel()
  }

  /// The answer's `data`. -101 is the login gone, -352/-412 and HTTP 412 Bilibili's risk control.
  func get(_ address: String, _ query: KeyValuePairs<String, String>) async throws -> [String: Any] {
    guard !Task.isCancelled else { throw NotifyFailure.cancelled }
    guard var components = URLComponents(string: address) else { throw NotifyFailure.decode }
    components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
    guard let url = components.url else { throw NotifyFailure.decode }
    var request = URLRequest(url: url)
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(Self.referer, forHTTPHeaderField: "Referer")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(cookie, forHTTPHeaderField: "Cookie")
    calls.add()
    let answer: (Data, URLResponse)
    do {
      answer = try await session.data(for: request)
    } catch {
      let failure = error as NSError
      if Task.isCancelled || error is CancellationError
        || (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) {
        throw NotifyFailure.cancelled
      }
      throw NotifyFailure.network(failure.domain, failure.code)
    }
    let (data, response) = answer
    guard let http = response as? HTTPURLResponse else { throw NotifyFailure.decode }
    if http.statusCode == 412 { throw NotifyFailure.risk }
    guard (200..<300).contains(http.statusCode) else { throw NotifyFailure.http(http.statusCode) }
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let code = NotifyJSON.int(root["code"]) else { throw NotifyFailure.decode }
    switch code {
    case 0: return root["data"] as? [String: Any] ?? [:]
    case -101: throw NotifyFailure.expired
    case -352, -412: throw NotifyFailure.risk
    default: throw NotifyFailure.code(Int(code))
    }
  }
}

enum NotifyJSON {
  /// Bilibili sends ids and times as numbers or strings. JSONSerialization keeps a 64-bit integer exact.
  static func int(_ value: Any?) -> Int64? {
    switch value {
    case let number as NSNumber: number.int64Value
    case let text as String: Int64(text)
    default: nil
    }
  }

  static func text(_ value: Any?) -> String {
    value as? String ?? ""
  }

  static func nonEmpty(_ value: Any?) -> String? {
    guard let text = value as? String, !text.isEmpty else { return nil }
    return text
  }

  static func objects(_ value: Any?) -> [[String: Any]] {
    (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
  }
}

/// One new thing from a list, before it is worded.
struct NotifyItem {
  let kind: NotifyKind
  /// Unique within its kind: the notification's id, a like's id at its time (a new liker moves the time), a card's id.
  let key: String
  let time: Int64
  /// The replier, the one who @'d or liked, the uploader.
  let who: String
  /// The reply, the liked comment or post, the video's title.
  let text: String
  /// 评论, 动态, 视频…: what a like was on, or where an @ was.
  var business = ""
  /// The others who liked it too.
  var others: Int64 = 0
  let route: NativeNotifyRoute
}

enum NotifyItems {
  /// A 回复我的 or @我的 item (docs/message/msg.md in bilibili-api-collect).
  static func comment(_ json: [String: Any], kind: NotifyKind, at timeField: String) -> NotifyItem? {
    guard let id = NotifyJSON.int(json["id"]), let time = NotifyJSON.int(json[timeField]) else { return nil }
    let item = json["item"] as? [String: Any] ?? [:]
    return NotifyItem(kind: kind, key: "\(id)", time: time,
                      who: NotifyJSON.text((json["user"] as? [String: Any])?["nickname"]),
                      text: NotifyJSON.text(item["source_content"]),
                      business: NotifyJSON.text(item["business"]),
                      route: NotifyRoutes.comment(item, kind: kind))
  }

  /// 赞 opens the app until 消息 is built.
  static func like(_ json: [String: Any]) -> NotifyItem? {
    guard let id = NotifyJSON.int(json["id"]), let time = NotifyJSON.int(json["like_time"]) else { return nil }
    let item = json["item"] as? [String: Any] ?? [:]
    let users = NotifyJSON.objects(json["users"])
    let likers = NotifyJSON.int(json["counts"]) ?? Int64(users.count)
    return NotifyItem(kind: .likes, key: "\(id)@\(time)", time: time, who: NotifyJSON.text(users.first?["nickname"]),
                      text: NotifyJSON.text(item["title"]), business: NotifyJSON.text(item["business"]),
                      others: max(likers - 1, 0), route: .app)
  }

  /// A 视频 card of the polymer feed, as bili_core's dynamic decode reads it (dynamic_models.dart).
  static func upload(_ json: [String: Any]) -> NotifyItem? {
    guard let id = NotifyJSON.nonEmpty(json["id_str"]) else { return nil }
    let modules = json["modules"] as? [String: Any]
    let author = modules?["module_author"] as? [String: Any]
    let major = (modules?["module_dynamic"] as? [String: Any])?["major"] as? [String: Any]
    guard let archive = major?["archive"] as? [String: Any] ?? major?["ugc_season"] as? [String: Any],
          let time = NotifyJSON.int(author?["pub_ts"]) else { return nil }
    let aid = NotifyJSON.int(archive["aid"]) ?? 0
    guard let bvid = NotifyJSON.nonEmpty(archive["bvid"]) ?? (aid > 0 ? NotifyRoutes.bvid(aid: aid) : nil) else {
      return nil
    }
    return NotifyItem(kind: .uploads, key: id, time: time, who: NotifyJSON.text(author?["name"]),
                      text: NotifyJSON.text(archive["title"]),
                      route: NativeNotifyRoute(target: .video, bvid: bvid, toComments: false))
  }
}

/// A notification ready to post.
struct NotifyPost {
  let kind: NotifyKind
  let title: String
  let body: String
  let route: NativeNotifyRoute
  /// Set where a newer post should replace the one before it.
  var identifier: String?
}

/// Every word the notifications show, in one place: the official app's lock-screen wording isn't captured yet.
enum NotifyWording {
  static func post(_ item: NotifyItem) -> NotifyPost {
    let who = item.who.isEmpty ? "有人" : item.who
    let title: String = switch item.kind {
    case .replies: "\(who) 回复了你"
    case .mentions: "\(who) 在\(item.business.isEmpty ? "评论" : item.business)中@了你"
    case .likes: likeTitle(who, item)
    case .uploads: "\(who) 投稿了新视频"
    case .messages: "私信"
    }
    return NotifyPost(kind: item.kind, title: title, body: item.text, route: item.route)
  }

  private static func likeTitle(_ who: String, _ item: NotifyItem) -> String {
    let target = item.business.isEmpty ? "评论" : item.business
    return item.others > 0 ? "\(who) 等 \(item.others + 1) 人赞了你的\(target)" : "\(who) 赞了你的\(target)"
  }

  /// One 私信 notification at a time: a newer count replaces the one before.
  static func messages(_ count: Int64) -> NotifyPost {
    NotifyPost(kind: .messages, title: "私信", body: "你有 \(count) 条新私信", route: .app,
               identifier: "com.kaichuan.bilifast.notify.messages")
  }

  static func summary(_ kind: NotifyKind, more: Int) -> NotifyPost {
    let (title, body): (String, String) = switch kind {
    case .replies: ("回复我的", "还有 \(more) 条新回复")
    case .mentions: ("@我的", "还有 \(more) 条新的@")
    case .likes: ("收到的赞", "还有 \(more) 条新的赞")
    case .uploads: ("关注的UP主投稿", "还有 \(more) 个新视频")
    case .messages: ("私信", "还有 \(more) 条新私信")
    }
    return NotifyPost(kind: kind, title: title, body: body, route: .app)
  }
}

/// Where a notification leads, carried in its userInfo: only what NativeNotifyRoute needs, never a name or text.
enum NotifyRoutes {
  private static let marker = "bilifast.notify"

  private static let bvidPattern = try! NSRegularExpression(pattern: "BV1[0-9A-Za-z]{9}")
  private static let aidPattern = try! NSRegularExpression(pattern: "/video/av([0-9]+)")
  private static let dynamicPattern = try! NSRegularExpression(
    pattern: "(?:t\\.bilibili\\.com/|/opus/|opus/detail/|following/detail/)([0-9]+)")

  static func userInfo(_ route: NativeNotifyRoute, kind: NotifyKind) -> [String: Any] {
    var info: [String: Any] = [marker: kind.rawValue, "target": route.target.rawValue, "toComments": route.toComments]
    if let bvid = route.bvid { info["bvid"] = bvid }
    if let commentRoot = route.commentRoot { info["commentRoot"] = commentRoot }
    if let comment = route.comment { info["comment"] = comment }
    if let dynamicId = route.dynamicId { info["dynamicId"] = dynamicId }
    return info
  }

  /// nil for a notification that isn't ours.
  static func route(_ info: [AnyHashable: Any]) -> NativeNotifyRoute? {
    guard info[marker] is String else { return nil }
    let target = NotifyJSON.int(info["target"]).flatMap { NativeNotifyTarget(rawValue: Int($0)) } ?? .app
    return NativeNotifyRoute(target: target, bvid: info["bvid"] as? String,
                             commentRoot: NotifyJSON.int(info["commentRoot"]), comment: NotifyJSON.int(info["comment"]),
                             dynamicId: info["dynamicId"] as? String, toComments: info["toComments"] as? Bool ?? false)
  }

  /// A reply or @ on a video (business 1: subject_id is its aid) opens its page on the thread; on a 动态 (11, 17) the
  /// post, on its comments unless an @ was in the post itself; anything else the app.
  static func comment(_ item: [String: Any], kind: NotifyKind) -> NativeNotifyRoute {
    let subject = NotifyJSON.int(item["subject_id"]) ?? 0
    let root = NotifyJSON.int(item["root_id"]) ?? 0
    let source = NotifyJSON.int(item["source_id"]) ?? 0
    let links = [NotifyJSON.text(item["uri"]), NotifyJSON.text(item["native_uri"])]
    switch NotifyJSON.int(item["business_id"]) ?? 0 {
    case 1:
      let aid = links.lazy.compactMap { match(aidPattern, in: $0, group: 1).flatMap { Int64($0) } }.first
        ?? (subject > 0 ? subject : nil)
      guard let video = links.lazy.compactMap({ match(bvidPattern, in: $0) }).first ?? aid.map(Self.bvid) else {
        return .app
      }
      let thread = root > 0 ? root : source
      return NativeNotifyRoute(target: .video, bvid: video, commentRoot: thread > 0 ? thread : nil,
                               comment: source > 0 ? source : nil, toComments: false)
    case let business where business == 11 || business == 17:
      // 17's subject_id is the post's own id; 11's is its picture album's, so only the link names the post.
      let linked = links.lazy.compactMap { match(dynamicPattern, in: $0, group: 1) }.first
      guard let id = linked ?? (business == 17 && subject > 0 ? "\(subject)" : nil) else { return .app }
      let onComment = kind == .replies || root > 0
        || links.contains { $0.contains("#reply") || $0.contains("comment_root_id") }
      return NativeNotifyRoute(target: .dynamicPost, dynamicId: id, toComments: onComment)
    default:
      return .app
    }
  }

  private static func match(_ pattern: NSRegularExpression, in link: String, group: Int = 0) -> String? {
    guard let match = pattern.firstMatch(in: link, range: NSRange(link.startIndex..., in: link)),
          let found = Range(match.range(at: group), in: link) else { return nil }
    return String(link[found])
  }

  private static let bvAlphabet = Array("FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf")

  /// Bilibili's published av → BV conversion, as bili_core's avToBv (bvid.dart).
  static func bvid(aid: Int64) -> String {
    var chars = Array("BV1000000000")
    var value = ((Int64(1) << 51) | aid) ^ 23442827791579
    var index = chars.count - 1
    while value > 0 {
      chars[index] = bvAlphabet[Int(value % 58)]
      value /= 58
      index -= 1
    }
    chars.swapAt(3, 9)
    chars.swapAt(4, 7)
    return String(chars)
  }
}
