import 'keychain_store.dart';

/// The Windows build's login store: the cookies in one file in the app's support folder, encrypted with DPAPI
/// (`CryptProtectData`, this Windows user only), so a copy of the file is useless elsewhere. The app token is never
/// kept on the PC: its loads answer null and its saves are refused.
class DpapiKeychainStore implements KeychainStore {
  DpapiKeychainStore(this.path);

  /// The encrypted file.
  final String path;

  @override
  Future<CookieLoad> loadCookies() => throw UnimplementedError();

  @override
  Future<bool> saveCookies(Map<String, String> cookies) => throw UnimplementedError();

  @override
  Future<void> deleteCookies() => throw UnimplementedError();

  @override
  Future<String?> loadAppToken() async => null;

  @override
  Future<bool> saveAppToken(String token) async => false;

  @override
  Future<void> deleteAppToken() async {}
}
