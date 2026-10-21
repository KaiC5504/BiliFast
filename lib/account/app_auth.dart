import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' show Random;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../app/app_environment.dart';
import '../home/feed_model.dart' show requestFailureMessage;
import '../playback/playback_setup.dart' show supportFilePath;
import '../shared/toast.dart';
import 'app_auth_page.dart';
import 'app_auth_prompt.dart';

/// The official API's login, the app token (PiliPlus's `access_key`): loaded at launch, got by one confirm with the
/// web login's cookies, renewed once near its end, dropped on 退出登录 or when Bilibili rejects it. What needs it
/// calls [request] rather than failing.
abstract interface class AppAuth implements Listenable {
  bool get authorized;

  /// When the token runs out; null without one.
  DateTime? get expiresAt;

  /// Launch: the stored token (renewed if due, one call), and the confirm asked once when logged in without one.
  Future<void> start();

  /// Asks for the confirm, completing with whether a token is held now. One already up answers every caller.
  Future<bool> request(BuildContext context);

  /// 开发者's 重新授权: drops the token and asks again.
  Future<bool> reauthorize(BuildContext context);

  void dispose();
}

/// Tests' default: never authorized, and asking gets nothing.
class NoAppAuth extends ChangeNotifier implements AppAuth {
  @override
  bool get authorized => false;

  @override
  DateTime? get expiresAt => null;

  @override
  Future<void> start() async {}

  @override
  Future<bool> request(BuildContext context) async => false;

  @override
  Future<bool> reauthorize(BuildContext context) async => false;
}

/// `--fake-account`: authorized from the start, so 不喜欢 can be pressed against `FakePageApi`.
class FakeAppAuth extends ChangeNotifier implements AppAuth {
  FakeAppAuth({this.authorized = true});

  @override
  bool authorized;

  @override
  DateTime? get expiresAt => authorized ? DateTime.now().add(const Duration(days: 180)) : null;

  @override
  Future<void> start() async {}

  @override
  Future<bool> request(BuildContext context) async {
    authorized = true;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> reauthorize(BuildContext context) => request(context);
}

/// Where the official calls' device id is kept.
String? appDevicePath() => supportFilePath('app_device.json');

/// The phone's: the token in the keychain's app-token item (its JSON, expiry included), set on
/// [AppEnvironment.client]. A launch only compares dates; the one renewal call goes out within
/// [AppToken.renewWithin] of the end. A token that is rejected or runs out is dropped and the confirm asked again.
class TokenAppAuth extends ChangeNotifier implements AppAuth {
  TokenAppAuth({
    required this.environment,
    required this.navigator,
    this.confirm = showAppAuthPrompt,
    this.confirmPage = AppAuthPage.route,
    this.devicePath = appDevicePath,
    DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 1),
    this.pagePollInterval = const Duration(seconds: 2),
    this.pageTimeout = const Duration(minutes: 2),
    Logger? logger,
  }) : _now = now ?? DateTime.now,
       _logger = logger ?? Logger.shared;

  final AppEnvironment environment;

  /// For the launch's confirm, which no page asks for.
  final GlobalKey<NavigatorState> navigator;

  /// Asks before anything is sent, completing with whether 授权 was pressed.
  final Future<bool> Function(BuildContext context) confirm;

  /// Bilibili's own confirm page, opened when the confirm call is refused.
  final Route<bool> Function(Uri url, Map<String, String> cookies) confirmPage;

  /// Null keeps the device id for this launch only.
  final String? Function() devicePath;

  /// Between the polls after the confirm call, which should find the token at once.
  final Duration pollInterval;

  /// Between the polls while [confirmPage] is up, for at most [pageTimeout] (the code itself lasts 180 s).
  final Duration pagePollInterval;
  final Duration pageTimeout;

  final DateTime Function() _now;
  final Logger _logger;

  /// Polls after a confirm call that went through: under 10, so a confirm the poll never sees can't loop.
  static const quickPolls = 5;

