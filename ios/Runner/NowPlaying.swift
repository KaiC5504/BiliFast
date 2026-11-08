import AVFoundation
import MediaPlayer

/// 后台听视频's background policy per player, and the lock screen and Control Center for the player now playing
/// (MPNowPlayingSession): its title, uploader and cover, its remote commands, and audio interruptions.
@MainActor
enum NowPlaying {
  static func setBackgroundPlayback(_ player: NativePlayer, enabled: Bool) {}

  static func set(_ player: NativePlayer, info: NativeNowPlaying?) {}
}
