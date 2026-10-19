import 'package:bilifast/account/login_gate.dart';
import 'package:flutter/widgets.dart';

/// Counts the requests and answers [answer] at once, with no login page.
final class FakeLoginGate implements LoginGate {
  int requests = 0;
  bool answer = false;

  @override
  Future<bool> request(BuildContext context) async {
    requests++;
    return answer;
  }
}
