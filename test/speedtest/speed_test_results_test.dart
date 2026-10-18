import 'package:bilifast/speedtest/speed_test_results.dart';
import 'package:flutter_test/flutter_test.dart';

PassResult pass(String variant, int quality,
    {double? first,
    List<double> taps = const [],
    List<double> backs = const [],
    int stalls = 0,
    int rssMB = 0,
    bool cold = false}) {
  final result = PassResult(pass: 1, variant: variant, askedQuality: quality, bvid: 'BV1', seed: 1, cold: cold)
    ..firstFrameMs = first
    ..stalls = stalls
    ..rssMaxBytes = rssMB * 1024 * 1024;
  for (final ms in taps) {
    result.steps.add(StepResult(kind: StepKind.tap, to: 100, ms: ms, timedOut: ms >= 15000));
  }
  for (final ms in backs) {
    result.steps.add(StepResult(kind: StepKind.back, to: 50, ms: ms, timedOut: false));
  }
  return result;
}

void main() {
  test('median, nearest-rank P90', () {
    expect(median([]), isNull);
    expect(median([3, 1, 2]), 2);
    expect(median([4, 1, 3, 2]), 2.5);
    expect(p90([]), isNull);
    expect(p90([for (var i = 1; i <= 10; i++) i.toDouble()]), 9);
    expect(p90([1, 2, 3]), 3);
  });

  test('groups pool each variant and played quality, in run order, leaving out skipped and failed passes', () {
    final results = [
      pass('A', 127, first: 1000, taps: [400, 600], backs: [100], stalls: 1, rssMB: 700),
      pass('B', 127, first: 800, taps: [300, 15000], stalls: 0, rssMB: 750),
      pass('B', 120, first: 500, taps: [200]),
      pass('A', 127, first: 1200, taps: [500], backs: [300], stalls: 2, rssMB: 650),
      pass('A', 127, first: 1)..skipped = true,
      pass('B', 127, first: 1)..failed = true,
    ];
    final groups = GroupSummary.of(results);
    expect(groups.map((group) => (group.variant, group.quality, group.passes)),
        [('A', 127, 2), ('B', 127, 1), ('B', 120, 1)]);
    final a = groups.first;
    expect(a.firstFrameMs, 1100);
    expect(a.seekMedianMs, 500);
    expect(a.seekP90Ms, 600);
    expect(a.seekMaxMs, 600);
    expect(a.backMedianMs, 200);
    expect(a.stalls, 3);
    expect(a.rssMaxMB, 700);
    final b = groups[1];
    expect(b.timeouts, 1);
    expect(b.seekMaxMs, 15000);

    final deltas = GroupDelta.of(groups);
    expect(deltas, hasLength(1), reason: 'B at 4K has no A to compare with');
    final delta = deltas.single;
    expect((delta.base.variant, delta.other.variant, delta.base.quality), ('A', 'B', 127));
    expect(delta.firstFrameMs, -300);
    expect(delta.seekMedianMs, (300 + 15000) / 2 - 500);
    expect(delta.backMedianMs, isNull);
    expect(delta.stalls, -3);
    expect(delta.rssMaxMB, 50);
  });

  test('cold passes get their own rows, before the warm ones, and are compared only with cold', () {
    final results = [
      pass('A', 127, taps: [8000], cold: true),
      pass('B', 127, taps: [300]),
      pass('A', 127, taps: [400]),
      pass('B', 127, taps: [5000], cold: true),
    ];
    final groups = GroupSummary.of(results);
    expect(groups.map((group) => (group.variant, group.cold, group.seekMedianMs)),
        [('A', true, 8000), ('A', false, 400), ('B', true, 5000), ('B', false, 300)]);
    expect(GroupDelta.of(groups).map((delta) => (delta.base.cold, delta.other.cold, delta.seekMedianMs)),
        [(true, true, -3000), (false, false, -100)]);
  });
}
