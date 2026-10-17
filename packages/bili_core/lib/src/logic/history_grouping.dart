import '../api/feed_models.dart';

abstract final class HistoryGrouping {
  /// One section per calendar day at `utcOffset` (null: the device's offset), in the order the days first appear.
  /// The history list is already newest first.
  static List<({String title, List<HistoryItem> items})> sections(
    List<HistoryItem> items, {
    required DateTime now,
    Duration? utcOffset,
  }) {
    final today = _day(now, utcOffset);
    final byDay = <DateTime, List<HistoryItem>>{};
    for (final item in items) {
      final viewed = DateTime.fromMillisecondsSinceEpoch(item.viewAt * 1000, isUtc: true);
      byDay.putIfAbsent(_day(viewed, utcOffset), () => []).add(item);
    }
    return [for (final MapEntry(key: day, value: rows) in byDay.entries) (title: _title(day, today), items: rows)];
  }

  static String _title(DateTime day, DateTime today) {
    // Both are UTC midnights, so whole-day division is exact.
    final age = today.difference(day).inDays;
    if (age == 0) return '今天';
    if (age == 1) return '昨天';
    final monthDay = '${day.month}月${day.day}日';
    return day.year == today.year ? monthDay : '${day.year}年$monthDay';
  }

  /// The calendar day at the offset, as a UTC midnight.
  static DateTime _day(DateTime instant, Duration? utcOffset) {
    final wall = instant.toUtc().add(utcOffset ?? instant.toLocal().timeZoneOffset);
    return DateTime.utc(wall.year, wall.month, wall.day);
  }
}
