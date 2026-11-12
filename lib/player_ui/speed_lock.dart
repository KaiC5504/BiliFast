import 'package:flutter/foundation.dart';

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
}
