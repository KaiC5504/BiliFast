import 'package:flutter/foundation.dart';

/// 竖屏's page under the finger. [offset] is how far the page has moved, in points: negative towards the next video
/// (a swipe up), positive towards the one before. The gesture layer drives a drag ([start], [update], [end]); the
/// pager shapes the finger's travel ([shape]), answers a lifted finger ([onRelease]) and moves the page by itself
/// ([settleTo]) until it [land]s. The chrome dims and keeps its top bar still while [moving].
class StoryDrag extends ChangeNotifier {
  double _offset = 0;
  double _travel = 0;
  bool _dragging = false;
  bool _settling = false;

  double get offset => _offset;
  bool get dragging => _dragging;
  bool get settling => _settling;
  bool get moving => _dragging || _settling || _offset != 0;

  /// The page's offset for the finger's travel: past the first video it resists.
  double Function(double travel)? shape;

  /// [shape] undone: the finger's travel that puts the page at an offset, so a finger taking a settling page picks it
  /// up where it is.
  double Function(double offset)? unshape;

  /// The finger lifted, at [velocity] points a second (negative upwards). Unset, the page goes back at once.
  void Function(double velocity)? onRelease;

  /// A finger took the page, also while it settles.
  void start() {
    _dragging = true;
    _settling = false;
    _travel = unshape?.call(_offset) ?? _offset;
    notifyListeners();
  }

  void update(double delta) {
    if (!_dragging) return;
    _travel += delta;
    _offset = shape?.call(_travel) ?? _travel;
    notifyListeners();
  }

  void end(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final release = onRelease;
    if (release != null) {
      release(velocity);
    } else {
      land();
    }
  }

  /// The drag was taken away (another gesture won, the page left 竖屏).
  void cancel() => end(0);

  /// The pager moving the page by itself.
  void settleTo(double offset) {
    _settling = true;
    _offset = offset;
    notifyListeners();
  }

  /// At rest: the neighbour is the page now, or the page went back.
  void land() {
    _dragging = false;
    _settling = false;
    _offset = 0;
    _travel = 0;
    notifyListeners();
  }
}
