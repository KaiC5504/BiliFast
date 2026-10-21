import 'package:flutter/widgets.dart';

import '../app/app_environment.dart';

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

/// The phone's: the token in the keychain's app-token item, set on [AppEnvironment.client].
class TokenAppAuth extends ChangeNotifier implements AppAuth {
  TokenAppAuth({required this.environment, required this.navigator});

  final AppEnvironment environment;

  /// For the launch's confirm, which no page asks for.
  final GlobalKey<NavigatorState> navigator;

  @override
  bool get authorized => environment.client.appToken != null;

  @override
  DateTime? get expiresAt => environment.client.appToken?.expiresAt;

  @override
  Future<void> start() async {}

  @override
  Future<bool> request(BuildContext context) async => false;

  @override
  Future<bool> reauthorize(BuildContext context) async => false;
}
