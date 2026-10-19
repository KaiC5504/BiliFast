import 'package:bili_core/devlog.dart';

import 'keychain_store.dart';

/// Writes the cookie jar back to the keychain, one write at a time, each with the jar's latest state
/// (BiliNative `AppEnvironment.swift`). After a failed read nothing is written until a read succeeds or the
/// user logs in or out: a transient keychain failure must not wipe the login.
class CookiePersistence {
  CookiePersistence(this._keychain, {Logger? logger})
    : _logger = logger ?? Logger.shared;

  final KeychainStore _keychain;
  final Logger _logger;
  bool _blocked = false;
  Map<String, String>? _pending;
  Future<bool>? _writing;
  bool _lastWriteOk = true;

  /// Bumped by [unblock]: a read that started before a login or logout answers for cookies that are gone.
  int _generation = 0;

  bool get blocked => _blocked;

  /// The cookies to start the jar with; empty when there are none or the read failed.
  Future<Map<String, String>> load() async => await reload() ?? const {};

  /// As [load], but null when a login or logout came while it read: then neither its cookies nor its failure
  /// (which would block the new login's writes) count.
  Future<Map<String, String>?> reload() async {
    final generation = _generation;
    final loaded = await _keychain.loadCookies();
    if (generation != _generation) return null;
    switch (loaded) {
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
  void unblock() {
    _generation += 1;
    _blocked = false;
  }

  /// Called on every jar change. Changes that arrive while a write runs collapse into one more write. Completes
  /// with whether every write it waited on reached the keychain; false when writes are held back.
  Future<bool> save(Map<String, String> cookies) {
    if (_blocked) return Future.value(false);
    _pending = Map.of(cookies);
    return _writing ??= _drain();
  }

  /// The writes under way, or how the last one went when none is.
  Future<bool> flush() => _writing ?? Future.value(_lastWriteOk);

  Future<bool> _drain() async {
    var ok = true;
    try {
      while (_pending != null && !_blocked) {
        final next = _pending!;
        _pending = null;
        final bool written;
        try {
          written = await _keychain.saveCookies(next);
        } catch (error) {
          _logger.error(LogCategory.app, 'cookie save threw', {
            'error': '$error',
          });
          ok = false;
          continue;
        }
        if (!written) {
          _logger.error(LogCategory.app, 'cookie save refused', {
            'count': next.length,
          });
          ok = false;
        }
      }
    } finally {
      _writing = null;
    }
    _lastWriteOk = ok;
    return ok;
  }
}
