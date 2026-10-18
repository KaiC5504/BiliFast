import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/speedtest/speed_test_plan.dart';
import 'package:bilifast/speedtest/speed_test_results.dart';
import 'package:bilifast/speedtest/speed_test_runner.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_target.dart';

const video = 'BV1GJ411x7h7';

void main() {
  late FakeTarget target;
  late FakeHooks hooks;
  late MemorySink logs;

  setUp(() {
    target = FakeTarget();
    hooks = FakeHooks(planWith());
    logs = MemorySink();
  });

  SpeedTestRunner make({int Function()? seed, int Function()? rss, bool shared = false}) => SpeedTestRunner(
        target: target,
        hooks: hooks.hooks,
        sharedTarget: shared,
        logger: Logger(session: 'test')..add(logs),
        newSeed: seed,
        rss: rss ?? () => 100 * 1024 * 1024,
      );

  List<LogEvent> events(String msg) => logs.events.where((event) => event.msg == msg).toList();

  Object? field(LogEvent event, String name) => switch (event.f[name]) {
        LogInt(:final value) => value,
        LogDouble(:final value) => value,
        LogString(:final value) => value,
        LogBool(:final value) => value,
        null => null,
      };

  /// Runs [body] on a fake clock with the target's timeline on it.
  void onFakeClock(void Function(FakeAsync async) body) => fakeAsync((async) {
        target.now = () => async.elapsed;
        body(async);
      });

  test('ABBA: one open as a warm-up, then a cold replay on each pass\'s engine, the same steps each time, all logged', () {
    onFakeClock((async) {
      final runner = make();
      var finished = false;
      runner.start(links: [video]).then((_) => finished = true);
      async.elapse(const Duration(minutes: 5));
      expect(finished, isTrue);
      expect(runner.running, isFalse);
      expect(runner.step, '完成');

      expect(hooks.engines, ['A', 'A', 'B', 'B', 'A', 'app'],
          reason: 'the warm-up open, a fresh engine every pass, then the app\'s own');
      expect(target.calls.where((call) => call.startsWith('open')), ['open $video']);
      expect(target.calls.where((call) => call.startsWith('replay')), List.filled(4, 'replay 120'),
          reason: 'the first pass replays too, so no first frame carries the playurl call');
      expect(target.playurlCalls, 1);
      expect(target.calls.take(4), ['muted true', 'awake true', 'useEngine', 'quality 120']);
      expect(target.calls.reversed.take(5).toList().reversed,
          ['muted false', 'awake false', 'rate 1.0', 'useEngine', 'quality 120']);
      expect(target.calls.where((call) => call == 'rate 2.0'), hasLength(4));

      final results = runner.results;
      expect(results.map((pass) => pass.variant), ['A', 'B', 'B', 'A']);
      for (final pass in results) {
        expect(pass.counts, isTrue);
        expect(pass.firstFrameMs, 800);
        expect(pass.msOf(StepKind.tap), [300, 300]);
        expect(pass.msOf(StepKind.hint), [300]);
        expect(pass.msOf(StepKind.back), [300]);
        expect(pass.quality, 120);
        expect(pass.codec, 'HEVC');
      }
      final groups = GroupSummary.of(results);
      expect(groups.map((group) => (group.variant, group.quality, group.cold, group.passes)),
          [('A', 120, true, 1), ('A', 120, false, 1), ('B', 120, false, 2)]);

      final start = events('speedtest start').single;
      expect(field(start, 'plan'), 'test-1');
      expect(field(start, 'source'), 'builtin');
      expect(field(start, 'passes'), 4);
      expect(field(start, 'videos'), 1);
      final passes = events('speedtest pass');
      expect(passes.map((event) => field(event, 'variant')), ['A', 'B', 'B', 'A']);
      expect(passes.map((event) => field(event, 'cold')), [true, false, false, false]);
      expect(field(passes[1], 'connectionsPerHost'), 4);
      expect(field(passes[1], 'overrides'), '{"peakBandwidth":true}');
      expect(field(passes[0], 'overrides'), '{}');
      expect(passes.every((event) => field(event, 'bvid') == video && field(event, 'seed') is int), isTrue);
      expect(events('speedtest step'), hasLength(4 * 5));
      expect(events('speedtest step').first.cat, LogCategory.app);
      final done = events('speedtest pass done');
      expect(done, hasLength(4));
      expect(field(done.first, 'firstFrameMs'), 800);
      expect(field(done.first, 'seekMedianMs'), 300);
      expect(field(done.first, 'seekP90Ms'), 300);
      expect(field(done.first, 'seekMaxMs'), 300);
      expect(field(done.first, 'backMedianMs'), 300);
      expect(field(done.first, 'rssMaxMB'), 100);
      expect(field(done.first, 'skipped'), isFalse);
      expect(field(events('speedtest done').single, 'passes'), 4);
      expect(field(events('speedtest done').single, 'cancelled'), isFalse);
    });
  });

  test('tap and hint seeks land fresh: inside the video, 30 s from every spot the pass played', () {
    onFakeClock((async) {
      hooks.plan = planWith({'seeks': 6, 'hints': 2, 'backJumps': 2, 'fastSeconds': 0});
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(minutes: 10));
      for (final pass in runner.results) {
        final played = <double>[0];
        for (final step in pass.steps.where((step) => step.kind != StepKind.first)) {
          if (step.kind == StepKind.back) {
            expect(step.to, played.last - 15, reason: 'back 15 s from where the last seek landed');
          } else {
            expect(step.to, inInclusiveRange(10, 580));
            for (final spot in played) {
              expect((step.to - spot).abs(), greaterThanOrEqualTo(30));
            }
          }
          played.add(step.to);
        }
        expect(pass.msOf(StepKind.tap), hasLength(6));
      }
    });
  });

  test('a hint rests 300 ms on the target before the seek', () {
    onFakeClock((async) {
      make().start(links: [video]);
      async.elapse(const Duration(minutes: 5));
      final hint = target.timeline.firstWhere((entry) => entry.$2.startsWith('hint'));
      final seek = target.timeline.firstWhere((entry) => entry.$1 >= hint.$1 && entry.$2.startsWith('seek'));
      expect(seek.$2, 'seek ${hint.$2.substring(5)}');
      expect(seek.$1 - hint.$1, 300);
    });
  });

  test('the seed of each pass is logged and decides its targets', () {
    onFakeClock((async) {
      final runner = make(seed: () => 42);
      runner.start(links: [video]);
      async.elapse(const Duration(minutes: 5));
      expect(events('speedtest pass').map((event) => field(event, 'seed')), everyElement(42));
      final targets = runner.results.map((pass) => pass.steps.map((step) => step.to).join(',')).toSet();
      expect(targets, hasLength(1));
    });
  });

  test('a video too short for every seek makes fewer and says so', () {
    onFakeClock((async) {
      target.duration = 70;
      hooks.plan = planWith({'order': 'A', 'seeks': 3, 'hints': 0});
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(minutes: 5));
      expect(runner.results.single.msOf(StepKind.tap), hasLength(1));
      expect(runner.notes.single, contains('1/3'));
      final short = events('speedtest short video').single;
      expect(field(short, 'wanted'), 3);
      expect(field(short, 'made'), 1);
    });
  });

  test('a seek that never resumes times out after 15 s, counts as 15 s, and the pass goes on', () {
    onFakeClock((async) {
      var seeks = 0;
      target.seekMs = (_) => ++seeks == 1 ? null : 300;
      hooks.plan = planWith({'order': 'A'});
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(minutes: 5));
      final pass = runner.results.single;
      expect(pass.counts, isTrue);
      expect(pass.timeouts, 1);
      expect(pass.msOf(StepKind.tap), [15000, 300]);
      final step = events('speedtest step').firstWhere((event) => field(event, 'kind') == 'tap');
      expect(field(step, 'timedOut'), isTrue);
      expect(field(step, 'ms'), 15000);
      expect(field(events('speedtest pass done').single, 'timeouts'), 1);
    });
  });

  test('no first frame within 20 s fails the pass, and the next pass runs', () {
    onFakeClock((async) {
      // The warm-up open's first frame, then none for the first pass.
      target.firstFrames.addAll([800, null]);
      hooks.plan = planWith({'order': 'AB'});
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(seconds: 19));
      expect(runner.results.single.failed, isFalse);
      async.elapse(const Duration(minutes: 5));
      expect(runner.results.map((pass) => (pass.failed, pass.failure)), [(true, '首帧超时'), (false, null)]);
      final first = events('speedtest step').first;
      expect(field(first, 'kind'), 'first');
      expect(field(first, 'timedOut'), isTrue);
    });
  });

  test('a playback that fails mid-pass fails that pass only', () {
    onFakeClock((async) {
      var seeks = 0;
      target.seekMs = (_) {
        if (++seeks > 1) return 300;
        target.phase = PlaybackPhase.failed;
        return null;
      };
      hooks.plan = planWith({'order': 'AB'});
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(milliseconds: 2100));
      expect(runner.results.first.failed, isTrue, reason: 'seen well within the 15 s seek timeout');
      async.elapse(const Duration(minutes: 5));
      expect(runner.results.map((pass) => pass.failed), [true, false]);
      expect(events('speedtest step').where((event) => field(event, 'pass') == 1).map((event) => field(event, 'kind')),
          ['first'],
          reason: 'the failed seek is not logged as a timeout');
    });
  });

  test('a video that does not open fails its passes without replays; the next video still runs', () {
    onFakeClock((async) {
      target.failToOpen.add('BVbroken');
      hooks.plan = planWith({'order': 'AB'});
      final runner = make();
      runner.start(links: ['BVbroken', video]);
      async.elapse(const Duration(minutes: 5));
      expect(runner.results.map((pass) => pass.failed), [true, true, false, false]);
      expect(target.calls.where((call) => call.startsWith('open') || call.startsWith('replay')),
          ['open BVbroken', 'open $video', 'replay 120', 'replay 120']);
    });
  });

  test('a video whose playurl fails costs one call, not one a pass', () {
    onFakeClock((async) {
      target.failPlayurl.add('BVlocked');
      hooks.plan = planWith({'order': 'ABBBBA'});
      final runner = make();
      runner.start(links: ['BVlocked']);
      async.elapse(const Duration(minutes: 5));
      expect(runner.results.map((pass) => pass.failure), List.filled(6, '视频打不开'));
      expect(target.playurlCalls, 1);
      expect(target.calls.where((call) => call.startsWith('replay')), isEmpty);
    });
  });

  test('a pass that fails loses the playurl answer: the next asks once, and a second failure gives the video up', () {
    onFakeClock((async) {
      target.failReplays.addAll([1, 2]);
      hooks.plan = planWith({'order': 'ABBA'});
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(minutes: 5));
      expect(runner.results.map((pass) => pass.failure), ['播放失败', '播放失败', '视频打不开', '视频打不开']);
      expect(target.playurlCalls, 2, reason: 'the open, then one more after the first failure');
    });
  });

  test('a failed pass costs one playurl call, and the passes after it run', () {
    onFakeClock((async) {
      target.failReplays.add(1);
      hooks.plan = planWith({'order': 'ABBA'});
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(minutes: 5));
      expect(runner.results.map((pass) => pass.failed), [true, false, false, false]);
      expect(target.playurlCalls, 2);
    });
  });

  test('the run plays in BTR mode and puts the mode back', () {
    onFakeClock((async) {
      target.mode = PlaybackMode.direct;
      make().start(links: [video]);
      async.elapse(const Duration(minutes: 5));
      final calls = target.calls;
      expect(calls.indexOf('mode btr'), lessThan(calls.indexOf('open $video')));
      expect(calls.last, 'mode direct');
      expect(target.mode, PlaybackMode.direct);
    });
  });

  test('a pass that fell back to direct does not count as its variant', () {
    onFakeClock((async) {
      target.fallBackOnReplays.add(2);
      hooks.plan = planWith({'order': 'AB'});
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(minutes: 5));
      expect(runner.results.map((pass) => (pass.failed, pass.failure)), [(false, null), (true, '回退到直连')]);
    });
  });

  test('a quality the video lacks plays the next one down once per variant; its repeat is skipped', () {
    onFakeClock((async) {
      target.maxQuality = 120;
      hooks.plan = planWith({'qualities': [127, 120], 'order': 'AB'});
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(minutes: 5));
      expect(runner.results.map((pass) => (pass.variant, pass.askedQuality, pass.quality, pass.skipped)), [
        ('A', 127, 120, false),
        ('B', 127, 120, false),
        ('A', 120, 120, true),
        ('B', 120, 120, true),
      ]);
      expect(runner.results[2].steps, isEmpty);
      expect(field(events('speedtest pass done')[2], 'skipped'), isTrue);
      expect(GroupSummary.of(runner.results).map((group) => group.passes), [1, 1]);
    });
  });

  test('stalls are counted per pass, separately at the fast rate, with memory warnings and the RSS peak', () {
    onFakeClock((async) {
      hooks.plan = planWith({'order': 'A', 'seeks': 0, 'hints': 0, 'backJumps': 0, 'fastSeconds': 10});
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(milliseconds: 1200));
      target.emit(const Stall(1));
      target.emit(const MemoryWarning(900 * 1024 * 1024));
      async.elapse(const Duration(seconds: 2));
      target.emit(const Stall(5));
      async.elapse(const Duration(minutes: 1));
      final pass = runner.results.single;
      expect(pass.stalls, 2);
      expect(pass.fastStalls, 1);
      expect(pass.memoryWarnings, 1);
      final done = events('speedtest pass done').single;
      expect(field(done, 'rssMaxMB'), 900);
      expect(field(done, 'fastStalls'), 1);
    });
  });

  test('stop ends the run at once, drops the unfinished pass and puts everything back', () {
    onFakeClock((async) {
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(milliseconds: 1500));
      expect(runner.running, isTrue);
      runner.stop();
      async.elapse(const Duration(seconds: 1));
      expect(runner.running, isFalse);
      expect(runner.cancelled, isTrue);
      expect(runner.step, '已停止');
      expect(runner.results, isEmpty);
      expect(target.calls.reversed.take(5).toList().reversed,
          ['muted false', 'awake false', 'rate 1.0', 'useEngine', 'quality 120']);
      expect(events('speedtest pass done'), isEmpty);
      final done = events('speedtest done').single;
      expect(field(done, 'cancelled'), isTrue);
      expect(field(done, 'passes'), 0);
    });
  });

  test('a page that goes away mid-run gets sound and screen back at once, and the engine is left alone', () {
    onFakeClock((async) {
      final runner = make();
      runner.start(links: [video]);
      async.elapse(const Duration(milliseconds: 1500));
      runner.dispose();
      async.flushMicrotasks();
      expect(target.calls, containsAllInOrder(['muted false', 'awake false']));
      final calls = target.calls.length;
      async.elapse(const Duration(minutes: 1));
      expect(target.calls.skip(calls), isNot(contains('useEngine')));
      expect(hooks.engines, ['A', 'A'], reason: 'the warm-up open and the first pass, not the app\'s');
    });
  });

  test('on a shared player, a page that goes away mid-run puts the app engine, quality and mode back once', () {
    onFakeClock((async) {
      target
        ..selectedQuality = 80
        ..mode = PlaybackMode.direct;
      final runner = make(shared: true);
      runner.start(links: [video]);
      async.elapse(const Duration(milliseconds: 1500));
      final calls = target.calls.length;
      runner.dispose();
      async.flushMicrotasks();
      expect(target.calls.skip(calls),
          containsAllInOrder(['muted false', 'awake false', 'useEngine', 'quality 80', 'mode direct']));
      expect(hooks.engines.last, 'app');
      expect(target.selectedQuality, 80);
      expect(target.mode, PlaybackMode.direct);
      async.elapse(const Duration(minutes: 1));
      expect(target.calls.skip(calls).where((call) => call == 'useEngine'), hasLength(1));
      expect(hooks.engines.where((engine) => engine == 'app'), hasLength(1));
    });
  });

  test('the sound is left as the run found it: a muted player stays muted', () {
    onFakeClock((async) {
      target.muted = true;
      make().start(links: [video]);
      async.elapse(const Duration(minutes: 5));
      expect(target.calls.where((call) => call.startsWith('muted')), ['muted true', 'muted true']);
      expect(target.muted, isTrue);
    });
  });

  test('without links the plan\'s videos are used, then the video that is open', () {
    onFakeClock((async) {
      hooks.plan = planWith({'order': 'A', 'videos': ['BVfromplan']});
      make().start(links: const []);
      async.elapse(const Duration(minutes: 1));
      expect(target.calls, contains('open BVfromplan'));

      target
        ..calls.clear()
        ..bvid = 'BVcurrent';
      hooks.plan = planWith({'order': 'A'});
      make().start(links: const []);
      async.elapse(const Duration(minutes: 1));
      expect(target.calls, contains('open BVcurrent'));
    });
  });

  test('with no video at all, or a plan refused, nothing runs and the page says why', () {
    onFakeClock((async) {
      final runner = make();
      runner.start(links: const []);
      async.elapse(const Duration(seconds: 1));
      expect(runner.running, isFalse);
      expect(runner.error, contains('没有要测的视频'));
      expect(target.calls, isEmpty);

      hooks.planError = const SpeedTestPlanError('方案 B 的 config 有引擎不认识或类型不对的项：typo');
      runner.start(links: [video]);
      async.elapse(const Duration(seconds: 1));
      expect(runner.error, contains('typo'));
      expect(target.calls, isEmpty);
      expect(field(events('speedtest plan refused').single, 'error'), contains('typo'));
    });
  });
}
