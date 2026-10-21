import 'package:bilifast/search/results/video_row.dart';
import 'package:flutter_test/flutter_test.dart';

import 'results_support.dart';

void main() {
  const offset = Duration(hours: 8);

  /// [hour]:[minute] on the given day, Beijing time.
  DateTime at(int year, int month, int day, int hour, int minute) =>
      DateTime.utc(year, month, day, hour, minute).subtract(offset);

  final now = at(2026, 10, 21, 15, 3);

  String date(DateTime published) => SearchFormat.date(published, now: now, utcOffset: offset);

  test('dates read as 56 and 61 show them', () {
    expect(date(now.subtract(const Duration(minutes: 7))), '7分钟前');
    expect(date(now.subtract(const Duration(hours: 23))), '23小时前');
    expect(date(at(2026, 10, 20, 15, 0)), '昨天 15:00');
    expect(date(at(2026, 6, 20, 9, 30)), '6月20日');
    expect(date(at(2025, 12, 31, 23, 0)), '2025-12-31');
    expect(SearchFormat.date(null, now: now), '');
  });

  test('counts as 9.2万, 148.1万 and plain under 10000', () {
    expect(SearchFormat.count(92345), '9.2万');
    expect(SearchFormat.count(1481999), '148.1万');
    expect(SearchFormat.count(8385), '8385');
    expect(SearchFormat.count(120000000), '1.2亿');
  });

  test('lengths as the cover shows them', () {
    expect(SearchFormat.duration(162), '2:42');
    expect(SearchFormat.duration(21), '0:21');
    expect(SearchFormat.duration(2312), '38:32');
    expect(SearchFormat.duration(3723), '1:02:03');
  });

  test('the plays line leaves out an unknown date', () {
    expect(SearchFormat.plays(video(1, play: 60000), now: now), '6万');
  });

  test('fans alone with no videos, else fans · videos', () {
    expect(SearchFormat.fans(user(1, fans: 8)), '8粉丝');
    expect(SearchFormat.fans(user(2, fans: 1481234, videos: 539)), '148.1万粉丝 · 539个视频');
  });
}
