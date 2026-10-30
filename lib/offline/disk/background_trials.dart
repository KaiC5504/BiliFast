import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../offline_host.dart';
import 'background_plan.dart';

/// How downloads go on while the app is away: the engine itself under iOS's continued processing, or a hand-off to
/// the background session with [connections] per host and pieces up to [maxPieceBytes].
@immutable
final class BackgroundArm {
  const BackgroundArm.continued() : connections = 0, maxPieceBytes = 0;
  const BackgroundArm.handOff({required this.connections, required this.maxPieceBytes});

  final int connections;
  final int maxPieceBytes;

  bool get continued => connections == 0;

  /// `continued` or `handoff-<connections>x<MiB>`, as kept and logged.
  String get name => continued ? 'continued' : 'handoff-${connections}x${maxPieceBytes >> 20}';

  static BackgroundArm? parse(String name) {
    if (name == 'continued') return continuedArm;
    final match = RegExp(r'^handoff-(\d+)x(\d+)$').firstMatch(name);
    if (match == null) return null;
    return BackgroundArm.handOff(
      connections: int.parse(match.group(1)!),
      maxPieceBytes: int.parse(match.group(2)!) << 20,
    );
  }

  static const continuedArm = BackgroundArm.continued();

  /// The hand-offs tried; the first is 1.3.0 (4)'s, and the one used until the others have numbers.
  static const handOffArms = [
    BackgroundArm.handOff(connections: OfflineHost.defaultConnections, maxPieceBytes: backgroundRangeMaxBytes),
    BackgroundArm.handOff(connections: 2, maxPieceBytes: 64 << 20),
    BackgroundArm.handOff(connections: 6, maxPieceBytes: 32 << 20),
  ];

  static const fallback = BackgroundArm.handOff(
    connections: OfflineHost.defaultConnections,
    maxPieceBytes: backgroundRangeMaxBytes,
  );

  @override
  bool operator ==(Object other) =>
      other is BackgroundArm && other.connections == connections && other.maxPieceBytes == maxPieceBytes;

  @override
  int get hashCode => Object.hash(connections, maxPieceBytes);

  @override
  String toString() => name;
}

/// One stay away from the app with downloads going: what the arm chosen for it got done.
@immutable
final class BackgroundTrip {
  const BackgroundTrip({
    required this.arm,
    required this.at,
    required this.seconds,
    required this.gainedBytes,
    required this.wastedBytes,
    required this.allDone,
    this.continuedEndedAfter,
    this.spoiled = false,
  });

  final BackgroundArm arm;

  /// When the app left.
  final DateTime at;

  /// Away, from the leave to the return.
  final double seconds;

  /// Bytes the downloads moved on by while away: the engine's and the ranges the background session finished.
  final int gainedBytes;

  /// Bytes the background session had fetched of ranges it didn't finish, thrown away on the return.
  final int wastedBytes;

  /// Nothing was left to download by the return, so the trip's rate says little.
  final bool allDone;

  /// Seconds into the trip at which iOS ended the continued processing; null when it didn't.
  final double? continuedEndedAfter;

  /// The app's side went wrong (nothing was handed off, the take-back failed, iOS ended the app while away), so the
  /// trip says nothing about its arm.
  final bool spoiled;

  static const minSeconds = 20.0;

  /// Counted in the arm's numbers: long enough, not cut short by the downloads running out, and not spoiled.
  bool get scored => seconds >= minSeconds && !allDone && !spoiled;

  double get mbps => seconds <= 0 ? 0 : gainedBytes / (1 << 20) / seconds;

  Map<String, Object?> toJson() => {
    'arm': arm.name,
    'at': at.millisecondsSinceEpoch,
    'seconds': seconds,
    'gained': gainedBytes,
    'wasted': wastedBytes,
    'allDone': allDone,
    'continuedEndedAfter': ?continuedEndedAfter,
    'spoiled': spoiled,
  };

  /// Null for anything unreadable.
  static BackgroundTrip? fromJson(Object? json) {
    if (json is! Map) return null;
    final arm = json['arm'] is String ? BackgroundArm.parse(json['arm'] as String) : null;
    final at = json['at'];
    final seconds = json['seconds'];
    final gained = json['gained'];
    final wasted = json['wasted'];
    if (arm == null || at is! int || seconds is! num || gained is! int || wasted is! int) return null;
    final ended = json['continuedEndedAfter'];
    return BackgroundTrip(
      arm: arm,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      seconds: seconds.toDouble(),
      gainedBytes: gained,
      wastedBytes: wasted,
      allDone: json['allDone'] == true,
      continuedEndedAfter: ended is num ? ended.toDouble() : null,
      spoiled: json['spoiled'] == true,
    );
  }
}

/// The arm for the next trip, and why: `untried`, `best`, `explore`, or `fallback` when every arm was tried and none
/// has numbers.
typedef BackgroundChoice = ({BackgroundArm arm, String why});

/// Picks how downloads go on while the app is away from how each way did on this device's earlier trips, so the
/// fastest is found by use rather than by a build per guess.
class BackgroundTrials {
  BackgroundTrials({math.Random? random}) : _random = random ?? math.Random();

