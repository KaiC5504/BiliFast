import 'dart:async';

import 'package:bilifast/account/keychain_store.dart';

/// Hands out [next] (or throws [throws]), after [loadGate] when one is set, and records every write, answering
/// [saveOk].
class FakeKeychain implements KeychainStore {
  FakeKeychain(this.next);

  CookieLoad next;
  Object? throws;
  Completer<void>? loadGate;
  bool saveOk = true;
  final saved = <Map<String, String>>[];

  @override
  Future<CookieLoad> loadCookies() async {
    await loadGate?.future;
    final error = throws;
    if (error != null) throw error;
    return next;
  }

  @override
  Future<bool> saveCookies(Map<String, String> cookies) async {
    saved.add(cookies);
    return saveOk;
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
