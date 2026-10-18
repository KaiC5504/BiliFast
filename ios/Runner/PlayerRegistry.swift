import AVFoundation
import UIKit

/// Every native player by id. A player outlives its Flutter view: picture in picture keeps playing while the view is
/// gone, and a restored page attaches the same host view again. Only `dispose` releases one.
@MainActor
final class PlayerRegistry {
  private let events: PlayerEventApi
  private var players: [Int64: NativePlayer] = [:]
  private var nextId: Int64 = 1

  init(events: PlayerEventApi) {
    self.events = events
  }

  func create() -> Int64 {
    let id = nextId
    nextId += 1
    players[id] = NativePlayer(id: id, events: events)
    return id
  }

  func player(_ id: Int64) throws -> NativePlayer {
    guard let player = players[id] else {
      throw PlayerApiError(code: "no-player", message: "no native player \(id)", details: nil)
    }
    return player
  }

  func hostView(_ id: Int64) -> PlayerHostView? {
    players[id]?.host
  }

  func captureFrame(_ id: Int64, reply: CaptureReply) {
    guard let player = players[id] else {
      reply.call(.success(false))
      return
    }
    player.captureFrame(reply)
  }

  func dispose(_ id: Int64) {
    players.removeValue(forKey: id)?.dispose()
  }
}

/// Carries a Pigeon reply, a plain closure, into a task on the main actor.
struct CaptureReply: @unchecked Sendable {
  let call: (Result<Bool, Error>) -> Void
}

/// One AVPlayer, reused by every part a page plays so the layer and picture in picture stay attached, and what it
/// reports to Dart. Every report is sent only when it changed.
@MainActor
final class NativePlayer {
  let id: Int64
  let player: AVPlayer
  let host: PlayerHostView
  private let events: PlayerEventApi
  private var timeObserver: Any?
  private var playerObservations: [NSKeyValueObservation] = []
  private var itemObservations: [NSKeyValueObservation] = []
  private var itemTokens: [NSObjectProtocol] = []
  private var item: AVPlayerItem?
  /// Bumped by every load, unload and dispose; callbacks of an older item do nothing.
  private var generation = 0
  /// Whether playback should run once the start seek lands; a pause during it wins.
  private var wantsPlay = false
  private var ended = false
  private var failed = false
  /// The current item reached playing; a format failure after that is not a refusal at load.
  private var played = false
  /// Set by a load or a seek until playback starts; while set, a wait to minimize stalls ends as soon as
  /// `startAheadSeconds` are loaded (see `startIfBuffered`).
  private var starting = false
  /// Seeks AVPlayer has not finished: until they land, `.playing` is the old position's and must not end the start.
  private var pendingSeeks = 0
  private var status: NativePlayerStatus?
  private var reportedRate: Double?
  private var reportedDuration: Double?
  private var reportedSize: CGSize?
  private var reportedRanges: [NativeTimeRange]?

  init(id: Int64, events: PlayerEventApi) {
    self.id = id
    self.events = events
    player = AVPlayer()
    host = PlayerHostView()
    player.automaticallyWaitsToMinimizeStalling = true
    host.player = player
    host.onPiPActive = { [weak self] active in self?.pictureInPictureChanged(active) }
    host.onRestore = { [weak self] in self?.restoreRequested() ?? false }
    host.onLog = { [weak self] kind, fields in self?.log(kind, fields) }
    observePlayer()
  }

