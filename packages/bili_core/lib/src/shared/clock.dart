final class MonotonicClock {
  const MonotonicClock(this.nowMs);

  final double Function() nowMs;

  static final MonotonicClock system = () {
    final watch = Stopwatch()..start();
    return MonotonicClock(() => watch.elapsedMicroseconds / 1000);
  }();
}

/// Test clock whose time only moves when told to.
final class ManualClock {
  ManualClock([this._value = 0]);

  double _value;

  void advance(double ms) => _value += ms;
  void set(double ms) => _value = ms;
  MonotonicClock get clock => MonotonicClock(() => _value);
}

Future<void> sleepMs(double ms) =>
    ms > 0 ? Future<void>.delayed(Duration(microseconds: (ms * 1000).round())) : Future<void>.value();
