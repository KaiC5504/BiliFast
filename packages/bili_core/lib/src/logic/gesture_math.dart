import 'dart:math' as math;

// Not `Axis`: Flutter's widgets library exports one, and the app imports both.
enum GestureAxis { horizontal, vertical }

abstract final class GestureMath {
  /// A drag across the whole player seeks this much plus [seekShareOfDuration] of the video. Measured on the
  /// official iPhone app with exact drags (3:31 to 48:37, portrait and landscape alike: 52.2 s + duration / 7.08,
  /// within half a second).
  static const double seekBaseSecondsPerWidth = 52.2;
  static const double seekShareOfDuration = 1 / 7.08;

  /// A seek counts from where the finger is this long after the drag is claimed, so a quick swipe's first stretch
  /// moves nothing; the official app loses about 11 pt of a 150 pt/s drag and 39 pt of a 1200 pt/s one.
  static const Duration seekCountsAfter = Duration(milliseconds: 20);

  static const double axisLockDistance = 10;
  static const double edgeInset = 25;

  /// null until the finger has travelled far enough to tell a seek from a brightness/volume drag.
  static GestureAxis? axis({required double dx, required double dy}) {
    if (math.sqrt(dx * dx + dy * dy) < axisLockDistance) return null;
    return dx.abs() >= dy.abs() ? GestureAxis.horizontal : GestureAxis.vertical;
  }

  static double seekSecondsPerWidth(double duration) =>
      seekBaseSecondsPerWidth + _max(0, duration) * seekShareOfDuration;

  static double seekTarget({
    required double start,
    required double dx,
    required double width,
    required double duration,
  }) {
    final upper = _max(0, duration);
    if (!(width > 0)) return _min(_max(start, 0), upper);
    return _min(_max(start + dx / width * seekSecondsPerWidth(duration), 0), upper);
  }

  /// Brightness or volume after a vertical drag; dragging up raises it, a full height drag spans 0 to 1.
  static double level({required double start, required double dy, required double height}) {
    if (!(height > 0)) return _min(_max(start, 0), 1);
    return _min(_max(start - dy / height, 0), 1);
  }

  // Swift's min/max: a NaN in the second argument loses instead of spreading, so a NaN duration clamps to 0.
  static double _max(double x, double y) => y >= x ? y : x;
  static double _min(double x, double y) => y < x ? y : x;
}
