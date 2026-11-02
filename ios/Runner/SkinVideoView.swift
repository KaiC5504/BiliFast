import AVFoundation
import Flutter
import UIKit

/// The 我的 header's `head_myself_mp4_bg` for Dart's SkinVideo: a muted video from a file in the support folder,
/// looping or played once (`path`, `loop`). Only the first video track is played, so it never activates the audio
/// session; with `sound` (the own space's 空间头图) the first audio track is kept too, heard only while not `muted`.
///
/// Each view has its own `bilifast/skin_video/<id>` channel: Dart sends `play` and `pause` (a new view waits paused)
/// and `setMuted` with a bool, the view sends `ready` once its first frame shows and `failed` with "domain code" when
/// the file won't load or play.
enum SkinVideoView {
  static let viewType = "bilifast/skin_video"

  static func register(with registrar: FlutterPluginRegistrar) {
    // Touchless, and IgnorePointer in Dart: nothing to block, and no delaying recognizer on top (PlayerChannel's).
    registrar.register(SkinVideoFactory(messenger: registrar.messenger()), withId: viewType,
                       gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture)
  }
}

final class SkinVideoFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let params = args as? [String: Any]
    let path = params?["path"] as? String ?? ""
    let loop = (params?["loop"] as? NSNumber)?.boolValue ?? false
    let sound = (params?["sound"] as? NSNumber)?.boolValue ?? false
    let muted = (params?["muted"] as? NSNumber)?.boolValue ?? true
    let channel = FlutterMethodChannel(name: "\(SkinVideoView.viewType)/\(viewId)", binaryMessenger: messenger)
    let host: SkinVideoHostView = MainActor.assumeIsolated {
      SkinVideoHostView(frame: frame, path: path, loop: loop, sound: sound, muted: muted, channel: channel)
    }
    return SkinVideoPlatformView(host: host)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class SkinVideoPlatformView: NSObject, FlutterPlatformView {
  private let host: SkinVideoHostView

  init(host: SkinVideoHostView) {
    self.host = host
    super.init()
  }

  func view() -> UIView {
    host
  }

  /// iOS platform views get no dispose call: the engine releases this object, and the player goes with it.
  deinit {
    let host = self.host
    DispatchQueue.main.async {
      MainActor.assumeIsolated { host.tearDown() }
    }
  }
}

/// The video laid out as the header's picture is drawn in Dart (BoxFit.cover from the top centre), so it lands
/// exactly where the picture was. It takes no touches.
final class SkinVideoHostView: UIView {
  private let playerLayer = AVPlayerLayer()
  private let channel: FlutterMethodChannel
  private let loop: Bool
  private let sound: Bool
  private var muted: Bool
  private var player: AVQueuePlayer?
  private var looper: AVPlayerLooper?
  private var onceItem: AVPlayerItem?
  /// The video's size on screen, its track's transform applied; zero until the file has loaded.
  private var displaySize = CGSize.zero
  private var loadTask: Task<Void, Never>?
  private var observations: [NSKeyValueObservation] = []
  /// Each played item's tracks, which load after the item is made; by the item.
  private var trackObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
  private var tokens: [NSObjectProtocol] = []
  /// What Dart last asked for; going to the background pauses without changing it.
  private var wantsPlay = false
  private var finished = false
  private var failed = false
  private var reportedReady = false
  private var tornDown = false

  private var mayPlay: Bool {
    wantsPlay && !finished && !failed && UIApplication.shared.applicationState != .background
  }

  private var audible: Bool { sound && !muted }