  /// Polls in a row that may fail to reach Bilibili while the page is up.
  static const pageFailuresAllowed = 5;

  static final _buvidShape = RegExp(r'^XY[0-9A-F]{35}$');

  /// PiliPlus's buvid: XY, three of the digits again, then 16 random bytes in upper-case hex.
  static String newBuvid([Random? random]) {
    final source = random ?? Random.secure();
    final hex = [
      for (var i = 0; i < 16; i++) source.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join().toUpperCase();
    return 'XY${hex[2]}${hex[12]}${hex[22]}$hex';
  }

  bool _started = false;
  bool _disposed = false;
  bool _launchAsked = false;
  bool _rejectionAsked = false;
  bool _loginUnderway = false;

  /// The keychain threw on the read, so a token may well be stored: the launch doesn't ask for another.
  bool _storeUnreadable = false;
  Future<bool>? _request;

  BiliClient get _client => environment.client;

  @override
  bool get authorized => _client.appToken != null;

  @override
  DateTime? get expiresAt => _client.appToken?.expiresAt;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _client.onAppTokenRejected = _rejected;
    _client.appBuvid = await _deviceId();
    var token = await _stored();
    if (_disposed) return;
    final now = _now();
    if (token != null && token.expired(now)) {
      _logger.info(LogCategory.app, 'app token dropped', {'reason': 'expired'});
      await _deleteStored();
      token = null;
    }
    if (token != null) {
      _client.appToken = token;
      notifyListeners();
      _logger.info(LogCategory.app, 'app token', {'days': _daysLeft(token, now)});
      if (token.dueForRenewal(now)) await _renew();
    }
    if (_disposed) return;
    environment.addListener(_accountChanged);
    environment.logins.addListener(_loggedIn);
    if (environment.account is! AccountUnknown) _accountChanged();
  }

  @override
  Future<bool> request(BuildContext context) {
    if (_request case final running?) return running;
    late final Future<bool> asked;
    asked = _ask(context).whenComplete(() {
      if (identical(_request, asked)) _request = null;
    });
    return _request = asked;
  }

  @override
  Future<bool> reauthorize(BuildContext context) {
    if (_request case final running?) return running;
    if (authorized) unawaited(_drop('reauthorize'));
    return request(context);
  }

  Future<bool> _ask(BuildContext context) async {
    if (environment.account is! LoggedIn) return false;
    final pages = Navigator.maybeOf(context, rootNavigator: true);
    if (!await confirm(context)) {
      _logger.info(LogCategory.app, 'app auth declined');
      return authorized;
    }
    _logger.info(LogCategory.app, 'app auth asked');
    try {
      final token = await _fetch(pages);
      if (token == null) {
        _logger.info(LogCategory.app, 'app auth closed');
        return authorized;
      }
      await _hold(token);
      _logger.info(LogCategory.app, 'app auth done', {'days': _daysLeft(token, _now())});
      _toast(context.mounted ? context : null, '授权成功');
      return true;
    } catch (error) {
      _logger.warn(LogCategory.app, 'app auth failed', _failure(error));
      _toast(context.mounted ? context : null, '授权失败：${requestFailureMessage(error, fallback: '请稍后重试')}');
      return authorized;
    }
  }

  /// The code, the confirm with the web login, then a few polls; a refused confirm opens Bilibili's page instead.
  /// Null when the page was closed by hand.
  Future<AppToken?> _fetch(NavigatorState? pages) async {
    final code = await _client.tvAuthCode();
    try {
      await _client.confirmTvLogin(code.authCode);
    } on BiliError catch (error) {
      if (error is! BiliAPIError && error is! BiliHTTPError) rethrow;
      _logger.info(LogCategory.app, 'app auth confirm refused', _failure(error));
      return _confirmOnPage(pages ?? navigator.currentState, code.url, code.authCode);
    }
    for (var poll = 0; poll < quickPolls; poll++) {
      if (poll > 0) await Future<void>.delayed(pollInterval);
      switch (await _client.tvPoll(code.authCode)) {
        case TVLoginConfirmed(:final token):
          return token;
        case TVLoginExpired():
          throw const _AuthFailure('expired');
        case TVLoginWaiting():
          break;
      }
    }
    throw const _AuthFailure('unconfirmed');
  }

