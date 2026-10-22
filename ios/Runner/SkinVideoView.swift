import Flutter
import UIKit

/// The 我的 header's `head_myself_mp4_bg` for Dart's SkinVideo: a muted video from a file in the support folder,
/// looping or played once (`path`, `loop`). Only the video track is played, so it never activates the audio session.
enum SkinVideoView {
  static let viewType = "bilifast/skin_video"

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(SkinVideoFactory(), withId: viewType)
  }
}

final class SkinVideoFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    SkinVideoPlatformView(frame: frame)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class SkinVideoPlatformView: NSObject, FlutterPlatformView {
  private let host: UIView

  init(frame: CGRect) {
    host = MainActor.assumeIsolated { UIView(frame: frame) }
    super.init()
  }

  func view() -> UIView {
    host
  }
}
