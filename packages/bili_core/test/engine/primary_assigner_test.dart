import 'package:bili_core/src/engine/primary_assigner.dart';
import 'package:test/test.dart';

/// Swift's `ObjectIdentifier(Key())`: a trial key nothing else shares.
final class _Key {}

void main() {
  test('weighted turns and trials at the end', () {
    const speeds = {'A': 10.0, 'B': 5.0, 'C': 0.0};
    final result = PrimaryAssigner().assign(
      urls: ['A', 'B', 'C'],
      count: 8,
      speed: (url) => speeds[url] ?? 0,
      trialKey: _Key(),
    );
    expect(result, ['A', 'B', 'A', 'A', 'B', 'A', 'C', 'C']);
  });

  test('a very slow node gets nothing', () {
    const speeds = {'A': 120.0, 'B': 5.0};
    final result = PrimaryAssigner().assign(
      urls: ['A', 'B'],
      count: 4,
      speed: (url) => speeds[url] ?? 0,
      trialKey: _Key(),
    );
    expect(result, ['A', 'A', 'A', 'A']);
  });

  test('a full node sits out while another has room', () {
    const a = 'https://a.example/v';
    const b = 'https://b.example/v';
    const speeds = {a: 10.0, b: 5.0};
    // a has room for two more pieces.
    final result = PrimaryAssigner().assign(
      urls: [a, b],
      count: 6,
      speed: (url) => speeds[url] ?? 0,
      trialKey: _Key(),
      isFull: (url, placed) => url == a && placed >= 2,
    );
    expect(result, [a, b, a, b, b, b]);
    final unmeasured = PrimaryAssigner().assign(
      urls: [a, b],
      count: 4,
      speed: (_) => 0,
      trialKey: _Key(),
      isFull: (url, placed) => url == a && placed >= 1,
    );
    expect(unmeasured, [a, b, b, b]);
  });

  test('turns go on as usual when every node is full', () {
    const speeds = {'A': 10.0, 'B': 5.0, 'C': 0.0};
    final result = PrimaryAssigner().assign(
      urls: ['A', 'B', 'C'],
      count: 8,
      speed: (url) => speeds[url] ?? 0,
      trialKey: _Key(),
      isFull: (_, _) => true,
    );
    expect(result, ['A', 'B', 'A', 'A', 'B', 'A', 'C', 'C']);
  });

  test('round robin without measurements rotates per range', () {
    final assigner = PrimaryAssigner();
    final key = _Key();
    expect(assigner.assign(urls: ['a', 'b', 'c'], count: 4, speed: (_) => 0, trialKey: key), ['a', 'b', 'c', 'a']);
    expect(assigner.assign(urls: ['a', 'b', 'c'], count: 4, speed: (_) => 0, trialKey: key), ['b', 'c', 'a', 'b']);
  });

  test('small ranges give an unknown node a trial every fourth', () {
    final assigner = PrimaryAssigner();
    final owner = _Key();
    const speeds = {'A': 10.0};
    final results = [
      for (var range = 0; range < 4; range++)
        assigner.assign(urls: ['A', 'C'], count: 2, speed: (url) => speeds[url] ?? 0, trialKey: owner),
    ];
    expect(results, [
      ['A', 'A'],
      ['A', 'A'],
      ['A', 'A'],
      ['A', 'C'],
    ]);
  });

  // Swift runs these on many threads at once to prove the trial count's read-modify-write is atomic. One isolate
  // runs each assignment whole, so interleaving them as separate tasks is the closest equivalent.
  test('concurrent ranges never lose a trial turn', () async {
    final assigner = PrimaryAssigner();
    final key = _Key();
    var trials = 0;
    await Future.wait([
      for (var iteration = 0; iteration < 400; iteration++)
        Future(() {
          final result = assigner.assign(
            urls: ['A', 'C'],
            count: 2,
            speed: (url) => url == 'A' ? 10 : 0,
            trialKey: key,
          );
          if (result.last == 'C') trials += 1;
        }),
    ]);
    expect(trials, 100);
  });
}
