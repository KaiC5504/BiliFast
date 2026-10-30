import 'dart:convert';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/offline/disk/background_plan.dart';
import 'package:bilifast/offline/disk/background_trials.dart';
import 'package:flutter_test/flutter_test.dart';

const mib = 1 << 20;

/// Answers each draw from [doubles] and [ints] in turn, and keeps the bounds [nextInt] was asked with.
final class ScriptedRandom implements math.Random {
  ScriptedRandom({List<double> doubles = const [], List<int> ints = const []})
    : _doubles = List.of(doubles),
      _ints = List.of(ints);

  final List<double> _doubles;
  final List<int> _ints;
  final intBounds = <int>[];

  @override
  double nextDouble() => _doubles.removeAt(0);

  @override
  int nextInt(int max) {
    intBounds.add(max);
    return _ints.removeAt(0);
  }

  @override
  bool nextBool() => throw UnimplementedError();
}

BackgroundTrip trip(
  BackgroundArm arm, {
  double mbps = 1,
  double seconds = 60,
  bool allDone = false,
  int minute = 0,
  int wasted = 0,
  double? endedAfter,
  bool spoiled = false,
}) => BackgroundTrip(
  arm: arm,
  at: DateTime(2026, 10, 31, 12).add(Duration(minutes: minute)),
  seconds: seconds,
  gainedBytes: (mbps * seconds * mib).round(),
  wastedBytes: wasted,
  allDone: allDone,
  continuedEndedAfter: endedAfter,
  spoiled: spoiled,
);

/// Never explores: every draw lands past [BackgroundTrials.exploreChance].
BackgroundTrials noExplore() => BackgroundTrials(random: _Steady());

final class _Steady implements math.Random {
  @override
  double nextDouble() => 0.99;

  @override
  int nextInt(int max) => throw StateError('no explore expected');

  @override
  bool nextBool() => throw UnimplementedError();
}

