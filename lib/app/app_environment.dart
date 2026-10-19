import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';

import '../account/cookie_persistence.dart';
import '../account/keychain_store.dart';
import '../account/web_cookies.dart';

sealed class Account {
  const Account();
}

final class AccountUnknown extends Account {
  const AccountUnknown();
}

final class LoggedOut extends Account {
  const LoggedOut();
}

final class LoggedIn extends Account {
  const LoggedIn({required this.name, required this.vip});

  final String name;
  final bool vip;
}

/// Cookies exist but Bilibili no longer accepts them (nav answered isLogin false).
final class LoginExpired extends Account {
  const LoginExpired();
}

/// The keychain login, the cookie jar and the API client (port of AppEnvironment.swift's account half). On the
/// iPhone the jar starts from the Swift app's keychain item, so the app opens logged in with no login screen;
/// Windows has no keychain and runs logged out.
class AppEnvironment extends ChangeNotifier {
  AppEnvironment._(
      {required this.cookies,
      required this.client,
      required this._persistence,
      required this._keychain,
      required this.webCookies,
      required this._logger});

  /// `http`, `httpFactory`, `keychain` and `webCookies` are for tests; the app passes none.
  static Future<AppEnvironment> load(
      {KeychainStore? keychain,
      WebCookies? webCookies,
      HTTPTransport? http,
      HTTPTransport Function() httpFactory = platformHttpTransport,
      Logger? logger}) async {
    final log = logger ?? Logger.shared;
    final guarded = _GuardedKeychain(keychain ?? KeychainStore.platform(), log);
    final persistence = CookiePersistence(guarded, logger: log);
    final jar = CookieJar(await persistence.load());
    if (persistence.blocked) log.warn(LogCategory.app, 'keychain read failed, cookie writes held back');
    jar.onChange = (_) => unawaited(persistence.save(jar.all));
    final client = BiliClient(transport: http ?? httpTransportOrFallback(httpFactory, log), cookies: jar, logger: log);
    return AppEnvironment._(
        cookies: jar,
        client: client,
        persistence: persistence,
        keychain: guarded,
        webCookies: webCookies ?? WebCookies.platform(),
        logger: log);
  }

  final CookieJar cookies;
  final BiliClient client;
  final CookiePersistence _persistence;
  final KeychainStore _keychain;

  /// The login web view's store, read by the login page and cleared on logout.
  final WebCookies webCookies;
  final Logger _logger;
  Account _account = const AccountUnknown();
  int? _mid;
  String? _face;
  bool _accountCheckFailed = false;

  Account get account => _account;

  /// The logged-in account's uid.
  int? get mid => _mid;

  /// The logged-in account's avatar URL.
  String? get face => _face;

  /// The last nav call failed (network, not a verdict), so [account] is still unknown.
  bool get accountCheckFailed => _accountCheckFailed;

  /// Counts the logins [didLogin] completed. A login over an account that already read logged in leaves [account]
  /// where it was, so what belongs to the account listens here rather than to its changes.
  ValueListenable<int> get logins => _logins;
  final _logins = ValueNotifier<int>(0);

  String get accountLabel => switch (_account) {
        LoggedIn(:final name) => name.isEmpty ? '已登录' : name,
        LoggedOut() => '未登录',
        LoginExpired() => '登录已失效',
        AccountUnknown() => _accountCheckFailed ? '账号确认失败' : '正在确认账号…',
      };

  /// Returns false when Bilibili could not be asked (network error); [account] then keeps its last value. A check
  /// already running answers every caller (launch, coming back to the app, returning to home) with one request.
  Future<bool> refreshAccount() {
    if (_fake) return Future.value(true);
    if (_checking case final running?) return running;
    late final Future<bool> check;
    check = _checkAccount().whenComplete(() {
      if (identical(_checking, check)) _checking = null;
    });
    return _checking = check;
  }

  bool _fake = false;

