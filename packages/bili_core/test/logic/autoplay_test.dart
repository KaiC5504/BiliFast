import 'package:bili_core/logic.dart';
import 'package:test/test.dart';

void main() {
  const a = PlayItem(bvid: 'A', cid: 1);
  const b = PlayItem(bvid: 'B', cid: 2);
  const c = PlayItem(bvid: 'C', cid: 3);

  NextStep next(PlayItem after, List<PlayItem> parts, List<PlayItem> episodes, bool autoplay, LoopMode loop) =>
      Autoplay.next(after: after, parts: parts, episodes: episodes, autoplay: autoplay, loop: loop);

  test('autoplay walks sections and stops at the end', () {
    expect(next(a, [a], [a, b, c], true, LoopMode.none), NextStep.play(b));
    expect(next(c, [c], [a, b, c], true, LoopMode.none), NextStep.stop);
    expect(next(c, [c], [a, b, c], false, LoopMode.list), NextStep.play(a));
    expect(next(b, [b], [a, b, c], false, LoopMode.none), NextStep.stop);
    expect(next(b, [b], [a, b, c], true, LoopMode.single), NextStep.replay);
  });

  test('autoplay prefers the next part', () {
    const p1 = PlayItem(bvid: 'A', cid: 11), p2 = PlayItem(bvid: 'A', cid: 12);
    expect(next(p1, [p1, p2], [], true, LoopMode.none), NextStep.play(p2));
    expect(next(p1, [p1, p2], [p1, b], true, LoopMode.none), NextStep.play(p2));
    expect(next(p1, [p1, p2], [p1, b], false, LoopMode.list), NextStep.play(p2));
  });

  test('last part moves on to the next episode by bvid', () {
    const p1 = PlayItem(bvid: 'A', cid: 11), p2 = PlayItem(bvid: 'A', cid: 12);
    expect(next(p2, [p1, p2], [p1, b, c], true, LoopMode.none), NextStep.play(b));
  });

  test('episode is found by cid before bvid', () {
    const e1 = PlayItem(bvid: 'A', cid: 1), e2 = PlayItem(bvid: 'A', cid: 2), e3 = PlayItem(bvid: 'A', cid: 3);
    expect(next(e2, [e2], [e1, e2, e3], true, LoopMode.none), NextStep.play(e3));
  });

  test('list loop wraps to the first part without episodes', () {
    const p1 = PlayItem(bvid: 'A', cid: 11), p2 = PlayItem(bvid: 'A', cid: 12);
    expect(next(p2, [p1, p2], [], false, LoopMode.list), NextStep.play(p1));
  });

  test('list loop of one item replays', () {
    expect(next(a, [a], [], false, LoopMode.list), NextStep.replay);
    expect(next(a, [a], [a], true, LoopMode.list), NextStep.replay);
  });

  test('list loop outside the collection stays with the video', () {
    const x = PlayItem(bvid: 'X', cid: 9);
    expect(next(x, [x], [a, b, c], true, LoopMode.list), NextStep.replay);
  });

  test('nothing after a standalone video stops', () {
    expect(next(a, [a], [], true, LoopMode.none), NextStep.stop);
    expect(next(a, [], [], true, LoopMode.none), NextStep.stop);
  });

  test('single loop replays even with autoplay off', () {
    expect(next(a, [a], [a, b], false, LoopMode.single), NextStep.replay);
  });

  test('loop mode raw values', () {
    expect(LoopMode.values.map((mode) => mode.name), ['single', 'list', 'none']);
  });
}
