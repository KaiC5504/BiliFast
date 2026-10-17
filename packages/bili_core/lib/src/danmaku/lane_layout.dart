enum LaneKind { scroll, top, bottom }

final class _Scrolling {
  const _Scrolling(this.start, this.width);

  final double start;
  final double width;
}

/// Collision-free lanes for scrolling, top and bottom danmaku. Times are seconds on the player's clock.
final class LaneLayout {
  LaneLayout({required int lanes, required double width, required double scrollDuration, this.staticDuration = 4})
    : _lanes = 0,
      _screenWidth = width,
      _scrollDuration = scrollDuration {
    reset(lanes: lanes, width: width, scrollDuration: scrollDuration);
  }

  final double staticDuration;
  int _lanes;
  double _screenWidth;
  double _scrollDuration;
  List<_Scrolling?> _scrolling = const [];
  List<double> _topBusyUntil = const [];
  List<double> _bottomBusyUntil = const [];

  /// The lane, 0 being the top line, or null when none is free and the danmaku is dropped.
  int? place(LaneKind kind, {required double width, required double at}) {
    final t = at;
    switch (kind) {
      case LaneKind.scroll:
        final speed = (_screenWidth + width) / _scrollDuration;
        for (var lane = 0; lane < _lanes; lane++) {
          if (_fitsScroll(lane, speed, t)) {
            _scrolling[lane] = _Scrolling(t, width);
            return lane;
          }
        }
        return null;
      case LaneKind.top:
        for (var lane = 0; lane < _lanes; lane++) {
          if (_topBusyUntil[lane] <= t) {
            _topBusyUntil[lane] = t + staticDuration;
            return lane;
          }
        }
        return null;
      case LaneKind.bottom:
        for (var index = 0; index < _lanes; index++) {
          if (_bottomBusyUntil[index] <= t) {
            _bottomBusyUntil[index] = t + staticDuration;
            return _lanes - 1 - index;
          }
        }
        return null;
    }
  }

  void reset({required int lanes, required double width, required double scrollDuration}) {
    final count = lanes < 0 ? 0 : lanes;
    _lanes = count;
    _screenWidth = width;
    _scrollDuration = scrollDuration;
    _scrolling = List<_Scrolling?>.filled(count, null);
    _topBusyUntil = List<double>.filled(count, double.negativeInfinity);
    _bottomBusyUntil = List<double>.filled(count, double.negativeInfinity);
  }

  bool _fitsScroll(int lane, double speed, double t) {
    final ahead = _scrolling[lane];
    if (ahead == null) return true;
    final aheadSpeed = (_screenWidth + ahead.width) / _scrollDuration;
    final fullyEntered = (t - ahead.start) * aheadSpeed >= ahead.width;
    final cannotCatchUp = (ahead.start + _scrollDuration - t) * speed <= _screenWidth;
    return fullyEntered && cannotCatchUp;
  }
}