  /// Trips kept, the newest; many windows' worth for every arm.
  static const keep = 200;

  /// An arm's mean is over its last few scored trips, so it follows a change of network or of iOS.
  static const window = 5;

  /// How often a choice tries an arm other than the best while some arm has fewer than [window] scored trips, so one
  /// unlucky trip doesn't bury an arm for good …
  static const exploreChance = 0.15;

  /// … and once every arm has a full window, so a change of network or of iOS still reaches the others.
  static const settledExploreChance = 0.05;

  /// Trips of at least [BackgroundTrip.minSeconds] after which an arm none of whose trips scored is no longer forced:
  /// one whose trips never score (the downloads always run out, or the app's side always fails) would be taken on
  /// every leave.
  static const maxAttempts = 3;

  /// Every arm, in the order ties go.
  static const arms = [BackgroundArm.continuedArm, ...BackgroundArm.handOffArms];

  final math.Random _random;
  final _trips = <BackgroundTrip>[];

  List<BackgroundTrip> get trips => List.unmodifiable(_trips);

  /// False when [json] isn't the file's shape; nothing is read then.
  bool load(Object? json) {
    _trips.clear();
    if (json is! Map || json['trips'] is! List) return false;
    for (final trip in json['trips'] as List) {
      if (BackgroundTrip.fromJson(trip) case final read?) _trips.add(read);
    }
    _trim();
    return true;
  }

  Map<String, Object?> toJson() => {
    'trips': [for (final trip in _trips) trip.toJson()],
  };

  /// [continued]: iOS's continued processing is running, so the engine can go on.
  BackgroundChoice choose({required bool continued}) {
    final candidates = continued ? arms : BackgroundArm.handOffArms;
    for (final arm in candidates) {
      if (_untried(arm)) return (arm: arm, why: 'untried');
    }
    final best = _bestOf(candidates);
    final settled = candidates.every((arm) => _scored(arm).length >= window);
    if (_random.nextDouble() < (settled ? settledExploreChance : exploreChance)) {
      final others = [
        for (final arm in candidates)
          if (arm != (best ?? candidates.first)) arm,
      ];
      return (arm: others[_random.nextInt(others.length)], why: 'explore');
    }
    return best == null ? (arm: candidates.first, why: 'fallback') : (arm: best, why: 'best');
  }

  /// The hand-off with the best numbers, else [BackgroundArm.fallback]: for when continued processing ends mid-trip.
  BackgroundArm bestHandOff() => _bestOf(BackgroundArm.handOffArms) ?? BackgroundArm.fallback;

  void record(BackgroundTrip trip) {
    _trips.add(trip);
    _trim();
  }

  /// Scored trips and their mean MB/s over the last few, per arm, for the log.
  ({int scored, double? mbps}) stats(BackgroundArm arm) {
    final scored = _scored(arm);
    if (scored.isEmpty) return (scored: 0, mbps: null);
    final recent = scored.sublist(math.max(0, scored.length - window));
    return (scored: scored.length, mbps: recent.fold(0.0, (sum, trip) => sum + trip.mbps) / recent.length);
  }

  /// The arm with the best mean so far; null before any has numbers.
  BackgroundArm? get best => _bestOf(arms);

  /// `{arm name: "scored/mean MB/s"}` for every arm, and `best`, for the log.
  Map<String, Object> summary() {
    String text(({int scored, double? mbps}) numbers) => '${numbers.scored}/${numbers.mbps?.toStringAsFixed(1) ?? '-'}';
    return {for (final arm in arms) arm.name: text(stats(arm)), 'best': best?.name ?? 'none'};
  }

  bool _untried(BackgroundArm arm) {
    var attempts = 0;
    for (final trip in _trips) {
      if (trip.arm != arm) continue;
      if (trip.scored) return false;
      if (trip.seconds >= BackgroundTrip.minSeconds) attempts += 1;
    }
    return attempts < maxAttempts;
  }

  List<BackgroundTrip> _scored(BackgroundArm arm) => [
    for (final trip in _trips)
      if (trip.arm == arm && trip.scored) trip,
  ];

  /// The highest mean of [candidates], the earlier on a tie; null when none has numbers.
  BackgroundArm? _bestOf(List<BackgroundArm> candidates) {
    BackgroundArm? best;
    double? top;
    for (final arm in candidates) {
      final mbps = stats(arm).mbps;
      if (mbps != null && (top == null || mbps > top)) {
        best = arm;
        top = mbps;
      }
    }
    return best;
  }

  /// Unscored trips go first, the oldest first, so a rarely chosen arm keeps its numbers longest.
  void _trim() {
    var excess = _trips.length - keep;
    if (excess <= 0) return;
    final kept = <BackgroundTrip>[];
    for (final trip in _trips) {
      if (excess > 0 && !trip.scored) {
        excess -= 1;
        continue;
      }
      kept.add(trip);
    }
    if (excess > 0) kept.removeRange(0, excess);
    _trips
      ..clear()
      ..addAll(kept);
  }
}