  /// A `--fake-account` run on the PC: logged in as a made-up 测试账号 with mid 1, so the page's actions can be pressed
  /// against the in-memory `FakePageApi`. No call goes out as this account, and nothing reports watch progress.
  bool get fake => _fake;

  void useFakeAccount() {
    _fake = true;
    _account = const LoggedIn(name: '测试账号', vip: false);
    _mid = 1;
    _face = null;
    notifyListeners();
  }

  Future<bool>? _checking;

  /// Bumped by every login and logout, so a check already on its way answers for cookies that are gone.
  int _epoch = 0;

  /// The login page's cookies once Bilibili set SESSDATA (BiliNative `AppEnvironment.didLogin`): they join the jar
  /// and the keychain, and the account is checked again, up to 3 times. Completes with whether it is now logged in.
  Future<bool> didLogin(Map<String, String> cookies) async {
    final epoch = ++_epoch;
    _checking = null;
    _fake = false;
    _persistence.unblock();
    this.cookies.replaceAll({...this.cookies.all, ...cookies});
    final saved = _persistence.flush();
    _account = const AccountUnknown();
    _accountCheckFailed = false;
    notifyListeners();
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(seconds: attempt));
      if (epoch != _epoch) break;
      await refreshAccount();
      if (_account is LoggedIn) break;
    }
    final loggedIn = _account is LoggedIn;
    _logger.info(LogCategory.app, 'login', {'count': cookies.length, 'loggedIn': loggedIn});
    // The session works from the jar either way; only the next launch would find itself logged out.
    if (!await saved) _logger.error(LogCategory.app, 'login not saved to the keychain', {'loggedIn': loggedIn});
    if (loggedIn && epoch == _epoch) _logins.value += 1;
    return loggedIn;
  }

  /// 退出登录 (BiliNative `AppEnvironment.logout`): empties the jar, deletes the keychain cookies and app token, and
  /// clears the web view's data. A step that fails is logged and the rest still run. A `--fake-account` run, which
  /// stored nothing, just stops being fake.
  ///
  /// Throws [LogoutIncomplete] when the jar or the keychain cookies couldn't be emptied. The account still reads
  /// logged out, which is true of this run (the jar sends no login), but the keychain may hold the login for the
  /// next launch, so the caller hears of it instead of a logout that only seemed to work.
  Future<void> logout() async {
    _epoch += 1;
    _checking = null;
    if (_fake) {
      _fake = false;
      _signedOut();
      return;
    }
    _persistence.unblock();
    final jarEmptied = await _logoutStep('jar', () async => cookies.removeAll());
    final keychainEmptied = await _logoutStep('keychain cookies', _keychain.deleteCookies);
    await _logoutStep('app token', _keychain.deleteAppToken);
    await _logoutStep('web data', webCookies.clearAll);
    _signedOut();
    // The fingerprint cookies went with the jar, and the web API answers 412 without them.
    unawaited(client.ensureRiskCookies().catchError((Object error) {
      _logger.warn(LogCategory.app, 'risk cookies failed', {'error': '$error'});
    }));
    if (!jarEmptied || !keychainEmptied) throw const LogoutIncomplete();
  }

  Future<bool> _logoutStep(String step, Future<void> Function() run) async {
    try {
      await run();
      return true;
    } catch (error) {
      _logger.warn(LogCategory.app, 'logout step failed', {'step': step, 'error': '$error'});
      return false;
    }
  }

  void _signedOut() {
    _account = const LoggedOut();
    _accountCheckFailed = false;
    _mid = null;
    _face = null;
    _logger.info(LogCategory.app, 'logout');
    notifyListeners();
  }

  Future<bool> _checkAccount() async {
    final epoch = _epoch;
    await _retryBlockedKeychainLoad(epoch);
    try {
      await client.ensureRiskCookies();
      final nav = await client.nav();
      if (epoch != _epoch) return true;
      _accountCheckFailed = false;
      if (nav.isLogin) {
        _account = LoggedIn(name: nav.uname ?? '', vip: nav.isVip);
        _mid = nav.mid;
        _face = nav.face;
        final mid = nav.mid;
        _logger.info(LogCategory.app, 'account', {'user': mid == null ? '?' : Redactor.mid(mid), 'vip': nav.isVip});
      } else {
        _account = cookies.value('SESSDATA') == null ? const LoggedOut() : const LoginExpired();
        _mid = null;
        _face = null;
        _logger.info(LogCategory.app, 'account', {'user': 'none', 'expired': _account is LoginExpired});
      }
      notifyListeners();
      return true;
    } catch (error) {
      _logger.warn(LogCategory.app, 'nav failed', {'error': '$error'});
      if (epoch != _epoch) return false;
      if (_account is AccountUnknown) {
        if (cookies.value('SESSDATA') == null) {
          _account = const LoggedOut();
        } else {
          _accountCheckFailed = true;
        }
      }
      notifyListeners();
      return false;
    }
  }

  /// After a failed read the stored cookies may still be there; once a read works they join the jar.
  Future<void> _retryBlockedKeychainLoad(int epoch) async {
    if (!_persistence.blocked) return;
    final stored = await _persistence.reload();
    if (stored == null || _persistence.blocked || epoch != _epoch) return;
    cookies.replaceAll({...stored, ...cookies.all});
  }

  @override
  void dispose() {
    _logins.dispose();
    super.dispose();
  }
}

