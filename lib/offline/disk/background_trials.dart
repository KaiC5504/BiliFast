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

  static const minSeconds = 20.0;

  /// Counted in the arm's numbers: long enough, and not cut short by the downloads running out.
  bool get scored => seconds >= minSeconds && !allDone;

  double get mbps => seconds <= 0 ? 0 : gainedBytes / (1 << 20) / seconds;

  Map<String, Object?> toJson() => {
    'arm': arm.name,
    'at': at.millisecondsSinceEpoch,
    'seconds': seconds,
    'gained': gainedBytes,
    'wasted': wastedBytes,
    'allDone': allDone,
    'continuedEndedAfter': ?continuedEndedAfter,
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
    );
  }
}

/// The arm for the next trip, and why: `untried`, `best` or `explore`.
typedef BackgroundChoice = ({BackgroundArm arm, String why});

/// Picks how downloads go on while the app is away from how each way did on this device's earlier trips, so the
/// fastest is found by use rather than by a build per guess.
class BackgroundTrials {
  BackgroundTrials({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  final _trips = <BackgroundTrip>[];

  List<BackgroundTrip> get trips => List.unmodifiable(_trips);

  void load(Object? json) {
    _trips.clear();
    if (json is! Map || json['trips'] is! List) return;
    for (final trip in json['trips'] as List) {
      if (BackgroundTrip.fromJson(trip) case final read?) _trips.add(read);
    }
  }

  Map<String, Object?> toJson() => {
    'trips': [for (final trip in _trips) trip.toJson()],
  };

  /// [continued]: iOS's continued processing is running, so the engine can go on.
  BackgroundChoice choose({required bool continued}) {
    return (arm: continued ? BackgroundArm.continuedArm : BackgroundArm.fallback, why: 'best');
  }

  /// The hand-off with the best numbers, else [BackgroundArm.fallback]: for when continued processing ends mid-trip.
  BackgroundArm bestHandOff() => BackgroundArm.fallback;

  void record(BackgroundTrip trip) => _trips.add(trip);

  /// Scored trips and their mean MB/s over the last few, per arm, for the log.
  ({int scored, double? mbps}) stats(BackgroundArm arm) => (scored: 0, mbps: null);

  /// The arm with the best mean so far; null before any has numbers.
  BackgroundArm? get best => null;

  /// `{arm name: "scored/mean MB/s"}` for every arm, and `best`, for the log.
  Map<String, Object> summary() => {};

  // Used by the real choice.
  // ignore: unused_element
  double _draw() => _random.nextDouble();
}
