import 'package:flutter/material.dart';

import '../app/app_environment.dart';
import 'login_page.dart';

/// Where a logged-out action goes (BiliNative `LoginGate`): the login page, completing with whether the user came
/// back logged in. The caller turns the phone upright first when it is in landscape full screen.
abstract interface class LoginGate {
  Future<bool> request(BuildContext context);
}

/// Pushes the login page over whatever is showing, even when the app reads logged in: callers ask for plain
/// logged-out taps only when logged out, and otherwise only after Bilibili answered that the login is gone (as
/// Swift's LoginGate, which always shows the page).
class LoginPageGate implements LoginGate {
  const LoginPageGate(this.environment);

  final AppEnvironment environment;

  /// The page already up for an environment, so a second request waits on it instead of pushing another.
  static final _showing = Expando<Future<bool>>();

  @override
  Future<bool> request(BuildContext context) {
    if (_showing[environment] case final showing?) return showing;
    final shown = Navigator.of(context, rootNavigator: true)
        .push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const LoginPage()))
        .then((loggedIn) => loggedIn ?? false)
        .whenComplete(() {
      _showing[environment] = null;
    });
    _showing[environment] = shown;
    return shown;
  }
}
