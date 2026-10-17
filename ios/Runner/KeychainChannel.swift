import Flutter
import Foundation
import Security

/// The Swift BiliFast's keychain items, read and written in exactly its format (BiliNative
/// `Account/KeychainStore.swift`, `AppTokenStore.swift`), so the login carries over in both directions.
/// Values never cross into logs: errors report only the OSStatus.
enum KeychainChannel {
  private static let cookieService = "com.kaichuan.bilinative.cookies"
  private static let tokenService = "com.kaichuan.bilinative.apptoken"
  private static let account = "bilibili"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "bilifast/keychain", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "loadCookies":
        result(loadCookies())
      case "saveCookies":
        let cookies = arguments?["cookies"] as? [String: String] ?? [:]
        result(saveCookies(cookies))
      case "deleteCookies":
        SecItemDelete(query(cookieService) as CFDictionary)
        result(nil)
      case "loadAppToken":
        result(loadAppToken())
      case "saveAppToken":
        result(saveAppToken(arguments?["token"] as? String ?? ""))
      case "deleteAppToken":
        SecItemDelete(query(tokenService) as CFDictionary)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func query(_ service: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  private static func load(_ service: String) -> (OSStatus, Data?) {
    var q = query(service)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &item)
    return (status, item as? Data)
  }

  /// errSecInteractionNotAllowed before the first unlock is a failure, not "logged out": the stored
  /// cookies may still be there, and the Dart side then blocks writes so it can't wipe them.
  private static func loadCookies() -> [String: Any] {
    let (status, data) = load(cookieService)
    if status == errSecItemNotFound { return ["status": "notFound"] }
    guard status == errSecSuccess else { return ["status": "failed", "code": Int(status)] }
    guard let data,
          let cookies = try? JSONDecoder().decode([String: String].self, from: data) else {
      return ["status": "failed", "code": Int(errSecDecode)]
    }
    return ["status": "cookies", "cookies": cookies]
  }

  private static func saveCookies(_ cookies: [String: String]) -> [String: Any] {
    if cookies.isEmpty {
      SecItemDelete(query(cookieService) as CFDictionary)
      return ["ok": true]
    }
    guard let data = try? JSONEncoder().encode(cookies) else {
      return ["ok": false, "code": Int(errSecParam)]
    }
    return save(data, service: cookieService)
  }

  private static func loadAppToken() -> [String: Any] {
    let (status, data) = load(tokenService)
    guard status == errSecSuccess else {
      return status == errSecItemNotFound ? [:] : ["code": Int(status)]
    }
    guard let data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { return [:] }
    return ["token": token]
  }

  private static func saveAppToken(_ token: String) -> [String: Any] {
    guard !token.isEmpty else {
      SecItemDelete(query(tokenService) as CFDictionary)
      return ["ok": true]
    }
    return save(Data(token.utf8), service: tokenService)
  }

  private static func save(_ data: Data, service: String) -> [String: Any] {
    let attributes: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    var status = SecItemUpdate(query(service) as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(query(service).merging(attributes) { $1 } as CFDictionary, nil)
    }
    return status == errSecSuccess ? ["ok": true] : ["ok": false, "code": Int(status)]
  }
}
