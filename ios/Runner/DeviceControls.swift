import AVFoundation
import MediaPlayer
import UIKit

/// Brightness and the system volume for the full-screen level gestures (BiliNative `Player/DeviceControls.swift`).
@MainActor
enum DeviceControls {
  static var brightness: Double {
    get { Double(screen?.brightness ?? 0.5) }
    set { screen?.brightness = CGFloat(min(max(newValue, 0), 1)) }
  }

  static func volume() -> Double {
    Double(AVAudioSession.sharedInstance().outputVolume)
  }

  /// A volume change made with the hardware buttons while the volume view hides the system HUD.
  static var hardwareVolumeChanged: ((Double) -> Void)?

  /// A hidden MPVolumeView's slider is the only public way to set the system volume. While that view sits in
  /// the window iOS also leaves out its own volume HUD, so it is there only in full screen, where the player's
  /// indicator takes the HUD's place; inline the buttons show the system HUD as usual.
  static func attachVolumeView() {
    attached = true
    _ = attachedSlider()
    observeVolume()
  }

  static func detachVolumeView() {
    attached = false
    volumeObservation?.invalidate()
    volumeObservation = nil
    volumeView?.removeFromSuperview()
    volumeView = nil
  }

  /// False only when the volume view is up and has no slider to move; detached, it does nothing.
  static func setVolume(_ value: Double) -> Bool {
    guard attached else { return true }
    let level = Float(min(max(value, 0), 1))
    lastOwnVolumeChange = Date()
    let (slider, fresh) = attachedSlider()
    guard let slider else { return false }
    // A slider that has only just joined the window ignores a value set in the same run loop turn.
    if fresh {
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(50))
        guard attached, slider.window != nil else { return }
        lastOwnVolumeChange = Date()
        slider.value = level
      }
    } else {
      slider.value = level
    }
    return true
  }

  private static var attached = false
  private static var volumeView: MPVolumeView?
  private static var volumeObservation: NSKeyValueObservation?
  private static var lastOwnVolumeChange: Date?

  private static func observeVolume() {
    guard volumeObservation == nil else { return }
    // KVO calls back on an audio thread, so the handler must not be main-actor isolated.
    let session = AVAudioSession.sharedInstance()
    volumeObservation = session.observe(\.outputVolume, options: [.new]) { @Sendable _, change in
      guard let value = change.newValue else { return }
      Task { @MainActor in DeviceControls.volumeChanged(Double(value)) }
    }
  }

  private static func volumeChanged(_ value: Double) {
    guard volumeObservation != nil else { return }
    // The system reports our own slider moves too, a little after the drag set them.
    if let last = lastOwnVolumeChange, Date().timeIntervalSince(last) < 0.5 { return }
    hardwareVolumeChanged?(value)
  }

  /// Puts the volume view back if it has lost its window; `fresh` says the slider has only just joined one.
  private static func attachedSlider() -> (UISlider?, fresh: Bool) {
    if let volumeView, volumeView.window != nil {
      return (slider(in: volumeView), false)
    }
    guard let window = keyWindow else { return (nil, false) }
    volumeView?.removeFromSuperview()
    // Inside the window's bounds: a view placed off screen may no longer keep the system HUD away.
    let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    // 0.01, not 0 or hidden: an invisible MPVolumeView no longer keeps the system HUD away.
    view.alpha = 0.01
    view.isUserInteractionEnabled = false
    window.addSubview(view)
    volumeView = view
    return (slider(in: view), true)
  }

  private static func slider(in view: UIView) -> UISlider? {
    for subview in view.subviews {
      if let slider = subview as? UISlider { return slider }
      if let slider = slider(in: subview) { return slider }
    }
    return nil
  }

  private static var screen: UIScreen? {
    keyWindow?.windowScene?.screen
  }

  private static var keyWindow: UIWindow? {
    let scene = DeviceChannel.scene
    return scene?.keyWindow ?? scene?.windows.first
  }
}
