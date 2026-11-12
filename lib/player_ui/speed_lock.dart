import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../shared/theme.dart';
import '../video/player_session.dart';

enum SpeedLockPhase {
  off,

  /// Held at 2×: the hint shows under the progress line.
  holding,

  /// The finger is down on the hint: let go there and the speed stays.
  armed,

  /// The speed stays after the finger left, until 取消.
  locked,
}

/// 竖屏's held 2× and its lock (182, 183, 186).
class SpeedLock extends ValueNotifier<SpeedLockPhase> {
  SpeedLock() : super(SpeedLockPhase.off);

  /// The hint's band, up from the screen's bottom: from just under the progress line over the bottom row and the
  /// home indicator (182, 183). A held finger inside it arms the lock.
  static double bandHeight(EdgeInsets padding) =>
      math.max(padding.bottom - BiliMetrics.verticalBottomDrop, 0.0) +
      BiliMetrics.chromeButton +
      SpeedLockTheme.bandOverRow;

  /// 取消, or the lock's end: back to the chosen speed. Does nothing unless locked.
  void unlock(PlayerSession session) {
    if (value != SpeedLockPhase.locked) return;
    value = SpeedLockPhase.off;
    session.speedUp(false);
  }
}
