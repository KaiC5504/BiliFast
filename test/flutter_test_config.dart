import 'dart:async';

import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/collection_row.dart';
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
  setUp(() {
    // 深色模式 is a global: a test that turns it on never leaks it into the next.
    BiliTheme.dark = false;
    // The playing mark loops forever, which no pumpAndSettle outlasts; its own tests let it move.
    PlayingBars.debugHoldStill = true;
  });
  await testMain();
}
