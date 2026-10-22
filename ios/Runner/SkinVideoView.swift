import AVFoundation
import Flutter
import UIKit

/// The 我的 header's `head_myself_mp4_bg` for Dart's SkinVideo: a muted video from a file in the support folder,
/// looping or played once (`path`, `loop`). Only the video track is played, so it never activates the audio session.
///
/// Each view has its own `bilifast/skin_video/<id>` channel: Dart sends `play` and `pause` (a new view waits paused),
/// the view sends `ready` once its first frame shows and `failed` with a reason when the file won't play.
enum SkinVideoView {
  static let viewType = "bilifast/skin_video"

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(SkinVideoFactory(messenger: registrar.messenger()), withId: viewType)
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

/// The video's layer, filling the view as the header's picture does. It takes no touches.
final class SkinVideoHostView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

  private let channel: FlutterMethodChannel
  private let loop: Bool
  private var player: AVQueuePlayer?
  private var looper: AVPlayerLooper?
  private var loadTask: Task<Void, Never>?
  private var readyObservation: NSKeyValueObservation?
  private var endToken: NSObjectProtocol?
  /// What Dart last asked for; going to the background pauses without changing it.
  private var wantsPlay = false
  private var finished = false
  private var reportedReady = false
  private var tornDown = false

  init(frame: CGRect, path: String, loop: Bool, channel: FlutterMethodChannel) {
    self.channel = channel
    self.loop = loop
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    clipsToBounds = true
    isUserInteractionEnabled = false
    playerLayer.videoGravity = .resizeAspectFill
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

  func tearDown() {
    guard !tornDown else { return }
    tornDown = true
    channel.setMethodCallHandler(nil)
    NotificationCenter.default.removeObserver(self)
    loadTask?.cancel()
    loadTask = nil
    readyObservation?.invalidate()
    readyObservation = nil
    if let endToken { NotificationCenter.default.removeObserver(endToken) }
    endToken = nil
    looper?.disableLooping()
    looper = nil
    player?.pause()
    player?.removeAllItems()
    player = nil
    playerLayer.player = nil
  }

  private func loadVideo(_ url: URL) {
    loadTask = Task { [weak self] in
      do {
        let item = try await SkinVideoHostView.videoOnlyItem(url)
        guard let self, !Task.isCancelled, !self.tornDown else { return }
        self.start(item)
      } catch {
        guard let self, !Task.isCancelled, !self.tornDown else { return }
        let nsError = error as NSError
        self.channel.invokeMethod("failed", arguments: "\(nsError.domain) \(nsError.code)")
      }
    }
  }

  /// The file's video tracks alone in a composition: with no audio track at all, the player has nothing to play
  /// through the app's AVAudioSession, which the video player owns.
  private static func videoOnlyItem(_ url: URL) async throws -> AVPlayerItem {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard !tracks.isEmpty else {
      throw NSError(domain: "SkinVideo.noVideoTrack", code: 0)
    }
    var parts: [(track: AVAssetTrack, range: CMTimeRange, transform: CGAffineTransform)] = []
    for track in tracks {
      let range = try await track.load(.timeRange)
      let transform = try await track.load(.preferredTransform)
      parts.append((track: track, range: range, transform: transform))
    }
    // A track holds its asset weakly.
    let composition = try withExtendedLifetime(asset) { try videoComposition(of: parts) }
    return AVPlayerItem(asset: composition)
  }

  /// Synchronous on purpose: inside an async function, insertTimeRange could resolve to an async overload.
  private static func videoComposition(
    of parts: [(track: AVAssetTrack, range: CMTimeRange, transform: CGAffineTransform)]
  ) throws -> AVMutableComposition {
    let composition = AVMutableComposition()
    for part in parts {
      guard let copy = composition.addMutableTrack(withMediaType: .video,
                                                   preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
      try copy.insertTimeRange(part.range, of: part.track, at: .zero)
      copy.preferredTransform = part.transform
    }
    return composition
  }

  private func start(_ item: AVPlayerItem) {
    let player = AVQueuePlayer()
    player.isMuted = true
    player.allowsExternalPlayback = false
    player.preventsDisplaySleepDuringVideoPlayback = false
    if loop {
      looper = AVPlayerLooper(player: player, templateItem: item)
    } else {
      player.actionAtItemEnd = .pause
      player.insert(item, after: nil)
      endToken = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                        object: item, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.finished = true }
      }
    }
    self.player = player
    playerLayer.player = player
    readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, change in
      guard change.newValue == true else { return }
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.firstFrameShown() }
      }
    }
    if wantsPlay && UIApplication.shared.applicationState != .background { player.play() }
  }

  private func firstFrameShown() {
    guard !reportedReady, !tornDown else { return }
    reportedReady = true
    channel.invokeMethod("ready", arguments: nil)
  }

  private func setWantsPlay(_ play: Bool) {
    wantsPlay = play
    guard let player else { return }
    if play {
      // Played once, it holds its last frame.
      if !finished { player.play() }
    } else {
      player.pause()
    }
  }

  @objc private func didEnterBackground() {
    player?.pause()
  }

  @objc private func willEnterForeground() {
    guard wantsPlay, !finished else { return }
    player?.play()
  }
}
