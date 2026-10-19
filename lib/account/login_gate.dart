import 'package:flutter/widgets.dart';

import '../app/app_environment.dart';

/// Where a logged-out action goes (BiliNative `LoginGate`): the login page, completing with whether the user came
/// back logged in. The caller turns the phone upright first when it is in landscape full screen.
abstract interface class LoginGate {
  Future<bool> request(BuildContext context);
}

/// Pushes the login page over whatever is showing.
class LoginPageGate implements LoginGate {
  const LoginPageGate(this.environment);

  final AppEnvironment environment;

  @override
  Future<bool> request(BuildContext context) => throw UnimplementedError('slice 8: login');
}
