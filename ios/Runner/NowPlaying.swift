import AVFoundation
import MediaPlayer
import UIKit

/// 后台听视频's background policy per player, and the lock screen and Control Center for the player now playing
/// (MPNowPlayingSession): its title, uploader and cover, its remote commands, and audio interruptions.
@MainActor
enum NowPlaying {
  /// Off is .automatic rather than .pauses: .automatic pauses in the background except in picture in picture;
  /// .pauses promises no such exception.
  static func setBackgroundPlayback(_ player: NativePlayer, enabled: Bool) {
    player.player.audiovisualBackgroundPlaybackPolicy = enabled ? .continuesIfPossible : .automatic
    player.log("background playback", ["enabled": enabled, "policy": policyName(player.player)])
  }

  static func set(_ player: NativePlayer, info: NativeNowPlaying?) {
    guard let info else {
      guard let session = player.nowPlaying else { return }
      player.nowPlaying = nil
      sessions.removeAll { $0.session == nil || $0.session === session }
      session.end()
      player.log("now playing cleared", [:])
      return
    }
    observeInterruptions()
    let created = player.nowPlaying == nil
    let session = player.nowPlaying ?? Session(owner: player)
    player.nowPlaying = session
    sessions.removeAll { $0.session == nil || $0.session === session }
    sessions.append(WeakSession(session: session))
    session.update(info)
    player.log("now playing set", ["created": created, "artwork": info.artworkPath != nil,
                                   "previous": info.hasPrevious, "next": info.hasNext,
                                   "item": player.player.currentItem != nil])
    session.becomeActive()
  }

  static func policyName(_ player: AVPlayer) -> String {
    switch player.audiovisualBackgroundPlaybackPolicy {
    case .automatic: "automatic"
    case .pauses: "pauses"
    case .continuesIfPossible: "continuesIfPossible"
    @unknown default: "\(player.audiovisualBackgroundPlaybackPolicy.rawValue)"
    }
  }

  private struct WeakSession {
    weak var session: Session?
  }

  /// Every player's session, oldest set first.
  private static var sessions: [WeakSession] = []
  private static var interruptionToken: NSObjectProtocol?
  /// The player the interruption under way began on, whose end must reach it even after Dart clears its lock screen.
  private static weak var interruptedOwner: NativePlayer?