  func load(url: URL, headers: [String: String], startSeconds: Double, autoplay: Bool) {
    generation += 1
    let current = generation
    detachItem()
    ended = false
    failed = false
    played = false
    starting = true
    pendingSeeks = 0
    wantsPlay = autoplay
    reportedDuration = nil
    reportedSize = nil
    reportedRanges = nil
    var options: [String: Any] = [:]
    if !headers.isEmpty {
      // In direct mode the media playlists point at the CDN, which refuses requests without the Referer and
      // User-Agent. AVURLAssetHTTPHeaderFieldsKey is not in the public headers; AVFoundation honours it.
      options["AVURLAssetHTTPHeaderFieldsKey"] = headers
      if let agent = headers["User-Agent"] { options[AVURLAssetHTTPUserAgentKey] = agent }
    }
    let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
    item.preferredForwardBufferDuration = 30
    PlayerHostView.attachVideoOutput(to: item)
    self.item = item
    observe(item, generation: current)
    player.replaceCurrentItem(with: item)
    updateStatus()
    log("load", ["at": startSeconds, "play": autoplay])
    if startSeconds > 0 {
      let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
      // A reload mid-playback keeps the rate, so the new item can wait at 0 while this seek is in flight.
      pendingSeeks += 1
      player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
        onMainActor { self?.startSeekFinished(current) }
      }
    } else if autoplay {
      player.play()
    }
  }

  /// The page closed: without an item AVPlayer stops filling its 30 s forward buffer. The layer stays attached for
  /// the next load.
  func unload() {
    // An emptied player under a live picture in picture would leave a black window to close by hand.
    host.stopPiP()
    generation += 1
    pendingSeeks = 0
    wantsPlay = false
    // Detached first, so the pause doesn't report a status for the item being dropped.
    detachItem()
    player.pause()
    player.replaceCurrentItem(with: nil)
    updateStatus()
  }

  func play() {
    wantsPlay = true
    ended = false
    guard item != nil else { return }
    player.play()
    updateStatus()
  }

  func pause() {
    wantsPlay = false
    player.pause()
    updateStatus()
  }

  func seek(seconds: Double, precise: Bool) {
    guard item != nil else { return }
    ended = false
    starting = true
    pendingSeeks += 1
    let current = generation
    let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
    // Bilibili's DASH has one keyframe per 5 s segment. Landing on the one that starts the target's segment
    // decodes at once from the segment the engine already fetched for the hint or the seek.
    let before = precise ? CMTime.zero : Self.keyframeTolerance
    player.seek(to: target, toleranceBefore: before, toleranceAfter: .zero) { [weak self] _ in
      onMainActor { self?.seekLanded(current) }
    }
    updateStatus()
  }

  func setRate(_ rate: Double) {
    let value = Float(rate)
    player.defaultRate = value
    if player.timeControlStatus == .playing {
      // Setting `rate` is a new play request: waiting to minimize stalls, AVPlayer holds the picture while it judges
      // the buffer at the new rate, a hitch on every hold to 2× and every release. Already playing, the data is there.
      player.playImmediately(atRate: value)
    } else if player.rate > 0 {
      player.rate = value
    }
    reportRate(rate)
  }

  func setMuted(_ muted: Bool) {
    player.isMuted = muted
  }

  func setFit(_ fit: NativeFit) {
    switch fit {
    case .fit: host.fit = .fit
    case .fill: host.fit = .fill
    case .stretch: host.fit = .stretch
    case .ratio16x9: host.fit = .ratio16x9
    case .ratio4x3: host.fit = .ratio4x3
    }
  }

  func setMirrored(_ mirrored: Bool) {
    host.mirrored = mirrored
  }

  func startPiP() {
    host.startPiP()
  }

  func stopPiP() {
    host.stopPiP()
  }

  func setAutoPiP(_ enabled: Bool) {
    host.autoPiP = enabled
  }

  func captureFrame(_ reply: CaptureReply) {
    guard let item, let image = FrameCapture.capture(from: item) else {
      log("no frame to capture", [:])
      reply.call(.success(false))
      return
    }
    Task {
      let result = await FrameCapture.saveToPhotos(image)
      switch result {
      case .saved:
        reply.call(.success(true))
      case .refused(let status):
        self.log("photos access refused", ["status": status])
        reply.call(.success(false))
      case .failed(let error):
        self.log("saving the screenshot failed", ["error": error])
        reply.call(.success(false))
      }
    }
  }

  func dispose() {
    generation += 1
    pendingSeeks = 0
    wantsPlay = false
    player.pause()
    detachItem()
    player.replaceCurrentItem(with: nil)
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    timeObserver = nil
    playerObservations.forEach { $0.invalidate() }
    playerObservations = []
    host.tearDown()
  }

  func log(_ kind: String, _ fields: [String: Any]) {
    events.onLog(playerId: id, kind: kind, fields: fields.mapValues { Optional($0) }, completion: ignoreReply)
  }

  private func observePlayer() {
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                                                  queue: .main) { [weak self] time in
      MainActor.assumeIsolated { self?.tick(time) }
    }
    playerObservations = [
      player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
        onMainActor {
          self?.updateStatus()
          self?.startIfBuffered()
        }
      },
      player.observe(\.rate, options: [.new]) { [weak self] _, _ in
        onMainActor { self?.rateChanged() }
      },
      // At the start of an item the wait often begins as `.evaluatingBufferingRate` and changes reason while
      // `timeControlStatus` stays the same.
      player.observe(\.reasonForWaitingToPlay, options: [.new]) { [weak self] _, _ in
        onMainActor { self?.startIfBuffered() }
      },
    ]
  }

  private func observe(_ item: AVPlayerItem, generation current: Int) {
    itemObservations = [
      item.observe(\.status, options: [.new]) { [weak self] item, _ in
        guard item.status == .failed else {
          onMainActor { self?.itemChanged(current) }
          return
        }
        let failure = NativePlayer.failure(item.error, log: NativePlayer.logEntries(item))
        onMainActor { self?.itemFailed(failure, generation: current) }
      },
      item.observe(\.duration, options: [.new]) { [weak self] _, _ in
        onMainActor { self?.reportDuration(current) }
      },
      item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] _, _ in
        onMainActor {
          self?.reportBuffered(current)
          self?.startIfBuffered()
        }
      },
      item.observe(\.presentationSize, options: [.new]) { [weak self] _, _ in
        onMainActor { self?.reportSize(current) }
      },
    ]
    let center = NotificationCenter.default
    itemTokens = [
      center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.playedToEnd(current) }
      },
      center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
        let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        let failure = NativePlayer.failure(error, log: NativePlayer.logEntries(item))
        MainActor.assumeIsolated { self?.itemFailed(failure, generation: current) }
      },
      center.addObserver(forName: AVPlayerItem.newAccessLogEntryNotification, object: item, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.accessLogged(current) }
      },
      center.addObserver(forName: AVPlayerItem.newErrorLogEntryNotification, object: item, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.errorLogged(current) }
      },
    ]
  }

  private func detachItem() {
    itemObservations.forEach { $0.invalidate() }
    itemObservations = []
    itemTokens.forEach { NotificationCenter.default.removeObserver($0) }
    itemTokens = []
    item = nil
  }

  private func seekLanded(_ current: Int) {
    guard current == generation else { return }
    pendingSeeks = max(0, pendingSeeks - 1)
    startIfBuffered()
  }

  private func startSeekFinished(_ current: Int) {
    guard current == generation else { return }
    pendingSeeks = max(0, pendingSeeks - 1)
    guard wantsPlay else { return }
    player.play()
    updateStatus()
    startIfBuffered()
  }

  /// What a start or seek needs loaded before it plays. AVPlayer's own rule waits for more after a slow first
  /// segment: phone logs had it holding up to 7.7 s with the first segments of both tracks already in, while the
  /// engine keeps fetching ahead much faster than playback.
  static let startAheadSeconds = 3.0
  static let keyframeTolerance = CMTime(seconds: 6, preferredTimescale: 600)

  private func startIfBuffered() {
    guard starting, let item, player.currentItem === item, item.status == .readyToPlay else { return }
    if player.timeControlStatus == .playing {
      if pendingSeeks == 0 { starting = false }
      return
    }
    // Until the seek lands, currentTime is the old position, already loaded: judged there, the start ended at once
    // and AVPlayer's own rule decided at the new one, waiting up to 17 s on a cold CDN (phone, 1.0.0 (2)).
    guard pendingSeeks == 0 else { return }
    let reason = player.reasonForWaitingToPlay
    guard wantsPlay, player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
          reason == .toMinimizeStalls || reason == .evaluatingBufferingRate else { return }
    let now = item.currentTime().seconds
    let duration = item.duration.seconds
    guard now.isFinite else { return }
    let loadedEnd = item.loadedTimeRanges.map(\.timeRangeValue)
      .first { $0.start.seconds <= now + 0.1 && $0.end.seconds > now }?.end.seconds ?? now
    let needed = duration.isFinite ? min(now + Self.startAheadSeconds, duration - 0.1) : now + Self.startAheadSeconds
    guard loadedEnd >= needed else { return }
    starting = false
    log("start without waiting", ["at": now, "ahead": loadedEnd - now, "reason": reason?.rawValue ?? ""])
    player.playImmediately(atRate: player.defaultRate > 0 ? player.defaultRate : 1)
  }

  private func tick(_ time: CMTime) {
    guard item != nil, player.currentItem === item else { return }
    let seconds = time.seconds.isFinite ? time.seconds : 0
    // The rate the playhead moves at while playing; paused, the rate playback resumes at.
    let rate = player.rate > 0 ? player.rate : player.defaultRate
    events.onPosition(playerId: id, seconds: seconds, rate: Double(rate), completion: ignoreReply)
  }

  private func itemChanged(_ current: Int) {
    guard current == generation else { return }
    updateStatus()
    reportDuration(current)
  }

  private func playedToEnd(_ current: Int) {
    guard current == generation else { return }
    ended = true
    updateStatus()
  }

  private func rateChanged() {
    let rate = Double(player.rate)
    if rate > 0 { reportRate(rate) }
    updateStatus()
  }

  private func updateStatus() {
    let next: NativePlayerStatus
    if let item, player.currentItem === item {
      if failed {
        next = .idle
      } else if item.status != .readyToPlay {
        next = .loading
      } else if ended {
        next = .ended
      } else {
        switch player.timeControlStatus {
        case .playing: next = .playing
        case .waitingToPlayAtSpecifiedRate: next = .buffering
        case .paused: next = .paused
        @unknown default: next = .paused
        }
      }
    } else {
      next = .idle
    }
    if next == .playing { played = true }
    guard next != status else { return }
    status = next
    events.onStatus(playerId: id, status: next, completion: ignoreReply)
  }

  private func reportRate(_ rate: Double) {
    guard rate != reportedRate else { return }
    reportedRate = rate
    events.onRate(playerId: id, rate: rate, completion: ignoreReply)
  }

  private func reportDuration(_ current: Int) {
    guard current == generation, let item else { return }
    let seconds = item.duration.seconds
    guard seconds.isFinite, seconds > 0, seconds != reportedDuration else { return }
    reportedDuration = seconds
    events.onDuration(playerId: id, seconds: seconds, completion: ignoreReply)
  }

  private func reportBuffered(_ current: Int) {
    guard current == generation, let item else { return }
    let ranges = item.loadedTimeRanges.map(\.timeRangeValue).compactMap { range -> NativeTimeRange? in
      let start = range.start.seconds
      let end = range.end.seconds
      guard start.isFinite, end.isFinite else { return nil }
      return NativeTimeRange(start: start, end: end)
    }
    guard ranges != reportedRanges else { return }
    reportedRanges = ranges
    events.onBuffered(playerId: id, ranges: ranges, completion: ignoreReply)
  }

  private func reportSize(_ current: Int) {
    guard current == generation, let item else { return }
    let size = item.presentationSize
    guard size.width > 0, size.height > 0, size != reportedSize else { return }
    reportedSize = size
    events.onSize(playerId: id, width: Int64(size.width.rounded()), height: Int64(size.height.rounded()),
                  completion: ignoreReply)
  }

  private func itemFailed(_ failure: ItemFailure, generation current: Int) {
    guard current == generation, !failed else { return }
    failed = true
    var fields: [String: Any] = ["kind": failure.kind.rawValue, "played": played, "error": failure.description,
                                 "chain": failure.chain]
    if let domain = failure.domain { fields["domain"] = domain }
    if let code = failure.code { fields["code"] = code }
    log("item failed", fields)
    let message = failure.kind == .network ? "网络连接失败，请检查网络后重试" : "播放失败，请稍后重试"
    events.onFailure(playerId: id, message: message, domain: failure.domain, code: failure.code.map { Int64($0) },
                     formatRejected: failure.kind == .format, completion: ignoreReply)
    updateStatus()
  }

  private func accessLogged(_ current: Int) {
    guard current == generation, let event = item?.accessLog()?.events.last else { return }
    var fields: [String: Any] = ["stalls": event.numberOfStalls, "bytes": event.numberOfBytesTransferred,
                                 "droppedFrames": event.numberOfDroppedVideoFrames]
    // Negative or NaN while AVFoundation doesn't know them.
    if event.indicatedBitrate.isFinite, event.indicatedBitrate >= 0 { fields["indicatedBitrate"] = event.indicatedBitrate.rounded() }
    if event.observedBitrate.isFinite, event.observedBitrate >= 0 { fields["observedBitrate"] = event.observedBitrate.rounded() }
    if event.transferDuration.isFinite { fields["transferMs"] = (event.transferDuration * 1000).rounded() }
    log("access log", fields)
  }

  private func errorLogged(_ current: Int) {
    guard current == generation, let event = item?.errorLog()?.events.last else { return }
    log("error log", ["status": event.errorStatusCode, "domain": event.errorDomain,
                      "comment": event.errorComment ?? "", "uri": NativePlayer.withoutQuery(event.uri)])
  }

  private func pictureInPictureChanged(_ active: Bool) {
    events.onPictureInPicture(playerId: id, active: active, completion: ignoreReply)
  }

  /// No page can come back for a player yet, so an off-screen restore ends at once instead of AVKit waiting 3 s;
  /// a view still on screen completes the restore by itself (PlayerHostView).
  private func restoreRequested() -> Bool {
    events.onPictureInPictureRestore(playerId: id, completion: ignoreReply)
    return false
  }

  enum FailureKind: String {
    case format, network, unknown
  }

  struct ItemFailure {
    let kind: FailureKind
    /// The error that decided the kind: the URL error, the error log entry or the AVFoundation format error.
    let domain: String?
    let code: Int?
    let description: String
    let chain: String
  }

  struct ErrorLogEntry {
    let domain: String
    let status: Int
    let comment: String
  }

  nonisolated static func failure(_ error: Error?, log: [ErrorLogEntry]) -> ItemFailure {
    let chain = errorChain(error)
    let kind = classify(error, log: log)
    var decisive: (domain: String, code: Int)?
    switch kind {
    case .network:
      if let url = chain.first(where: { $0.domain == NSURLErrorDomain }) {
        decisive = (domain: url.domain, code: url.code)
      } else if let entry = log.last(where: isNetwork) {
        decisive = (domain: entry.domain, code: entry.status)
      }
    case .format:
      decisive = chain.first(where: isFormat).map { (domain: $0.domain, code: $0.code) }
    case .unknown:
      decisive = chain.first.map { (domain: $0.domain, code: $0.code) }
    }
    return ItemFailure(kind: kind, domain: decisive?.domain, code: decisive?.code,
                       description: chain.first?.localizedDescription ?? "no error",
                       chain: chain.map { "\($0.domain) \($0.code)" }.joined(separator: " < "))
  }

  /// Format means AVFoundation could not parse or decode the media. Any sign of a network or HTTP
  /// failure wins: an expired URL's 403 body also fails to parse.
  nonisolated static func classify(_ error: Error?, log: [ErrorLogEntry]) -> FailureKind {
    let chain = errorChain(error)
    if log.contains(where: isNetwork) || chain.contains(where: { $0.domain == NSURLErrorDomain }) { return .network }
    return chain.contains(where: isFormat) ? .format : .unknown
  }

  nonisolated private static func errorChain(_ error: Error?) -> [NSError] {
    var chain: [NSError] = []
    var next = error.map { $0 as NSError }
    while let current = next, chain.count < 8 {
      chain.append(current)
      next = current.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return chain
  }

  nonisolated private static func isNetwork(_ entry: ErrorLogEntry) -> Bool {
    entry.domain == NSURLErrorDomain || (400..<600).contains(entry.status) || entry.comment.hasPrefix("HTTP ")
  }

  nonisolated private static func isFormat(_ error: NSError) -> Bool {
    let formatCodes: Set<AVError.Code> = [.decodeFailed, .decoderNotFound, .fileFormatNotRecognized, .failedToParse]
    return error.domain == AVFoundationErrorDomain && AVError.Code(rawValue: error.code).map { formatCodes.contains($0) } == true
  }

  /// Only entries from around the failure: an earlier 403 the player recovered from says nothing about it.
  nonisolated static func logEntries(_ item: AVPlayerItem, now: Date = Date()) -> [ErrorLogEntry] {
    let events = item.errorLog()?.events ?? []
    let recent: [AVPlayerItemErrorLogEvent]
    if events.allSatisfy({ $0.date == nil }) {
      recent = Array(events.suffix(1))
    } else {
      recent = events.filter { event in event.date.map { now.timeIntervalSince($0) <= 10 } ?? false }
    }
    return recent.map { ErrorLogEntry(domain: $0.errorDomain, status: $0.errorStatusCode, comment: $0.errorComment ?? "") }
  }

  /// Direct mode's segment URIs carry the CDN signature in the query.
  nonisolated static func withoutQuery(_ uri: String?) -> String {
    guard let uri, var components = URLComponents(string: uri) else { return "" }
    components.query = nil
    components.fragment = nil
    return components.string ?? ""
  }
}

/// AVFoundation reports KVO changes on whichever thread made them; most already arrive on the main thread,
/// where they are handled at once so the events keep their order.
private func onMainActor(_ body: @escaping @MainActor () -> Void) {
  if Thread.isMainThread {
    MainActor.assumeIsolated(body)
  } else {
    DispatchQueue.main.async { MainActor.assumeIsolated(body) }
  }
}

private func ignoreReply(_ result: Result<Void, PlayerApiError>) {}
