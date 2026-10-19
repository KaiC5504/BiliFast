import Flutter
import WebKit

/// Reads and clears the login web view's cookie store, `WKWebsiteDataStore.default()`, the one webview_flutter's
/// WKWebView uses. Cookie values go back to Dart only, never to a log.
enum WebCookies {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "bilifast/web_cookies", binaryMessenger: messenger)
    channel.setMethodCallHandler { _, result in
      result(FlutterMethodNotImplemented)
    }
  }
}
