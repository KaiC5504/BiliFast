/// Decides when to report playback progress; the caller does the network call.
final class HeartbeatSchedule {
  HeartbeatSchedule({this.interval = 15});

  /// Sent as the progress value once the video has been watched to the end.
  static const int finished = -1;

  final double interval;
  double _baseline = 0;

  int? tick({required double position, required bool playing}) {
    if (!playing || !position.isFinite || position - _baseline < interval) return null;
    _baseline = position;
    return _seconds(position);
  }

  /// For events that always report (pause, seek done, part change, leaving).
  int mark({required double position}) {
    _baseline = position.isFinite ? position : 0;
    return _seconds(position);
  }

  // The player's position is NaN while seeking or leaving; a stray negative must not read as the `finished` marker.
  int _seconds(double position) => position.isFinite && position > 0 ? position.toInt() : 0;
}
