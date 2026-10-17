import 'package:bili_core/logic.dart';
import 'package:test/test.dart';

void main() {
  const utc8 = Duration(hours: 8);

  int unix(int y, int mo, int d, int h, int mi, [int s = 0]) =>
      DateTime.utc(y, mo, d, h, mi, s).subtract(utc8).millisecondsSinceEpoch ~/ 1000;

  DateTime at(int unix) => DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);

  test('clock and pair', () {
    expect(TimeFormat.pair(1, 195), '00:01/03:15');
    expect(TimeFormat.clock(3723), '1:02:03');
    expect(TimeFormat.clock(195), '03:15');
    expect(TimeFormat.clock(3599.9), '59:59');
    expect(TimeFormat.clock(3600), '1:00:00');
  });

  test('clock clamps nonsense', () {
    expect(TimeFormat.clock(-5), '00:00');
    expect(TimeFormat.clock(double.nan), '00:00');
    expect(TimeFormat.clock(double.infinity), '00:00');
  });

  test('publish in the given UTC offset', () {
    expect(TimeFormat.publish(unix(2026, 10, 11, 21, 5), utcOffset: utc8), '2026年10月11日 21:05');
    expect(TimeFormat.publish(unix(2026, 1, 2, 3, 4), utcOffset: utc8), '2026年1月2日 03:04');
    expect(TimeFormat.publish(unix(2026, 10, 11, 1, 5), utcOffset: Duration.zero), '2026年10月10日 17:05');
  });

  test('relative times', () {
    final nowUnix = unix(2026, 10, 17, 22, 0);
    final now = at(nowUnix);
    String rel(int t) => TimeFormat.relative(t, now: now, utcOffset: utc8);

    expect(rel(nowUnix - 30), '刚刚');
    expect(rel(nowUnix - 59), '刚刚');
    expect(rel(nowUnix + 30), '刚刚');
    expect(rel(nowUnix - 60), '1分钟前');
    expect(rel(nowUnix - 5 * 60), '5分钟前');
    expect(rel(nowUnix - 3600), '1小时前');
    expect(rel(nowUnix - 3 * 3600), '3小时前');
    expect(rel(nowUnix - 24 * 3600 + 1), '23小时前');
    expect(rel(unix(2026, 10, 16, 21, 5)), '昨天 21:05');
    expect(rel(unix(2026, 10, 16, 0, 30)), '昨天 00:30');
    expect(rel(unix(2026, 10, 15, 23, 59)), '10-15');
    expect(rel(unix(2026, 10, 1, 8, 0)), '10-01');
    expect(rel(unix(2025, 10, 1, 8, 0)), '2025-10-01');
  });

  test('yesterday follows the given UTC offset, not the device one', () {
    // 2026-10-16 07:00 at +8 is 2026-10-15 23:00 in UTC
    final now = at(unix(2026, 10, 17, 9, 0));
    final published = unix(2026, 10, 16, 7, 0);
    expect(TimeFormat.relative(published, now: now, utcOffset: utc8), '昨天 07:00');
    expect(TimeFormat.relative(published, now: now, utcOffset: Duration.zero), '10-15');
  });
}
