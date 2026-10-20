import 'dart:async';

import 'package:bilifast/shared/theme.dart';

import 'support/system_font.dart';

/// Tests register the SF stand-in under BiliFonts.system, which iOS doesn't, so the phone's own fallback to PingFang SC
/// for Chinese has to be named here.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  BiliFonts.systemFallback = systemFallback;
  await testMain();
}
