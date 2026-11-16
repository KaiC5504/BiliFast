import 'package:bilifast/message/message_dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 16, 10);

  test('a list date reads as 196, 197 and 198 do', () {
    expect(noticeDate(now.subtract(const Duration(seconds: 20)), now: now), '刚刚');
    expect(noticeDate(now.subtract(const Duration(minutes: 5)), now: now), '5分钟前');
    expect(noticeDate(now.subtract(const Duration(hours: 23)), now: now), '23小时前');
    expect(noticeDate(now.subtract(const Duration(days: 3)), now: now), '3天前');
    expect(noticeDate(DateTime(2026, 11, 12, 9), now: now), '11月12日');
    expect(noticeDate(DateTime(2023, 11, 19), now: now), '2023年11月19日');
  });

  test("a chat's time line always gives the year", () {
    expect(chatStamp(DateTime(2025, 11, 26, 21, 51)), '2025年11月26日 21:51');
    expect(chatStamp(DateTime(2026, 11, 6, 9, 5)), '2026年11月6日 09:05');
  });
}
