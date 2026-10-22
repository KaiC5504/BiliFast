import AVFoundation
import Flutter
import UIKit

/// The 我的 header's `head_myself_mp4_bg` for Dart's SkinVideo: a muted video from a file in the support folder,
/// looping or played once (`path`, `loop`). Only the first video track is played, so it never activates the audio
/// session.
///
/// Each view has its own `bilifast/skin_video/<id>` channel: Dart sends `play` and `pause` (a new view waits paused),
/// the view sends `ready` once its first frame shows and `failed` with "domain code" when the file won't load or play.
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
    let channel = FlutterMethodChannel(name: "\(SkinVideoView.viewType)/\(viewId)", binaryMessenger: messenger)
    let host: SkinVideoHostView = MainActor.assumeIsolated {
      SkinVideoHostView(frame: frame, path: path, loop: loop, channel: channel)
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
  private var player: AVQueuePlayer?
  private var looper: AVPlayerLooper?
  private var onceItem: AVPlayerItem?
  /// The video's size on screen, its track's transform applied; zero until the file has loaded.
  private var displaySize = CGSize.zero
  private var loadTask: Task<Void, Never>?
  private var observations: [NSKeyValueObservation] = []
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

  init(frame: CGRect, path: String, loop: Bool, channel: FlutterMethodChannel) {
    self.channel = channel
    self.loop = loop
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    clipsToBounds = true
    isUserInteractionEnabled = false
    playerLayer.videoGravity = .resizeAspectFill
    layer.addSublayer(playerLayer)
    channel.setMethodCallHandler { [weak self] call, result in
      let method = call.method
      guard method == "play" || method == "pause" else {
        result(FlutterMethodNotImplemented)
        return
      }
      MainActor.assumeIsolated { self?.setWantsPlay(method == "play") }
      result(nil)
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
    loadTask = Task { [weak self] in
      do {
        let video = try await SkinVideoHostView.videoOnlyItem(url)
        guard let self, !Task.isCancelled, !self.tornDown else { return }
        self.start(video.item, size: video.size)
      } catch {
        guard let self, !Task.isCancelled, !self.tornDown else { return }
        self.fail(skinVideoFailure(error))
      }
    }
  }

  /// The file's first video track alone in a composition: with no audio track at all, the player has nothing to play
  /// through the app's AVAudioSession, which the video player owns.
  private static func videoOnlyItem(_ url: URL) async throws -> (item: AVPlayerItem, size: CGSize) {
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
    // A track holds its asset weakly.
    let composition = try withExtendedLifetime(asset) {
      try videoComposition(of: track, range: range, transform: transform)
    }
    return (item: AVPlayerItem(asset: composition), size: shown)
  }

  /// Synchronous on purpose: inside an async function, insertTimeRange could resolve to an async overload.
  private static func videoComposition(
    of track: AVAssetTrack, range: CMTimeRange, transform: CGAffineTransform
  ) throws -> AVMutableComposition {
    let composition = AVMutableComposition()
    guard let copy = composition.addMutableTrack(withMediaType: .video,
                                                 preferredTrackID: kCMPersistentTrackID_Invalid) else {
      throw NSError(domain: "SkinVideo.noCompositionTrack", code: 0)
    }
    try copy.insertTimeRange(range, of: track, at: .zero)
    copy.preferredTransform = transform
    return composition
  }

  private func start(_ item: AVPlayerItem, size: CGSize) {
    displaySize = size
    setNeedsLayout()
    let player = AVQueuePlayer()
    player.isMuted = true
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
        DispatchQueue.main.async {
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
        DispatchQueue.main.async {
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
    observations.append(
      playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { @Sendable [weak self] _, change in
        guard change.newValue == true else { return }
        DispatchQueue.main.async {
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
