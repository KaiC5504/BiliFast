import Flutter
import WebKit

/// Reads and clears the login web view's cookie store, `WKWebsiteDataStore.default()`, the one webview_flutter's
/// WKWebView uses. Cookie values go back to Dart only, never to a log.
enum WebCookies {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "bilifast/web_cookies", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      // Channel handlers run on the main thread, where WebKit's stores belong.
      MainActor.assumeIsolated {
        switch call.method {
        case "bilibili":
          bilibiliCookies { cookies in
            var byName: [String: String] = [:]
            for cookie in cookies where byName[cookie.name] == nil {
              byName[cookie.name] = cookie.value
            }
            result(byName)
          }
        case "clearBilibili":
          bilibiliCookies { cookies in
            delete(cookies) { result(nil) }
          }
        case "clearAll":
          WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
          ) {
            result(nil)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  @MainActor
  private static func bilibiliCookies(_ done: @escaping ([HTTPCookie]) -> Void) {
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
      done(cookies.filter { isBilibili($0.domain) })
    }
  }

  @MainActor
  private static func delete(_ cookies: [HTTPCookie], then done: @escaping () -> Void) {
    let store = WKWebsiteDataStore.default().httpCookieStore
    let group = DispatchGroup()
    for cookie in cookies {
      group.enter()
      store.delete(cookie) { group.leave() }
    }
    group.notify(queue: .main) { done() }
  }

  /// bilibili.com and its subdomains, as BiliNative's `BiliHosts.isBilibili`.
  private static func isBilibili(_ domain: String) -> Bool {
    var name = domain.lowercased()
    if name.hasPrefix(".") { name.removeFirst() }
    return name == "bilibili.com" || name.hasSuffix(".bilibili.com")
  }
}
