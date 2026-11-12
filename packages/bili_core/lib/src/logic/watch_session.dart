/// What one play came to, as the official app's end report counts it; whole seconds.
final class WatchTotals {
  const WatchTotals({
    required this.startTs,
    required this.playedTime,
    required this.actualPlayedTime,
    required this.totalTime,
    required this.pausedTime,
    required this.lastProgress,
    required this.maxProgress,
  });

  /// Unix seconds when the play began.
  final int startTs;

  /// How much of the video went by while playing: twice [actualPlayedTime] at 2×.
  final int playedTime;

  /// The time spent playing.
  final int actualPlayedTime;

  /// The time since the play began, pauses and waits included.
  final int totalTime;
  final int pausedTime;

  /// Where the player was last, and the furthest it has been.
  final int lastProgress;
  final int maxProgress;
}

enum _State { playing, paused, waiting }

/// Adds one play up from the player's events for the official app's end report: the caller says when playback
/// starts, pauses, resumes, seeks and ends, and where the player is. Nothing counts before [started]. Times go to the
/// nearest second and places are cut to the second, which is how the captured report of an 8 s play reads (8 s
/// played, last at 7).
final class WatchSession {
  WatchSession({this._now = DateTime.now});

  /// No speed the player has moves faster than this; with [_slack] it tells play from a jump.
  static const _topRate = 4.0;
  static const _slack = 1.0;

  final DateTime Function() _now;
  DateTime? _startedAt;
  _State _state = _State.waiting;

  /// When the state's time was last added up, and when [_position] was heard.
  late DateTime _since;
  late DateTime _positionAt;
  Duration _playing = Duration.zero;
  Duration _paused = Duration.zero;
  double _played = 0;
  double _position = 0;
  double _furthest = 0;

  /// Playback first starts, at [position].
  void started(double position) {
    if (_startedAt != null) return;
    final now = _now();
    _startedAt = now;
    _since = now;
    _positionAt = now;
    _state = _State.playing;
    _place(position, now);
  }

  /// The player is at [position]; not [playing] while it waits (buffering, a reload). A paused player stays paused
  /// until [resumed].
  void tick({required double position, required bool playing}) {
    if (_startedAt == null) return;
    final now = _now();
    _addUp(now);
    _advance(position, now);
    if (_state != _State.paused) _state = playing ? _State.playing : _State.waiting;
  }

  void paused() => _enter(_State.paused);

  void resumed() => _enter(_State.playing);

  /// The video reached its end.
  void ended() => _enter(_State.waiting);

  /// The player was sent to [position].
  void seeked(double position) {
    if (_startedAt == null) return;
    final now = _now();
    _addUp(now);
    _place(position, now);
  }

  WatchTotals get totals {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return const WatchTotals(
        startTs: 0,
        playedTime: 0,
        actualPlayedTime: 0,
        totalTime: 0,
        pausedTime: 0,
        lastProgress: 0,
        maxProgress: 0,
      );
    }
    final now = _now();
    _addUp(now);
    return WatchTotals(
      startTs: startedAt.millisecondsSinceEpoch ~/ 1000,
      playedTime: _played.round(),
      actualPlayedTime: _seconds(_playing),
      totalTime: _seconds(now.difference(startedAt)),
      pausedTime: _seconds(_paused),
      lastProgress: _position.floor(),
      maxProgress: _furthest.floor(),
    );
  }

  void _enter(_State state) {
    if (_startedAt == null) return;
    final now = _now();
    _addUp(now);
    _state = state;
    // A pause can be long: what the player does across it is not measured against it.
    _positionAt = now;
  }

  void _addUp(DateTime now) {
    final spent = now.difference(_since);
    _since = now;
    // The phone's clock can be set back mid-play.
    if (spent.isNegative) return;
    switch (_state) {
      case _State.playing:
        _playing += spent;
      case _State.paused:
        _paused += spent;
      case _State.waiting:
        break;
    }
  }

  /// The move to [position] counts as played only while playing, forward, and no further than the time since the
  /// last position allows: a reading from before a seek landed, or a seek nobody named, plays nothing.
  void _advance(double position, DateTime now) {
    if (!position.isFinite || position < 0) return;
    final moved = position - _position;
    final allowed = now.difference(_positionAt).inMicroseconds / 1e6 * _topRate + _slack;
    if (_state == _State.playing && moved > 0 && moved <= allowed) _played += moved;
    _place(position, now);
  }

  void _place(double position, DateTime now) {
    if (!position.isFinite || position < 0) return;
    _position = position;
    _positionAt = now;
    if (position > _furthest) _furthest = position;
  }

  static int _seconds(Duration time) => time.isNegative ? 0 : (time.inMicroseconds / 1e6).round();
}