void main() {
  const continued = BackgroundArm.continuedArm;
  final [h128, h64, h32] = BackgroundArm.handOffArms;

  group('arms', () {
    test("are continued and the three hand-offs, 1.3.0 (4)'s first, named as kept", () {
      expect(BackgroundTrials.arms.map((arm) => arm.name), [
        'continued',
        'handoff-3x128',
        'handoff-2x64',
        'handoff-6x32',
      ]);
      expect(BackgroundArm.fallback, h128);
      for (final arm in BackgroundTrials.arms) {
        expect(BackgroundArm.parse(arm.name), arm);
      }
    });
  });

  group('scored', () {
    test('a trip counts from 20 s away, and not when the downloads ran out', () {
      expect(trip(h128, seconds: 19.9).scored, isFalse);
      expect(trip(h128, seconds: 20).scored, isTrue);
      expect(trip(h128, seconds: 600).scored, isTrue);
      expect(trip(h128, seconds: 600, allDone: true).scored, isFalse);
    });

    test('a spoiled trip never counts, however long', () {
      expect(trip(h128, seconds: 600, spoiled: true).scored, isFalse);
    });

    test('its rate is MiB a second away', () {
      expect(trip(h128, mbps: 2.5, seconds: 40).mbps, closeTo(2.5, 1e-9));
      expect(
        BackgroundTrip(
          arm: h128,
          at: DateTime.utc(2026),
          seconds: 0,
          gainedBytes: mib,
          wastedBytes: 0,
          allDone: false,
        ).mbps,
        0,
      );
    });
  });

  group('stats', () {
    test('nothing scored: no mean', () {
      final trials = noExplore()
        ..record(trip(h128, seconds: 10))
        ..record(trip(h128, allDone: true));
      expect(trials.stats(h128), (scored: 0, mbps: null));
      expect(trials.stats(continued), (scored: 0, mbps: null));
    });

    test('counts every scored trip of the arm, and means the last five', () {
      final trials = noExplore();
      for (final rate in [100.0, 100.0, 1.0, 2.0, 3.0, 4.0, 5.0]) {
        trials.record(trip(h64, mbps: rate));
      }
      trials
        ..record(trip(h64, mbps: 50, seconds: 5))
        ..record(trip(h64, mbps: 50, allDone: true))
        ..record(trip(h128, mbps: 50));

      final stats = trials.stats(h64);
      expect(stats.scored, 7);
      expect(stats.mbps, closeTo(3, 1e-9), reason: 'the two early 100s are out of the window; unscored trips never in');
      expect(trials.stats(h128).scored, 1);
      expect(trials.stats(h128).mbps, closeTo(50, 1e-9));
    });
  });

  group('choose', () {
    test("without continued: each hand-off untried in turn, 1.3.0 (4)'s first", () {
      final trials = noExplore()..record(trip(continued, mbps: 99));
      expect(trials.choose(continued: false), (arm: h128, why: 'untried'));

      trials.record(trip(h128, seconds: 10));
      expect(trials.choose(continued: false), (arm: h128, why: 'untried'), reason: 'a short trip tells nothing');

      trials.record(trip(h128));
      expect(trials.choose(continued: false), (arm: h64, why: 'untried'));

      trials.record(trip(h64));
      expect(trials.choose(continued: false), (arm: h32, why: 'untried'));

      trials.record(trip(h32, mbps: 4));
      expect(trials.choose(continued: false), (arm: h32, why: 'best'), reason: 'continued is not a candidate');
    });

    test('with continued: continued first, then each hand-off', () {
      final trials = noExplore();
      expect(trials.choose(continued: true), (arm: continued, why: 'untried'));

      trials.record(trip(continued));
      expect(trials.choose(continued: true), (arm: h128, why: 'untried'));

      trials
        ..record(trip(h128))
        ..record(trip(h64));
      expect(trials.choose(continued: true), (arm: h32, why: 'untried'));

      trials.record(trip(h32));
      expect(trials.choose(continued: true).why, 'best');
    });

    test('continued untried but not running: the hand-offs alone decide', () {
      final trials = noExplore()
        ..record(trip(h128, mbps: 1))
        ..record(trip(h64, mbps: 3))
        ..record(trip(h32, mbps: 2));
      expect(trials.choose(continued: false), (arm: h64, why: 'best'));
      expect(trials.choose(continued: true), (arm: continued, why: 'untried'));
    });

    test('everything tried: the highest mean, ties to the earlier in the list', () {
      final trials = noExplore()
        ..record(trip(continued, mbps: 2))
        ..record(trip(h128, mbps: 1))
        ..record(trip(h64, mbps: 3))
        ..record(trip(h32, mbps: 3));
      expect(trials.choose(continued: true), (arm: h64, why: 'best'));
      expect(trials.choose(continued: false), (arm: h64, why: 'best'));

      trials.record(trip(continued, mbps: 4));
      expect(trials.choose(continued: true), (arm: continued, why: 'best'), reason: 'mean (2 + 4) / 2 = 3, a tie');
      expect(trials.choose(continued: false), (arm: h64, why: 'best'));
    });

    test('explores below the chance: a candidate other than the best, picked uniformly', () {
      List<BackgroundTrip> tried() => [
        trip(continued, mbps: 5),
        trip(h128, mbps: 1),
        trip(h64, mbps: 2),
        trip(h32, mbps: 3),
      ];

      final random = ScriptedRandom(doubles: [0.1, 0.149, 0.15], ints: [0, 2]);
      final trials = BackgroundTrials(random: random);
      tried().forEach(trials.record);

      expect(trials.choose(continued: true), (arm: h128, why: 'explore'));
      expect(trials.choose(continued: true), (arm: h32, why: 'explore'));
      expect(random.intBounds, [3, 3], reason: 'the best is never among those explored');
      expect(trials.choose(continued: true), (arm: continued, why: 'best'), reason: 'the chance is 0.15, exclusive');

      final handOffs = ScriptedRandom(doubles: [0.0], ints: [1]);
      final second = BackgroundTrials(random: handOffs);
      tried().forEach(second.record);
      expect(second.choose(continued: false), (arm: h64, why: 'explore'), reason: 'h32 is the best hand-off');
      expect(handOffs.intBounds, [2]);
    });

    test('an arm whose long trips never score is forced at most three times', () {
      final trials = noExplore()
        ..record(trip(h128, allDone: true))
        ..record(trip(h128, seconds: 10))
        ..record(trip(h128, seconds: 19))
        ..record(trip(h128, spoiled: true));
      expect(trials.choose(continued: false), (arm: h128, why: 'untried'), reason: 'short trips are no attempt');

      trials.record(trip(h128, seconds: 20, spoiled: true));
      expect(trials.choose(continued: false), (arm: h64, why: 'untried'));
      expect(BackgroundTrials.maxAttempts, 3);
    });

    test('every candidate attempted and none scored: the first, as before any trial', () {
      final trials = noExplore();
      for (final arm in BackgroundTrials.arms) {
        for (var i = 0; i < BackgroundTrials.maxAttempts; i++) {
          trials.record(trip(arm, allDone: true));
        }
      }
      expect(trials.choose(continued: false), (arm: h128, why: 'fallback'));
      expect(trials.choose(continued: true), (arm: continued, why: 'fallback'));

      final random = ScriptedRandom(doubles: [0.1], ints: [1]);
      final exploring = BackgroundTrials(random: random)..load(trials.toJson());
      expect(exploring.choose(continued: false), (arm: h32, why: 'explore'), reason: 'among all but the first');
      expect(random.intBounds, [2]);
    });

    test('once every candidate has a full window, explores at the settled chance', () {
      List<BackgroundTrip> full() => [
        for (var i = 0; i < BackgroundTrials.window; i++) ...[
          trip(h128, mbps: 1, minute: i),
          trip(h64, mbps: 2, minute: i),
          trip(h32, mbps: 3, minute: i),
        ],
      ];

      final random = ScriptedRandom(doubles: [0.06, 0.049], ints: [0]);
      final settled = BackgroundTrials(random: random);
      full().forEach(settled.record);
      expect(settled.choose(continued: false), (arm: h32, why: 'best'), reason: '0.06 is past the settled chance');
      expect(settled.choose(continued: false), (arm: h128, why: 'explore'));
      expect(BackgroundTrials.settledExploreChance, 0.05);

      final unsettled = BackgroundTrials(
        random: ScriptedRandom(doubles: [0.06], ints: [0]),
      );
      [...full(), trip(continued, mbps: 1)].forEach(unsettled.record);
      expect(unsettled.choose(continued: true), (
        arm: continued,
        why: 'explore',
      ), reason: 'continued has one scored trip, so the full chance holds');
    });

    test('no explore while any candidate is untried', () {
      final random = ScriptedRandom();
      final trials = BackgroundTrials(random: random)..record(trip(h128));
      expect(trials.choose(continued: false), (arm: h64, why: 'untried'));
      expect(trials.choose(continued: true), (arm: continued, why: 'untried'));
    });

    test('with a seeded random: explores about 15% of choices, never the best, every other arm', () {
      final trials = BackgroundTrials(random: math.Random(7))
        ..record(trip(continued, mbps: 5))
        ..record(trip(h128, mbps: 1))
        ..record(trip(h64, mbps: 2))
        ..record(trip(h32, mbps: 3));

      final choices = [for (var i = 0; i < 4000; i++) trials.choose(continued: true)];
      final explored = choices.where((choice) => choice.why == 'explore').toList();
      expect(explored.length / choices.length, closeTo(BackgroundTrials.exploreChance, 0.03));
      expect(explored.map((choice) => choice.arm).toSet(), {h128, h64, h32});
      expect(choices.where((choice) => choice.why == 'best').map((choice) => choice.arm).toSet(), {continued});
    });
  });

  group('best', () {
    test('null before any arm has numbers', () {
      final trials = noExplore()..record(trip(h128, seconds: 5));
      expect(trials.best, isNull);
    });

    test('the highest mean over every arm', () {
      final trials = noExplore()
        ..record(trip(h128, mbps: 1))
        ..record(trip(h32, mbps: 6))
        ..record(trip(continued, mbps: 4));
      expect(trials.best, h32);
    });

    test('ties go to continued, then the hand-offs in order', () {
      final trials = noExplore()
        ..record(trip(h32, mbps: 2))
        ..record(trip(h64, mbps: 2));
      expect(trials.best, h64);

      trials.record(trip(h128, mbps: 2));
      expect(trials.best, h128);

      trials.record(trip(continued, mbps: 2));
      expect(trials.best, continued);
    });
  });

  group('bestHandOff', () {
    test('the fallback until a hand-off has numbers, whatever continued did', () {
      final trials = noExplore()
        ..record(trip(continued, mbps: 9))
        ..record(trip(h64, seconds: 10));
      expect(trials.bestHandOff(), BackgroundArm.fallback);
    });

    test('the best hand-off, never continued', () {
      final trials = noExplore()
        ..record(trip(continued, mbps: 9))
        ..record(trip(h128, mbps: 1))
        ..record(trip(h32, mbps: 2));
      expect(trials.bestHandOff(), h32);

      trials.record(trip(h64, mbps: 2));
      expect(trials.bestHandOff(), h64, reason: 'ties to the earlier hand-off');
    });
  });

  group('record', () {
    test('keeps the newest 200', () {
      final trials = noExplore();
      for (var i = 0; i < BackgroundTrials.keep + 5; i++) {
        trials.record(trip(h128, minute: i));
      }
      expect(trials.trips, hasLength(BackgroundTrials.keep));
      expect(trials.trips.first.at, trip(h128, minute: 5).at);
      expect(trials.trips.last.at, trip(h128, minute: BackgroundTrials.keep + 4).at);
    });

    test('over the cap, the oldest unscored trips go first, then the oldest scored', () {
      final trials = noExplore()..record(trip(h32, minute: 0));
      for (var i = 1; i < BackgroundTrials.keep; i++) {
        trials.record(trip(h128, minute: i, allDone: true));
      }
      trials.record(trip(h64, minute: 500));
      expect(trials.trips, hasLength(BackgroundTrials.keep));
      expect(trials.trips.first.arm, h32, reason: 'the oldest, but scored');
      expect(trials.trips[1].at, trip(h128, minute: 2).at);
      expect(trials.stats(h32).scored, 1);

      // 198 unscored left to drop, then one scored.
      for (var i = 0; i < 199; i++) {
        trials.record(trip(h64, minute: 1000 + i));
      }
      expect(trials.trips.every((trip) => trip.scored), isTrue);
      expect(trials.trips.first.at, trip(h64, minute: 500).at, reason: 'then the oldest scored');
      expect(trials.stats(h32).scored, 0);
    });

    test('a loaded file over the cap keeps its newest 200', () {
      final trials = noExplore()
        ..load({
          'trips': [for (var i = 0; i < 250; i++) trip(h64, minute: i).toJson()],
        });
      expect(trials.trips, hasLength(BackgroundTrials.keep));
      expect(trials.trips.first.at, trip(h64, minute: 50).at);
    });
  });

  group('json', () {
    test('round-trips every field through the file', () {
      final trials = noExplore()
        ..record(trip(continued, mbps: 3.25, seconds: 95.5, wasted: 7, endedAfter: 31.5))
        ..record(trip(h64, mbps: 1, seconds: 12, minute: 2))
        ..record(trip(h32, allDone: true, minute: 3))
        ..record(trip(h128, spoiled: true, minute: 4));

      final read = noExplore()..load(jsonDecode(jsonEncode(trials.toJson())));

      expect(read.toJson(), trials.toJson());
      expect(read.trips.map((trip) => trip.arm), [continued, h64, h32, h128]);
      final first = read.trips.first;
      expect(first.at, trials.trips.first.at);
      expect(first.seconds, 95.5);
      expect(first.gainedBytes, trials.trips.first.gainedBytes);
      expect(first.wastedBytes, 7);
      expect(first.continuedEndedAfter, 31.5);
      expect(read.trips[1].continuedEndedAfter, isNull);
      expect(read.trips[2].allDone, isTrue);
      expect(read.trips[2].spoiled, isFalse);
      expect(read.trips[3].spoiled, isTrue);
      expect(read.stats(continued), trials.stats(continued));
    });

    test('anything unreadable is skipped, never thrown', () {
      final good = trip(h128).toJson();
      final trials = noExplore();
      for (final junk in <Object?>[
        null,
        'trips',
        42,
        <Object?>[],
        {'trips': 'none'},
        {'other': <Object?>[]},
      ]) {
        trials.record(trip(h128));
        expect(trials.load(junk), isFalse, reason: '$junk');
        expect(trials.trips, isEmpty, reason: '$junk');
      }

      final read = trials.load({
        'trips': [
          null,
          7,
          'handoff-3x128',
          <Object?>[good],
          {...good, 'arm': 'turbo'},
          {...good, 'arm': 'handoff-3xbig'},
          {...good, 'arm': 3},
          {...good, 'at': '2026-10-31'},
          {...good, 'seconds': '60'},
          {...good, 'gained': 1.5},
          {...good, 'wasted': null},
          {...good}..remove('gained'),
          {...good, 'continuedEndedAfter': 'soon', 'allDone': 'yes', 'spoiled': 'yes'},
          good,
        ],
      });

      expect(read, isTrue);
      expect(trials.trips, hasLength(2));
      expect(trials.trips.first.continuedEndedAfter, isNull, reason: 'a wrong optional field reads as absent');
      expect(trials.trips.first.allDone, isFalse);
      expect(trials.trips.first.spoiled, isFalse);
      expect(BackgroundTrip.fromJson({...good}..remove('spoiled'))!.spoiled, isFalse, reason: 'files before it');
      expect(trials.trips.last.toJson(), good);
    });
  });

  group('summary', () {
    test('every arm and none best before any numbers', () {
      expect(noExplore().summary(), {
        'continued': '0/-',
        'handoff-3x128': '0/-',
        'handoff-2x64': '0/-',
        'handoff-6x32': '0/-',
        'best': 'none',
      });
    });

    test('scored count, mean to one decimal and the best', () {
      final trials = noExplore()
        ..record(trip(continued, mbps: 2.04))
        ..record(trip(continued, mbps: 3))
        ..record(trip(continued, mbps: 8, seconds: 5))
        ..record(trip(h64, mbps: 4.26));
      expect(trials.summary(), {
        'continued': '2/2.5',
        'handoff-3x128': '0/-',
        'handoff-2x64': '1/4.3',
        'handoff-6x32': '0/-',
        'best': 'handoff-2x64',
      });
      expect(trials.summary().keys.toList(), [...BackgroundTrials.arms.map((arm) => arm.name), 'best']);
    });
  });

  group('piece cap', () {
    List<int> sizes(List<ByteRange> pieces) => [for (final piece in pieces) piece.length ~/ mib];

    test('pieces grow to the cap and stay there', () {
      final gap = [ByteRange(0, 512 * mib - 1)];
      expect(sizes(backgroundPieces(gap, max: 32 * mib)), [16, 16, 32, ...List.filled(14, 32)]);
      expect(sizes(backgroundPieces(gap, max: 64 * mib)), [16, 16, 32, ...List.filled(7, 64)]);
      expect(sizes(backgroundPieces(gap)), [16, 16, 32, 64, 128, 128, 128]);
    });

    test('the next piece size by bytes queued', () {
      int size(int queuedMib, int maxMib) => backgroundPieceBytes(queuedMib * mib, max: maxMib * mib) ~/ mib;
      expect(
        [
          for (final queued in [0, 16, 32, 64, 128, 1024]) size(queued, 32),
        ],
        [16, 16, 32, 32, 32, 32],
      );
      expect(
        [
          for (final queued in [0, 16, 32, 64, 128, 1024]) size(queued, 64),
        ],
        [16, 16, 32, 64, 64, 64],
      );
      expect(size(0, 16), 16, reason: 'a cap at the first size keeps every piece at it');
      expect(size(1024, 16), 16);
    });

    test("the hand-off's ranges follow the cap asked for", () {
      DashStream stream(String name) => DashStream(
        id: 0,
        baseURL: 'https://upos.example/$name.m4s',
        backupURLs: const [],
        bandwidth: 0,
        mimeType: '',
        codecs: '',
        codecid: 0,
        width: 0,
        height: 0,
        frameRate: null,
        initialization: ByteRange(0, 9),
        indexRange: ByteRange(10, 19),
      );
      List<int> lengths(int max) => [
        for (final range in backgroundRanges(
          id: '1',
          gaps: DownloadGaps(
            id: '1',
            video: [ByteRange(0, 256 * mib - 1)],
            audio: const [],
            videoTotal: 256 * mib,
            audioTotal: mib,
          ),
          choice: TrackChoice(video: stream('v'), audio: stream('a')),
          videoPath: 'v.m4s',
          audioPath: 'a.m4s',
          maxPieceBytes: max,
        ))
          (range.end - range.start + 1) ~/ mib,
      ];

      expect(lengths(32 * mib), [16, 16, 32, 32, 32, 32, 32, 32, 32]);
      expect(lengths(64 * mib), [16, 16, 32, 64, 64, 64]);
      expect(lengths(backgroundRangeMaxBytes), [16, 16, 32, 64, 128]);
    });
  });
}