  private static func observeInterruptions() {
    guard interruptionToken == nil else { return }
    interruptionToken = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
    ) { note in
      let values = note.userInfo ?? [:]
      let type = (values[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
      let options = AVAudioSession.InterruptionOptions(rawValue: values[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
      let reason = values[AVAudioSessionInterruptionReasonKey] as? UInt
      MainActor.assumeIsolated { interrupted(type, options: options, reason: reason) }
    }
  }

  /// Goes to the player the interruption began on; with none yet, to the session iOS shows, else the one set last.
  private static func interrupted(_ type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions,
                                  reason: UInt?) {
    guard let type else { return }
    let began = type == .began
    let live = sessions.compactMap(\.session)
    let active = live.last { $0.isActive }
    let shown = (active ?? live.last)?.owner
    // iOS may never send the end, so each start picks afresh rather than trusting a remembered player.
    let target = began ? shown : interruptedOwner ?? shown
    interruptedOwner = began ? target : nil
    guard let owner = target else { return }
    let shouldResume = !began && options.contains(.shouldResume)
    owner.log("audio interruption", ["began": began, "shouldResume": shouldResume, "reason": reasonName(reason),
                                     "active": active != nil, "session": owner.nowPlaying != nil])
    owner.sendInterruption(began: began, shouldResume: shouldResume)
  }

  private static func reasonName(_ raw: UInt?) -> String {
    guard let raw else { return "none" }
    switch AVAudioSession.InterruptionReason(rawValue: raw) {
    case .default: return "default"
    case .appWasSuspended: return "appWasSuspended"
    case .builtInMicMuted: return "builtInMicMuted"
    default: return "\(raw)"
    }
  }

  /// One player's MPNowPlayingSession, made when the player is first set and ended when it is cleared or disposed.
  /// The skin video's player never joins one, so it can't take the lock screen.
  @MainActor
  final class Session: NSObject, MPNowPlayingSessionDelegate {
    private(set) weak var owner: NativePlayer?
    private let player: AVPlayer
    private let session: MPNowPlayingSession
    private var info: NativeNowPlaying?
    /// The path `artwork` is for, or is loading for.
    private var artworkPath: String?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var targets: [(command: MPRemoteCommand, target: Any)] = []
    private var reportedActive: Bool?
    private var ended = false

    /// The lock screen's long side; a cached video's cover.jpg can be the full upload.
    nonisolated private static let artworkLongSide: CGFloat = 1280

    var isActive: Bool { session.isActive }

    init(owner: NativePlayer) {
      self.owner = owner
      player = owner.player
      session = MPNowPlayingSession(players: [owner.player])
      super.init()
      session.automaticallyPublishesNowPlayingInfo = true
      session.delegate = self
      let center = session.remoteCommandCenter
      handle(center.playCommand, .play)
      handle(center.pauseCommand, .pause)
      handle(center.togglePlayPauseCommand, .toggle)
      handle(center.changePlaybackPositionCommand, .seek)
      handle(center.nextTrackCommand, .next)
      handle(center.previousTrackCommand, .previous)
      // The official lock screen has no ☆ and no ±15 s.
      let unused: [MPRemoteCommand] = [
        center.skipForwardCommand, center.skipBackwardCommand, center.seekForwardCommand, center.seekBackwardCommand,
        center.likeCommand, center.dislikeCommand, center.bookmarkCommand, center.ratingCommand,
        center.changePlaybackRateCommand,
      ]
      unused.forEach { $0.isEnabled = false }
    }

    func update(_ info: NativeNowPlaying) {
      self.info = info
      session.remoteCommandCenter.nextTrackCommand.isEnabled = info.hasNext
      session.remoteCommandCenter.previousTrackCommand.isEnabled = info.hasPrevious
      if info.artworkPath != artworkPath {
        artworkTask?.cancel()
        artworkTask = nil
        artwork = nil
        artworkPath = info.artworkPath
        if let path = info.artworkPath { loadArtwork(path) }
      }
      refreshPlayback()
    }

    /// The player's next item: the metadata is the item's, so every load needs it again.
    func attach(_ item: AVPlayerItem) {
      item.nowPlayingInfo = metadata(for: item, current: false)
    }

    /// The session's own publishing left the lock screen's timeline blank until the first seek (1.3.0 (10) on the
    /// phone), so the item's info carries the duration, position and rate too, set again whenever one changes.
    func refreshPlayback() {
      guard !ended, let item = player.currentItem else { return }
      item.nowPlayingInfo = metadata(for: item, current: true)
    }

    func becomeActive() {
      session.becomeActiveIfPossible { @Sendable [weak self] active in
        onMainActor { self?.activeChanged(active) }
      }
    }

    func end() {
      ended = true
      artworkTask?.cancel()
      artworkTask = nil
      for (command, target) in targets {
        command.removeTarget(target)
        command.isEnabled = false
      }
      targets = []
      player.currentItem?.nowPlayingInfo = nil
      // Turning publishing off first already drops the session's observers on the player, and removePlayer then
      // removes them again: an uncaught KVO exception (the crash on leaving a page in the first phone build).
      session.removePlayer(player)
      session.automaticallyPublishesNowPlayingInfo = false
      session.nowPlayingInfoCenter.nowPlayingInfo = nil
      session.delegate = nil
    }

    nonisolated func nowPlayingSessionDidChangeActive(_ nowPlayingSession: MPNowPlayingSession) {
      let active = nowPlayingSession.isActive
      onMainActor { [weak self] in self?.activeChanged(active) }
    }

    /// iOS doesn't retry a becomeActiveIfPossible it refused.
    nonisolated func nowPlayingSessionDidChangeCanBecomeActive(_ nowPlayingSession: MPNowPlayingSession) {
      onMainActor { [weak self] in
        guard let self, !self.ended, self.session.canBecomeActive,
              NowPlaying.sessions.compactMap(\.session).last === self else { return }
        self.becomeActive()
      }
    }

    /// [current]: [item] is the player's, so its position and rate are the player's.
    private func metadata(for item: AVPlayerItem, current: Bool) -> [String: Any] {
      guard let info else { return [:] }
      var values: [String: Any] = [MPMediaItemPropertyTitle: info.title, MPMediaItemPropertyArtist: info.artist]
      if let artwork { values[MPMediaItemPropertyArtwork] = artwork }
      let duration = item.duration.seconds
      if duration.isFinite, duration > 0 { values[MPMediaItemPropertyPlaybackDuration] = duration }
      if current {
        let elapsed = player.currentTime().seconds
        if elapsed.isFinite { values[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed) }
        values[MPNowPlayingInfoPropertyPlaybackRate] = Double(player.rate)
      }
      values[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
      values[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
      return values
    }

    /// Dart decides what each button does, so nothing plays or pauses here.
    private func handle(_ command: MPRemoteCommand, _ kind: NativeRemoteCommand) {
      command.isEnabled = true
      let target = command.addTarget { @Sendable [weak self] event in
        let seconds = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
        onMainActor { self?.commanded(kind, seconds: seconds) }
        return .success
      }
      targets.append((command: command, target: target))
    }

    private func commanded(_ kind: NativeRemoteCommand, seconds: Double?) {
      guard !ended, let owner else { return }
      var fields: [String: Any] = ["command": String(describing: kind)]
      if kind == .seek, let seconds { fields["at"] = seconds }
      owner.log("remote command", fields)
      owner.sendRemoteCommand(kind, seconds: kind == .seek ? seconds : nil)
    }

    private func activeChanged(_ active: Bool) {
      guard !ended, active != reportedActive else { return }
      reportedActive = active
      owner?.log("now playing active", ["active": active])
    }

    private func loadArtwork(_ path: String) {
      artworkTask = Task { [weak self] in
        let image = await Task.detached(priority: .utility) { Session.artworkImage(path) }.value
        guard let self, !Task.isCancelled, !self.ended, self.artworkPath == path else { return }
        guard let image else {
          self.owner?.log("now playing artwork unreadable", [:])
          return
        }
        // Its own size, so the lock screen draws the 16:9 cover whole rather than a square crop. @Sendable: MediaPlayer
        // asks for the picture off the main thread.
        self.artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
        self.owner?.log("now playing artwork", ["width": Int(image.size.width), "height": Int(image.size.height)])
        self.refreshPlayback()
      }
    }

    /// Decoded here, off the main thread, so MediaPlayer's request costs nothing.
    nonisolated private static func artworkImage(_ path: String) -> UIImage? {
      guard let data = FileManager.default.contents(atPath: path), let image = UIImage(data: data) else { return nil }
      let longest = max(image.size.width, image.size.height)
      guard longest > artworkLongSide else { return image.preparingForDisplay() ?? image }
      let scale = artworkLongSide / longest
      let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
      return image.preparingThumbnail(of: size) ?? image
    }
  }
}
