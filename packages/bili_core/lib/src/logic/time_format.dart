/// Swift takes a TimeZone here. Dart's DateTime only knows local and UTC, so the calendar functions take a fixed
/// `utcOffset` instead; null means the device's own offset at the instant being formatted.
abstract final class TimeFormat {
  static String clock(double seconds) {
    final total = seconds.isFinite && seconds > 0 ? seconds.toInt() : 0;
    final h = total ~/ 3600, m = total % 3600 ~/ 60, s = total % 60;
    return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
  }

  static String pair(double position, double duration) => '${clock(position)}/${clock(duration)}';

  static String publish(int unix, {Duration? utcOffset}) {
    final c = _wallClock(_date(unix), utcOffset);
    return '${c.year}年${c.month}月${c.day}日 ${_two(c.hour)}:${_two(c.minute)}';
  }

  /// Comment and feed timestamps. The 24 h cut is elapsed time; "昨天" and the date forms follow the calendar at `utcOffset`.
  static String relative(int unix, {required DateTime now, Duration? utcOffset}) {
    final then = _date(unix);
    final elapsed = now.difference(then).inMicroseconds / Duration.microsecondsPerSecond;
    if (elapsed < 60) return '刚刚';
    if (elapsed < 3600) return '${elapsed ~/ 60}分钟前';
    if (elapsed < 86400) return '${elapsed ~/ 3600}小时前';

    final c = _wallClock(then, utcOffset);
    final today = _wallClock(now, utcOffset);
    final days = _startOfDay(today).difference(_startOfDay(c)).inDays;
    if (days == 1) return '昨天 ${_two(c.hour)}:${_two(c.minute)}';
    if (c.year == today.year) return '${_two(c.month)}-${_two(c.day)}';
    return '${c.year}-${_two(c.month)}-${_two(c.day)}';
  }

  /// A UTC DateTime whose fields read as the wall clock at the offset.
  static DateTime _wallClock(DateTime instant, Duration? utcOffset) =>
      instant.toUtc().add(utcOffset ?? instant.toLocal().timeZoneOffset);

  static DateTime _startOfDay(DateTime wallClock) => DateTime.utc(wallClock.year, wallClock.month, wallClock.day);

  static DateTime _date(int unix) => DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);

  static String _two(int n) => n < 10 ? '0$n' : '$n';
}
