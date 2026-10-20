import 'dart:async';

import 'package:bilifast/shared/theme.dart';

import 'support/system_font.dart';

/// Tests register the SF stand-in under BiliFonts.system itself, so the PingFang stand-in behind it is all the list the
/// phone's launch check (BiliFonts.settleSystemFallback) names after SF.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  BiliFonts.systemFallback = systemFallback;
  await testMain();
}