  init(frame: CGRect, path: String, loop: Bool, sound: Bool, muted: Bool, channel: FlutterMethodChannel) {
    self.channel = channel
    self.loop = loop
    self.sound = sound
    self.muted = muted
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    clipsToBounds = true
    isUserInteractionEnabled = false
    playerLayer.videoGravity = .resizeAspectFill
    layer.addSublayer(playerLayer)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "play", "pause":
        let play = call.method == "play"
        MainActor.assumeIsolated { self?.setWantsPlay(play) }
        result(nil)
      case "setMuted":
        guard let muted = (call.arguments as? NSNumber)?.boolValue else {
          result(FlutterError(code: "bad_args", message: "setMuted takes a bool", details: nil))
          return
        }
        MainActor.assumeIsolated { self?.setMuted(muted) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(didEnterBackground),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.addObserver(self, selector: #selector(willEnterForeground),
                       name: UIApplication.willEnterForegroundNotification, object: nil)
    loadVideo(URL(fileURLWithPath: path))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    // A sublayer's frame would animate implicitly; the header's size changes follow Dart's own animation.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    playerLayer.frame = Self.videoFrame(displaySize, in: bounds)
    CATransaction.commit()
  }

  /// Dart's BoxFit.cover with Alignment.topCenter: the whole box covered, the video's top on the box's top.
  private static func videoFrame(_ size: CGSize, in bounds: CGRect) -> CGRect {
    guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
    let scale = max(bounds.width / size.width, bounds.height / size.height)
    let width = size.width * scale
    let height = size.height * scale
    return CGRect(x: bounds.minX + (bounds.width - width) / 2, y: bounds.minY, width: width, height: height)
  }

  func tearDown() {
    guard !tornDown else { return }
    tornDown = true
    channel.setMethodCallHandler(nil)
    NotificationCenter.default.removeObserver(self)
    loadTask?.cancel()
    loadTask = nil
    observations.forEach { $0.invalidate() }
    observations = []
    trackObservations.values.forEach { $0.invalidate() }
    trackObservations = [:]
    tokens.forEach { NotificationCenter.default.removeObserver($0) }
    tokens = []
    looper?.disableLooping()
    looper = nil
    onceItem = nil
    player?.pause()
    player?.removeAllItems()
    player = nil
    playerLayer.player = nil
  }

  private func loadVideo(_ url: URL) {
    let sound = self.sound
    loadTask = Task { [weak self] in
      do {
        let video = try await SkinVideoHostView.playerItem(url, sound: sound)
        guard let self, !Task.isCancelled, !self.tornDown else { return }
        self.start(video.item, size: video.size)
      } catch {
        guard let self, !Task.isCancelled, !self.tornDown else { return }
        self.fail(skinVideoFailure(error))
      }
    }
  }

  /// The file's first video track in a composition, and with `sound` its first audio track: with no audio track at
  /// all, the player has nothing to play through the app's AVAudioSession, which the video player owns.
  private static func playerItem(_ url: URL, sound: Bool) async throws -> (item: AVPlayerItem, size: CGSize) {
    // Without an extension AVFoundation can't tell what the file is.
    let options: [String: Any]? = url.pathExtension.isEmpty ? [AVURLAssetOverrideMIMETypeKey: "video/mp4"] : nil
    let asset = AVURLAsset(url: url, options: options)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      throw NSError(domain: "SkinVideo.noVideoTrack", code: 0)
    }
    let range = try await track.load(.timeRange)
    let transform = try await track.load(.preferredTransform)
    let naturalSize = try await track.load(.naturalSize)
    let shown = CGRect(origin: .zero, size: naturalSize).applying(transform).size
    var audio: (track: AVAssetTrack, range: CMTimeRange)?
    if sound, let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
      let audioRange = try await audioTrack.load(.timeRange)
      audio = (track: audioTrack, range: audioRange)
    }
    // A track holds its asset weakly.
    let composition = try withExtendedLifetime(asset) {
      try videoComposition(of: track, range: range, transform: transform, audio: audio)
    }
    return (item: AVPlayerItem(asset: composition), size: shown)
  }

  /// Synchronous on purpose: inside an async function, insertTimeRange could resolve to an async overload.
  private static func videoComposition(
    of track: AVAssetTrack, range: CMTimeRange, transform: CGAffineTransform,
    audio: (track: AVAssetTrack, range: CMTimeRange)?
  ) throws -> AVMutableComposition {
    let composition = AVMutableComposition()
    guard let copy = composition.addMutableTrack(withMediaType: .video,
                                                 preferredTrackID: kCMPersistentTrackID_Invalid) else {
      throw NSError(domain: "SkinVideo.noCompositionTrack", code: 0)
    }
    try copy.insertTimeRange(range, of: track, at: .zero)
    copy.preferredTransform = transform
    if let audio, let audioCopy = composition.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid) {
      // Within the picture's time, so a loop never runs on for the sound's tail.
      let start = CMTimeMaximum(audio.range.start, range.start)
      let end = CMTimeMinimum(audio.range.end, range.end)
      do {
        guard CMTimeCompare(end, start) > 0 else { throw NSError(domain: "SkinVideo.noAudioOverlap", code: 0) }
        try audioCopy.insertTimeRange(CMTimeRange(start: start, end: end), of: audio.track,
                                      at: CMTimeSubtract(start, range.start))
      } catch {
        // The picture plays on without its sound rather than not at all.
        composition.removeTrack(audioCopy)
      }
    }
    return composition
  }

  private func start(_ item: AVPlayerItem, size: CGSize) {
    displaySize = size
    setNeedsLayout()
    let player = AVQueuePlayer()
    player.isMuted = !audible
    player.allowsExternalPlayback = false
    player.preventsDisplaySleepDuringVideoPlayback = false
    let center = NotificationCenter.default
    // KVO calls back on any thread, so the handlers are not main-actor isolated.
    if loop {
      let looper = AVPlayerLooper(player: player, templateItem: item)
      self.looper = looper
      observations.append(looper.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] looper, _ in
        guard looper.status == .failed else { return }
        let reason = skinVideoFailure(looper.error)
        DispatchQueue.main.async { [weak self] in
          MainActor.assumeIsolated { self?.fail(reason) }
        }
      })
    } else {
      player.actionAtItemEnd = .pause
      player.insert(item, after: nil)
      onceItem = item
      observations.append(item.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] item, _ in
        guard item.status == .failed else { return }
        let reason = skinVideoFailure(item.error)
        DispatchQueue.main.async { [weak self] in
          MainActor.assumeIsolated { self?.fail(reason) }
        }
      })
      tokens.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                       object: item, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.finished = true }
      })
    }
    // Any item: the looper plays copies of its template.
    tokens.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                                     object: nil, queue: .main) { [weak self] note in
      guard let played = note.object as? AVPlayerItem else { return }
      let id = ObjectIdentifier(played)
      let reason = skinVideoFailure(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
      MainActor.assumeIsolated {
        guard let self, self.plays(id) else { return }
        self.fail(reason)
      }
    })
    self.player = player
    playerLayer.player = player
    if sound {
      // Set up before playing, so each replica's sound track is switched off as it loads, not once it is heard.
      observations.append(player.observe(\.currentItem, options: [.new]) { @Sendable [weak self] _, _ in
        if Thread.isMainThread {
          MainActor.assumeIsolated { self?.applyAudible() }
        } else {
          DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.applyAudible() }
          }
        }
      })
      applyAudible()
    }
    observations.append(
      playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { @Sendable [weak self] _, change in
        guard change.newValue == true else { return }
        DispatchQueue.main.async { [weak self] in
          MainActor.assumeIsolated { self?.firstFrameShown() }
        }
      })
    if mayPlay { player.play() }
  }

  private func plays(_ id: ObjectIdentifier) -> Bool {
    if let onceItem, ObjectIdentifier(onceItem) == id { return true }
    return looper?.loopingPlayerItems.contains { ObjectIdentifier($0) == id } ?? false
  }

  private func firstFrameShown() {
    guard !reportedReady, !failed, !tornDown else { return }
    reportedReady = true
    channel.invokeMethod("ready", arguments: nil)
  }

  private func fail(_ reason: String) {
    guard !failed, !tornDown else { return }
    failed = true
    player?.pause()
    channel.invokeMethod("failed", arguments: reason)
  }

  private func setMuted(_ muted: Bool) {
    guard muted != self.muted else { return }
    self.muted = muted
    applyAudible()
  }

  /// Muted, the items' sound tracks are switched off as well as the player muted, so a muted banner never takes the
  /// audio session from another app's music. Heard, it plays through the `.playback` category AppDelegate sets for the
  /// video player, which the ringer switch doesn't silence. Muting again leaves the session as it is: a video page or
  /// the small window may be playing through it.
  private func applyAudible() {
    guard sound, !tornDown, let player else { return }
    let audible = self.audible
    if audible { Self.preparePlaybackSession() }
    var items = looper?.loopingPlayerItems ?? []
    if let onceItem { items.append(onceItem) }
    if let current = player.currentItem, !items.contains(where: { $0 === current }) { items.append(current) }
    for item in items {
      watchTracks(of: item)
      Self.setAudioTracks(of: item, enabled: audible)
    }
    player.isMuted = !audible
  }

  private func watchTracks(of item: AVPlayerItem) {
    let id = ObjectIdentifier(item)
    guard trackObservations[id] == nil else { return }
    trackObservations[id] = item.observe(\.tracks, options: [.new]) { @Sendable [weak self] _, _ in
      if Thread.isMainThread {
        MainActor.assumeIsolated { self?.applyAudible() }
      } else {
        DispatchQueue.main.async { [weak self] in
          MainActor.assumeIsolated { self?.applyAudible() }
        }
      }
    }
  }

  private static func setAudioTracks(of item: AVPlayerItem, enabled: Bool) {
    for track in item.tracks where track.assetTrack?.mediaType == .audio && track.isEnabled != enabled {
      track.isEnabled = enabled
    }
  }

  /// AppDelegate's category, set again only if something has changed it.
  private static func preparePlaybackSession() {
    let session = AVAudioSession.sharedInstance()
    guard session.category != .playback else { return }
    do {
      try session.setCategory(.playback, mode: .moviePlayback)
    } catch {
      print("skin video audio session category failed: \(error)")
    }
  }

  private func setWantsPlay(_ play: Bool) {
    wantsPlay = play
    guard let player else { return }
    // Played once, it holds its last frame; in the background, willEnterForeground starts it.
    if play {
      if mayPlay { player.play() }
    } else {
      player.pause()
    }
  }

  @objc private func didEnterBackground() {
    player?.pause()
  }

  @objc private func willEnterForeground() {
    guard wantsPlay, !finished, !failed else { return }
    player?.play()
  }
}

private func skinVideoFailure(_ error: Error?) -> String {
  guard let error else { return "SkinVideo.unknown 0" }
  let nsError = error as NSError
  return "\(nsError.domain) \(nsError.code)"
}
