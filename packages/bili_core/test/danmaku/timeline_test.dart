import 'package:bili_core/danmaku.dart';
import 'package:test/test.dart';

import 'helpers.dart';

List<DisplayDanmaku> items(List<int> times) => [
  for (final t in times)
    DisplayDanmaku(
      elem: makeElem('t$t', at: t),
      text: 't$t',
      isOwn: false,
    ),
];

List<String> texts(List<DisplayDanmaku> list) => [for (final d in list) d.text];

void main() {
  test('seek back re-emits once and a jump skips', () {
    final t = DanmakuTimeline()..add(items([500, 1500, 2500]));
    expect(t.advance(600).length, 1);
    expect(t.advance(1600).length, 1);
    t.seek(0);
    expect(t.advance(600).length, 1);
    expect(t.advance(3000).length, 0); // a 2 400 ms jump is a seek
  });

  test('advance returns each item once in order', () {
    final t = DanmakuTimeline()..add(items([300, 100, 200]));
    expect(texts(t.advance(250)), ['t100', 't200']);
    expect(t.advance(250).length, 0);
    expect(texts(t.advance(350)), ['t300']);
    expect(t.advance(900).length, 0);
  });

  test('a step backwards is a seek', () {
    final t = DanmakuTimeline()..add(items([100, 200, 300]));
    expect(t.advance(350).length, 3);
    expect(t.advance(150).length, 0);
    expect(texts(t.advance(250)), ['t200']);
  });

  test('first advance after a start mid-video skips earlier items', () {
    final t = DanmakuTimeline()..add(items([100, 60000, 60500]));
    expect(t.advance(60000).length, 0);
    expect(texts(t.advance(60600)), ['t60500']);
  });

  test('items at time zero are emitted by the first advance', () {
    final t = DanmakuTimeline()..add(items([0, 50]));
    expect(texts(t.advance(100)), ['t0', 't50']);
  });

  test('items added behind the playhead wait for a seek', () {
    final t = DanmakuTimeline()..add(items([1000]));
    expect(t.advance(900).length, 0);
    expect(t.advance(1100).length, 1);
    t.add(items([500, 1050, 1200]));
    expect(texts(t.advance(1300)), ['t1200']);
    t.seek(0);
    expect(texts(t.advance(600)), ['t500']);
  });

  test('a later segment is merged in time order, ties after what was there', () {
    final t = DanmakuTimeline()..add(items([100, 300, 500]));
    t.add([
      DisplayDanmaku(elem: makeElem('early', at: 50), text: 'early', isOwn: false),
      DisplayDanmaku(elem: makeElem('tie', at: 300), text: 'tie', isOwn: false),
      DisplayDanmaku(elem: makeElem('late', at: 900), text: 'late', isOwn: false),
    ]);
    t.add(items([400, 200]));
    expect(texts(t.advance(999)), ['early', 't100', 't200', 't300', 'tie', 't400', 't500', 'late']);
  });

  test('same millisecond keeps arrival order', () {
    final t = DanmakuTimeline()
      ..add([DisplayDanmaku(elem: makeElem('a', at: 100), text: 'a', isOwn: false)])
      ..add([DisplayDanmaku(elem: makeElem('b', at: 100), text: 'b', isOwn: false)]);
    expect(texts(t.advance(200)), ['a', 'b']);
  });
}