  Future<AppToken?> _confirmOnPage(NavigatorState? pages, String url, String authCode) async {
    final page = Uri.tryParse(url);
    if (pages == null || !pages.mounted || page == null || page.scheme != 'https') {
      throw const _AuthFailure('no page');
    }
    final route = confirmPage(page, environment.cookies.all);
    var open = true;
    unawaited(pages.push(route).whenComplete(() => open = false));
    var failures = 0;
    try {
      final polls = pageTimeout.inMilliseconds ~/ pagePollInterval.inMilliseconds;
      for (var poll = 0; poll < polls; poll++) {
        await Future<void>.delayed(pagePollInterval);
        if (!open) return null;
        final TVLoginState state;
        try {
          state = await _client.tvPoll(authCode);
        } on BiliError {
          rethrow;
        } catch (error) {
          // A dropped connection while the user reads the page; only a run of them ends it.
          if (++failures >= pageFailuresAllowed) rethrow;
          continue;
        }
        failures = 0;
        switch (state) {
          case TVLoginConfirmed(:final token):
            return token;
          case TVLoginExpired():
            throw const _AuthFailure('expired');
          case TVLoginWaiting():
            break;
        }
      }
      if (!open) return null;
      throw const _AuthFailure('timed out');
    } finally {
      if (open) _close(route);
    }
  }

  void _close(Route<Object?> route) {
    final pages = route.navigator;
    if (pages == null || !route.isActive) return;
    if (route.isCurrent) {
      pages.pop();
    } else {
      pages.removeRoute(route);
    }
  }

  /// One call; a failure keeps the token, which is good until its date. A rejection drops it through [_rejected].
  Future<void> _renew() async {
    try {
      final renewed = await _client.renewAppToken();
      if (_disposed || !authorized) return;
      await _hold(renewed);
      _logger.info(LogCategory.app, 'app token renewed', {'days': _daysLeft(renewed, _now())});
    } catch (error) {
      _logger.warn(LogCategory.app, 'app token renewal failed', _failure(error));
    }
  }

  void _rejected() {
    if (!authorized) return;
    unawaited(_drop('rejected'));
    if (_rejectionAsked) return;
    _rejectionAsked = true;
    _askLater();
  }

  void _accountChanged() {
    switch (environment.account) {
      case AccountUnknown():
        // Only a login passes through unknown without a failed check. It reads logged in while the login page is
        // still up, and that page pops whatever is on top when it closes, so its end ([_loggedIn]) asks instead.
        if (!environment.accountCheckFailed) _loginUnderway = true;
      case LoggedOut():
        _loginUnderway = false;
        if (authorized) unawaited(_drop('logout'));
      case LoginExpired():
        _loginUnderway = false;
      case LoggedIn():
        if (_loginUnderway || _launchAsked) return;
        _launchAsked = true;
        _dropOtherAccount();
        if (!authorized && !_storeUnreadable) _askLater();
    }
  }

  void _loggedIn() {
    _loginUnderway = false;
    _launchAsked = true;
    _dropOtherAccount();
    if (!authorized) _askLater();
  }

  /// The token belongs to the account it was confirmed with; another account logging in can't use it.
  void _dropOtherAccount() {
    final token = _client.appToken;
    final mid = environment.mid;
    if (token != null && mid != null && token.mid != mid) unawaited(_drop('other account'));
  }

  /// After the current turn, so a login page popping as it hands over its login closes itself, not the confirm.
  void _askLater() {
    Timer.run(() {
      if (_disposed || authorized || environment.account is! LoggedIn) return;
      final context = navigator.currentContext;
      if (context == null) {
        _logger.warn(LogCategory.app, 'app auth not asked', {'reason': 'no navigator'});
        return;
      }
      unawaited(request(context));
    });
  }