/// [AppEnvironment.logout] couldn't empty the jar or delete the keychain's cookies.
final class LogoutIncomplete implements Exception {
  const LogoutIncomplete();

  @override
  String toString() => 'LogoutIncomplete';
}

/// URLSession on the iPhone, as the Swift app's API client: ephemeral, with its own cookie store off, since
/// the jar sets the Cookie header. dart:io elsewhere.
HTTPTransport platformHttpTransport() {
  if (!Platform.isIOS) return ClientHTTPTransport();
  final configuration = URLSessionConfiguration.ephemeralSessionConfiguration()
    ..httpShouldSetCookies = false
    ..httpCookieAcceptPolicy = NSHTTPCookieAcceptPolicy.NSHTTPCookieAcceptPolicyNever
    ..timeoutIntervalForRequest = const Duration(seconds: 15);
  return ClientHTTPTransport(client: CupertinoClient.fromSessionConfiguration(configuration));
}

/// cupertino_http reaches URLSession through native bindings that can fail to load; the app then talks to
/// Bilibili over dart:io rather than not starting.
HTTPTransport httpTransportOrFallback(HTTPTransport Function() make, Logger logger) {
  try {
    return make();
  } catch (error) {
    logger.error(LogCategory.app, 'http transport failed, using dart:io', {'error': '$error'});
    return ClientHTTPTransport();
  }
}

/// A keychain channel that throws (no native side yet, a platform error) counts as a failed read, so the
/// write block keeps a login that may still be stored.
final class _GuardedKeychain implements KeychainStore {
  const _GuardedKeychain(this._inner, this._logger);

  final KeychainStore _inner;
  final Logger _logger;

  @override
  Future<CookieLoad> loadCookies() async {
    try {
      return await _inner.loadCookies();
    } catch (error) {
      _logger.error(LogCategory.app, 'keychain read threw', {'error': '$error'});
      return const CookieLoadFailed(-1);
    }
  }

  @override
  Future<bool> saveCookies(Map<String, String> cookies) => _inner.saveCookies(cookies);

  @override
  Future<void> deleteCookies() => _inner.deleteCookies();

  @override
  Future<String?> loadAppToken() => _inner.loadAppToken();

  @override
  Future<bool> saveAppToken(String token) => _inner.saveAppToken(token);

  @override
  Future<void> deleteAppToken() => _inner.deleteAppToken();
}
