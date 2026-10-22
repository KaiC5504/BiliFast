import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    } catch {
      print("audio session category failed: \(error)")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Full screen is the same page rotated, so the app turns only when Dart's DeviceChannel allows it. An override:
  /// Swift mirrors UIApplicationDelegate's methods onto FlutterAppDelegate, which adopts the protocol, as with
  /// didFinishLaunchingWithOptions above.
  override func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    MainActor.assumeIsolated { DeviceChannel.mask }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeychainChannel") {
      KeychainChannel.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PlayerChannel") {
      PlayerChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LogServerDiscovery") {
      LogServerDiscovery.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PasteControl") {
      PasteControl.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SkinVideoView") {
      SkinVideoView.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LegacyDefaults") {
      LegacyDefaults.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceChannel") {
      DeviceChannel.register(with: registrar.messenger())
      MainActor.assumeIsolated { NetworkMonitor.start() }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WebCookies") {
      WebCookies.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PictureDecoder") {
      PictureDecoder.register(with: registrar.messenger())
    }
  }
}
