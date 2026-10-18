import Flutter
import UIKit

/// The link field's paste button for Dart's PasteButton: the system's UIPasteControl, which pastes without the
/// "Allow Paste?" prompt that reading UIPasteboard from code brings up on every tap (the Swift app used SwiftUI's
/// PasteButton). Each view has its own `bilifast/paste_control/<id>` channel: `paste` with the text (empty when
/// none loaded) goes to Dart, `setEnabled` comes from it.
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
    let tint = Self.color((params?["color"] as? NSNumber)?.int64Value ?? 0)
    let enabled = params?["enabled"] as? Bool ?? true
    let channel = FlutterMethodChannel(name: "\(PasteControl.viewType)/\(viewId)", binaryMessenger: messenger)
    let target: PasteTargetView = MainActor.assumeIsolated {
      PasteTargetView(frame: frame, tint: tint, enabled: enabled, channel: channel)
    }
    channel.setMethodCallHandler { [weak target] call, result in
      switch call.method {
      case "setEnabled":
        let enabled = call.arguments as? Bool ?? true
        MainActor.assumeIsolated { target?.setEnabled(enabled) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    return PastePlatformView(target: target, channel: channel)
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
  private let channel: FlutterMethodChannel

  init(target: PasteTargetView, channel: FlutterMethodChannel) {
    self.target = target
    self.channel = channel
    super.init()
  }

  func view() -> UIView {
    target
  }

  /// iOS platform views get no dispose call: the engine releases this object.
  deinit {
    channel.setMethodCallHandler(nil)
  }
}

/// Hosts the control and is its paste target; UIResponder already speaks UIPasteConfigurationSupporting.
final class PasteTargetView: UIView {
  private let control: UIPasteControl
  private let channel: FlutterMethodChannel

  init(frame: CGRect, tint: UIColor, enabled: Bool, channel: FlutterMethodChannel) {
    let configuration = UIPasteControl.Configuration()
    configuration.displayMode = .iconOnly
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = tint
    configuration.baseBackgroundColor = .clear
    control = UIPasteControl(configuration: configuration)
    self.channel = channel
    super.init(frame: frame)
    backgroundColor = .clear
    pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
    control.frame = bounds
    control.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    control.isEnabled = enabled
    control.target = self
    addSubview(control)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setEnabled(_ enabled: Bool) {
    control.isEnabled = enabled
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