  Future<void> _hold(AppToken token) async {
    _client.appToken = token;
    if (!_disposed) notifyListeners();
    var saved = false;
    try {
      saved = await environment.keychain.saveAppToken(jsonEncode(token.toJson()));
    } catch (_) {
      saved = false;
    }
    if (!saved) _logger.warn(LogCategory.app, 'app token not saved');
  }

  Future<void> _drop(String reason) async {
    _client.appToken = null;
    _logger.info(LogCategory.app, 'app token dropped', {'reason': reason});
    if (!_disposed) notifyListeners();
    await _deleteStored();
  }

  Future<AppToken?> _stored() async {
    final String? stored;
    try {
      stored = await environment.keychain.loadAppToken();
    } catch (error) {
      _storeUnreadable = true;
      _logger.warn(LogCategory.app, 'app token unreadable', {'error': '${error.runtimeType}'});
      return null;
    }
    if (stored == null) return null;
    AppToken? token;
    try {
      token = AppToken.fromJson(jsonDecode(stored));
    } on FormatException {
      token = null;
    } on DecodeError {
      token = null;
    }
    if (token != null) return token;
    // The Swift app kept a bare access token here, with no refresh token or expiry to go on.
    _logger.info(LogCategory.app, 'app token dropped', {'reason': 'not json'});
    await _deleteStored();
    return null;
  }

  Future<void> _deleteStored() async {
    try {
      await environment.keychain.deleteAppToken();
    } catch (error) {
      _logger.warn(LogCategory.app, 'app token not deleted', {'error': '${error.runtimeType}'});
    }
  }

  Future<String> _deviceId() async {
    final path = devicePath();
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final json = jsonDecode(await file.readAsString());
          final id = json is Map<String, Object?> ? json['buvid'] : null;
          if (id is String && _buvidShape.hasMatch(id)) return id;
        }
      } catch (error) {
        _logger.warn(LogCategory.app, 'app device id unreadable', {'error': '${error.runtimeType}'});
      }
    }
    final id = newBuvid();
    if (path != null) {
      try {
        await File(path).parent.create(recursive: true);
        await File(path).writeAsString(jsonEncode({'buvid': id}), flush: true);
      } catch (error) {
        _logger.warn(LogCategory.app, 'app device id not saved', {'error': '${error.runtimeType}'});
      }
    }
    return id;
  }

  /// A context under the app's overlay, for the toasts of a confirm no page asked for.
  BuildContext? _underOverlay() {
    BuildContext? child;
    navigator.currentState?.overlay?.context.visitChildElements((element) => child ??= element);
    return child;
  }

  void _toast(BuildContext? context, String message) {
    if (_disposed) return;
    final target = context != null && Overlay.maybeOf(context, rootOverlay: true) != null ? context : _underOverlay();
    if (target != null) showToast(target, message);
  }

  static int _daysLeft(AppToken token, DateTime now) => token.expiresAt.difference(now).inDays;

  /// Codes and states only: never a token, the auth code or its page's URL.
  static Map<String, Object> _failure(Object error) => switch (error) {
    BiliAPIError(:final code) => {'code': code},
    BiliHTTPError(:final status) => {'status': status},
    _AuthFailure(:final reason) => {'reason': reason},
    _ => {'error': '${error.runtimeType}'},
  };

  @override
  void dispose() {
    _disposed = true;
    environment.removeListener(_accountChanged);
    environment.logins.removeListener(_loggedIn);
    if (_client.onAppTokenRejected == _rejected) _client.onAppTokenRejected = null;
    super.dispose();
  }
}

/// The token didn't come: the code ran out, the poll never saw the confirm, or there was no page to confirm on.
final class _AuthFailure implements Exception {
  const _AuthFailure(this.reason);

  final String reason;

  @override
  String toString() => 'AppAuthFailure($reason)';
}
