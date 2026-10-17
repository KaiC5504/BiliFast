import 'package:bilifast/account/keychain_store.dart';

/// Hands out [next] (or throws [throws]) and records every write.
class FakeKeychain implements KeychainStore {
  FakeKeychain(this.next);

  CookieLoad next;
  Object? throws;
  final saved = <Map<String, String>>[];

  @override
  Future<CookieLoad> loadCookies() async {
    final error = throws;
    if (error != null) throw error;
    return next;
  }

  @override
  Future<bool> saveCookies(Map<String, String> cookies) async {
    saved.add(cookies);
    return true;
  }

  @override
  Future<void> deleteCookies() async {}
  @override
  Future<String?> loadAppToken() async => null;
  @override
  Future<bool> saveAppToken(String token) async => true;
  @override
  Future<void> deleteAppToken() async {}
}
