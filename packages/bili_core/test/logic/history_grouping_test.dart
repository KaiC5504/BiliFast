import 'package:bili_core/api.dart';
import 'package:bili_core/logic.dart';
import 'package:test/test.dart';

void main() {
  const utc8 = Duration(hours: 8);

  int unix(int y, int mo, int d, int h, int mi) =>
      DateTime.utc(y, mo, d, h, mi).subtract(utc8).millisecondsSinceEpoch ~/ 1000;

  HistoryItem item(String bvid, {required int at}) => HistoryItem(
    bvid: bvid,
    cid: 1,
    title: bvid,
    cover: '',
    ownerName: '',
    progress: 0,
    duration: 60,
    viewAt: at,
    device: 1,
    part: null,
  );

  final now = DateTime.fromMillisecondsSinceEpoch(unix(2026, 10, 17, 1, 0) * 1000, isUtc: true);

  test('grouping titles', () {
    final items = [
      item('today', at: unix(2026, 10, 17, 0, 30)),
      item('yesterday', at: unix(2026, 10, 16, 23, 0)),
      item('sameYear', at: unix(2026, 10, 1, 8, 0)),
      item('lastYear', at: unix(2025, 12, 31, 12, 0)),
    ];
    final sections = HistoryGrouping.sections(items, now: now, utcOffset: utc8);
    expect(sections.map((s) => s.title), ['今天', '昨天', '10月1日', '2025年12月31日']);
    expect(sections.map((s) => s.items.map((i) => i.bvid).toList()), [
      ['today'],
      ['yesterday'],
      ['sameYear'],
      ['lastYear'],
    ]);
  });

  test('rows of one day share a section and keep their order', () {
    final items = [
      item('a', at: unix(2026, 10, 16, 23, 0)),
      item('b', at: unix(2026, 10, 16, 9, 0)),
      item('c', at: unix(2026, 10, 16, 0, 5)),
      item('d', at: unix(2026, 10, 15, 23, 59)),
    ];
    final sections = HistoryGrouping.sections(items, now: now, utcOffset: utc8);
    expect(sections.map((s) => s.title), ['昨天', '10月15日']);
    expect(sections[0].items.map((i) => i.bvid), ['a', 'b', 'c']);
  });

  test('the given offset decides where midnight falls', () {
    // Now is 01:00 on the 17th at +8 but 17:00 on the 16th in UTC, so a 23:00 row on the 16th is "yesterday" only at +8.
    final late = [item('late', at: unix(2026, 10, 16, 23, 0))];
    expect(HistoryGrouping.sections(late, now: now, utcOffset: utc8).map((s) => s.title), ['昨天']);
    expect(HistoryGrouping.sections(late, now: now, utcOffset: Duration.zero).map((s) => s.title), ['今天']);
  });

  test('no rows, no sections', () {
    expect(HistoryGrouping.sections([], now: now, utcOffset: utc8), isEmpty);
  });
}
