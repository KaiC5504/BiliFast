import 'package:bili_core/danmaku.dart';
import 'package:test/test.dart';

void main() {
  test('scroll lane waits until the last one has entered', () {
    final layout = LaneLayout(lanes: 3, width: 400, scrollDuration: 8);
    expect(layout.place(LaneKind.scroll, width: 100, at: 0), 0);
    expect(layout.place(LaneKind.scroll, width: 100, at: 0.5), 1);
    expect(layout.place(LaneKind.scroll, width: 100, at: 2.0), 0);
  });

  test('fast long danmaku does not catch a slow short one', () {
    final layout = LaneLayout(lanes: 2, width: 400, scrollDuration: 8);
    expect(layout.place(LaneKind.scroll, width: 20, at: 0), 0);
    // The long one has room to enter at 0.5 s, but at 100 pt/s it would reach the short one before it leaves.
    expect(layout.place(LaneKind.scroll, width: 400, at: 0.5), 1);
  });

  test('scroll drops when every lane is busy', () {
    final layout = LaneLayout(lanes: 2, width: 400, scrollDuration: 8);
    expect(layout.place(LaneKind.scroll, width: 100, at: 0), 0);
    expect(layout.place(LaneKind.scroll, width: 100, at: 0.1), 1);
    expect(layout.place(LaneKind.scroll, width: 100, at: 0.2), isNull);
  });

  test('static lanes fill from their edges and drop when full', () {
    final layout = LaneLayout(lanes: 2, width: 400, scrollDuration: 8);
    expect(layout.place(LaneKind.top, width: 50, at: 0), 0);
    expect(layout.place(LaneKind.top, width: 50, at: 1), 1);
    expect(layout.place(LaneKind.top, width: 50, at: 2), isNull);
    expect(layout.place(LaneKind.bottom, width: 50, at: 2), 1);
    expect(layout.place(LaneKind.bottom, width: 50, at: 2), 0);
    expect(layout.place(LaneKind.bottom, width: 50, at: 3), isNull);
  });

  test('static lane frees after its duration', () {
    final layout = LaneLayout(lanes: 1, width: 400, scrollDuration: 8, staticDuration: 4);
    expect(layout.place(LaneKind.top, width: 50, at: 10), 0);
    expect(layout.place(LaneKind.top, width: 50, at: 13.9), isNull);
    expect(layout.place(LaneKind.top, width: 50, at: 14), 0);
  });

  test('reset clears every lane and takes the new geometry', () {
    final layout = LaneLayout(lanes: 1, width: 400, scrollDuration: 8);
    expect(layout.place(LaneKind.scroll, width: 100, at: 0), 0);
    expect(layout.place(LaneKind.top, width: 100, at: 0), 0);
    expect(layout.place(LaneKind.scroll, width: 100, at: 0.1), isNull);
    layout.reset(lanes: 2, width: 800, scrollDuration: 6);
    expect(layout.place(LaneKind.scroll, width: 100, at: 0.1), 0);
    expect(layout.place(LaneKind.scroll, width: 100, at: 0.1), 1);
    expect(layout.place(LaneKind.top, width: 100, at: 0.1), 0);
  });

  test('zero lanes places nothing', () {
    final layout = LaneLayout(lanes: 0, width: 400, scrollDuration: 8);
    expect(layout.place(LaneKind.scroll, width: 10, at: 0), isNull);
    expect(layout.place(LaneKind.top, width: 10, at: 0), isNull);
    expect(layout.place(LaneKind.bottom, width: 10, at: 0), isNull);
  });

  test('a heavy segment filters and lays out quickly', () {
    const words = ['哈哈哈', '前方高能', '666', 'awsl', '名场面', '好家伙', '泪目', '太强了'];
    final elems = <DanmakuElem>[];
    var seed = 42;
    int random(int bound) {
      // Dart ints wrap at 64 bits, matching Swift's &* and &+ on UInt64; >>> is the unsigned shift.
      seed = seed * 6364136223846793005 + 1442695040888963407;
      return (seed >>> 33) % bound;
    }

    const modes = [1, 1, 1, 1, 4, 5, 6, 7];
    for (var i = 0; i < 20000; i++) {
      elems.add(
        DanmakuElem(
          id: i,
          progressMs: random(360000),
          mode: modes[random(modes.length)],
          color: random(5) == 0 ? 0xFF0000 : 0xFFFFFF,
          midHash: random(500).toRadixString(16),
          content: words[random(words.length)] + random(3000).toString(),
        ),
      );
    }
    const options = DanmakuFilterOptions(
      blockFixed: true,
      blockScroll: false,
      blockColored: true,
      blockAdvanced: true,
      blockCount: false,
      dedupe: true,
      hideBottom: true,
    );
    const rules = [
      BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: '泪目1'),
      BlockRule(id: 2, kind: BlockRuleKind.regex, filter: r'/awsl2\d+/'),
      BlockRule(id: 3, kind: BlockRuleKind.user, filter: '1f4'),
    ];

    final watch = Stopwatch()..start();
    final shown = DanmakuFilter.apply(elems, options: options, rules: rules, ownHash: 'abc');
    final layout = LaneLayout(lanes: 30, width: 800, scrollDuration: 7);
    var placed = 0;
    for (final item in shown) {
      // runes stand in for Swift's Character count; the words here have no multi-code-point graphemes.
      if (layout.place(LaneKind.scroll, width: item.text.runes.length * 25.0, at: item.elem.progressMs / 1000) !=
          null) {
        placed += 1;
      }
    }
    watch.stop();

    expect(shown.length, greaterThan(1000));
    expect(placed, greaterThan(0));
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });
}
