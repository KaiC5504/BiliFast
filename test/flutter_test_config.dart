import 'dart:async';

import 'package:bilifast/shared/theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stand_in_fonts.dart';
import 'support/system_font.dart';

/// Every test draws the system font, as the phone does, through its stand-ins. Tests register the SF stand-in under
/// BiliFonts.system itself, so the PingFang stand-in behind it is all the list the phone's launch check
/// (BiliFonts.settleSystemFallback) names after SF.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadSystemFontStandIns();
  BiliFonts.systemFallback = systemFallback;
  await testMain();
}
