import Flutter
import UIKit

/// The link field's paste button for Dart's PasteButton: the system's UIPasteControl, which pastes without the
/// "Allow Paste?" prompt that reading UIPasteboard from code brings up on every tap (the Swift app used SwiftUI's
/// PasteButton). Each view has its own `bilifast/paste_control/<id>` channel to Dart: `paste` with the text (empty
/// when none loaded), and `layout` once with the room it got against the room it wants.
enum PasteControl {
  static let viewType = "bilifast/paste_control"

  static func register(with registrar: FlutterPluginRegistrar) {
    // The default blocking policy: touches wait for Dart's EagerGestureRecognizer to claim them, then reach the control.
    registrar.register(PasteControlFactory(messenger: registrar.messenger()), withId: viewType)
  }
}

final class PasteControlFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let params = args as? [String: Any]
    let fill = Self.color((params?["fill"] as? NSNumber)?.int64Value ?? 0)
    let glyph = Self.color((params?["glyph"] as? NSNumber)?.int64Value ?? 0xFFFF_FFFF)
    let channel = FlutterMethodChannel(name: "\(PasteControl.viewType)/\(viewId)", binaryMessenger: messenger)
    let target: PasteTargetView = MainActor.assumeIsolated {
      PasteTargetView(frame: frame, fill: fill, glyph: glyph, channel: channel)
    }
    return PastePlatformView(target: target)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  /// Dart's Color.toARGB32().
  private static func color(_ argb: Int64) -> UIColor {
    func component(_ shift: Int64) -> CGFloat { CGFloat((argb >> shift) & 0xFF) / 255 }
    return UIColor(red: component(16), green: component(8), blue: component(0), alpha: component(24))
  }
}

final class PastePlatformView: NSObject, FlutterPlatformView {
  private let target: PasteTargetView

  init(target: PasteTargetView) {
    self.target = target
    super.init()
  }

  func view() -> UIView {
    target
  }
}

/// Hosts the control and is its paste target; UIResponder already speaks UIPasteConfigurationSupporting.
///
/// The control decides for itself when it is enabled (from what the clipboard holds), so Dart never sets isEnabled:
/// forcing it on with nothing to paste brings back the prompt. A disabled PasteButton refuses the touch in Dart.
final class PasteTargetView: UIView {
  private let control: UIPasteControl
  private let channel: FlutterMethodChannel
  private var reportedLayout = false

  init(frame: CGRect, fill: UIColor, glyph: UIColor, channel: FlutterMethodChannel) {
    let configuration = UIPasteControl.Configuration()
    configuration.displayMode = .iconOnly
    configuration.cornerStyle = .capsule
    // Opaque, as the Swift app's PasteButton was: the control checks it can be seen before it pastes.
    configuration.baseBackgroundColor = fill
    configuration.baseForegroundColor = glyph
    control = UIPasteControl(configuration: configuration)
    self.channel = channel
    super.init(frame: frame)
    backgroundColor = .clear
    pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
    control.frame = bounds
    control.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // A control squeezed below the size it wants turns itself off; large Dynamic Type would make it want more
    // than the 34 pt field has.
    control.maximumContentSizeCategory = .large
    control.target = self
    addSubview(control)
    // After a copy in another app the control can keep its old clipboard state until its target is set again.
    NotificationCenter.default.addObserver(
      self, selector: #selector(reattach), name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func reattach() {
    control.target = nil
    control.target = self
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard !reportedLayout, bounds.width > 0 else { return }
    reportedLayout = true
    // The intrinsic size settles a moment after the first layout.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      guard let self else { return }
      let wanted = self.control.intrinsicContentSize
      self.channel.invokeMethod("layout", arguments: [
        "width": Double(self.bounds.width), "height": Double(self.bounds.height),
        "wantedWidth": Double(wanted.width), "wantedHeight": Double(wanted.height),
      ])
    }
  }

  override func paste(itemProviders: [NSItemProvider]) {
    let channel = self.channel
    guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
      channel.invokeMethod("paste", arguments: "")
      return
    }
    // The completion runs on a background queue; channels are called on the main thread.
    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
      let text = (object as? NSString).map { $0 as String } ?? ""
      DispatchQueue.main.async { channel.invokeMethod("paste", arguments: text) }
    }
  }
}
