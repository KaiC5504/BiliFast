import 'keychain_store.dart';

/// Writes the cookie jar back to the keychain, one write at a time, each with the jar's latest state
/// (BiliNative `AppEnvironment.swift`). After a failed read nothing is written until a read succeeds or the
/// user logs in or out: a transient keychain failure must not wipe the login.
class CookiePersistence {
  CookiePersistence(this._keychain);

  final KeychainStore _keychain;
  bool _blocked = false;
  Map<String, String>? _pending;
  Future<void>? _writing;

  bool get blocked => _blocked;

  /// The cookies to start the jar with; empty when there are none or the read failed.
  Future<Map<String, String>> load() async {
    switch (await _keychain.loadCookies()) {
      case StoredCookies(:final cookies):
        _blocked = false;
        return cookies;
      case NoStoredCookies():
        _blocked = false;
        return const {};
      case CookieLoadFailed():
        _blocked = true;
        return const {};
    }
  }

  /// A login or logout is a verdict on the account, so it may overwrite whatever the keychain holds.
  void unblock() => _blocked = false;

  /// Called on every jar change. Changes that arrive while a write runs collapse into one more write.
  Future<void> save(Map<String, String> cookies) {
    if (_blocked) return Future.value();
    _pending = Map.of(cookies);
    return _writing ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_pending != null && !_blocked) {
        final next = _pending!;
        _pending = null;
        await _keychain.saveCookies(next);
      }
    } finally {
      _writing = null;
    }
  }
}
