import 'dart:io';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/ban_list.dart';
import 'package:bili_core/src/engine/attempt.dart';
import 'package:bili_core/src/engine/connection_pool.dart';
import 'package:bili_core/src/engine/range_downloader.dart';
import 'package:bili_core/src/engine/resolver.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

const _akamai = 'upos-hz-mirrorakam.akamaized.net';

/// The phone's nodes as 1.0.0 (1) measured them over 3,300 pieces: Akamai answers in tens of milliseconds over its
/// 8 HTTP/1.1 connections but misses its cache on a fifth of requests; aliov answers in ~220 ms; cosov sends nothing
/// for over a second and then the whole piece at once; the HK nodes answer in ~350 ms and then trickle.
SimCDN _phone(int size) => SimCDN(
  size: size,
  connectionsPerHost: 8,
  behaviors: {
    _akamai: const NodeBehavior(firstByteMs: 20, bytesPerSecond: 16e6, missEvery: 5, missFirstByteMs: 450),
    TestEngine.aliov: const NodeBehavior(firstByteMs: 220, bytesPerSecond: 2.9e6),
    TestEngine.cosov: const NodeBehavior(firstByteMs: 1200, bytesPerSecond: 20e6),
    TestEngine.hk1: const NodeBehavior(firstByteMs: 360, bytesPerSecond: 0.15e6),
    TestEngine.hk3: const NodeBehavior(firstByteMs: 320, bytesPerSecond: 0.25e6),
  },
);

/// What the app runs (`appRipperConfig`) as far as one range goes.
const _app = RipperConfig(fixedConcurrency: 24, seekBurst: true, exploreInHurry: false, tailBackups: true);

final class _Run {
  _Run(this.cdn, this.seekMs, {required this.startSlowRequests});

  final SimCDN cdn;
  final List<double> seekMs;
  final int startSlowRequests;

  int get seekSlowRequests => _slow(cdn) - startSlowRequests;

  double get totalMs => seekMs.fold(0, (sum, ms) => sum + ms);

  @override
  String toString() =>
      'seeks ${seekMs.map((ms) => ms.round()).toList()} ms, $seekSlowRequests slow-node requests in the seeks, '
      '${_slow(cdn)} of ${cdn.requestCount} in all';
}

int _slow(SimCDN cdn) =>
    cdn.requestsTo(TestEngine.cosov) + cdn.requestsTo(TestEngine.hk1) + cdn.requestsTo(TestEngine.hk3);

Future<_Run> _seeks(RipperConfig config) async {
  const segment = 2 * 1024 * 1024;
  const seeks = 4;
  final cdn = _phone(segment * (seeks + 2));
  final ctx = EngineContext(
    transport: cdn,
    pool: ConnectionPool(config.concurrency),
    config: config,
    logger: Logger(session: 'test'),
  );
  ctx.nodes
    ..exploreInHurry = config.exploreInHurry
    ..tailBackups = config.tailBackups
    ..keepsOffSlow = config.hurryKeepsOffSlow
    ..median = config.medianEstimates;
  final resolver = Resolver(
    primary: TestEngine.on(TestEngine.cosov),
    backups: const ['https://$_akamai/upgcxcode/1/2/3/v.m4s?deadline=9&os=akam'],
    mode: NodeMode.overseas,
    bans: BanList(),
  );
  final downloader = RangeDownloader(ctx);
  final seekMs = <double>[];
  var startSlow = 0;
  // The start measures the nodes; each seek then reads a segment elsewhere in the file.
  for (var index = 0; index <= seeks; index++) {
    final range = ByteRange(index * segment + 4096, (index + 1) * segment + 4095);
    final bytes = BytesBuilder(copy: false);
    final watch = Stopwatch()..start();
    await downloader.stream(
      range,
      resolver,
      startup: true,
      priority: 50,
      hurry: () => true,
      burst: true,
      emit: bytes.add,
    );
    expect(bytes.length, range.length);
    if (index > 0) seekMs.add(watch.elapsedMicroseconds / 1000);
    if (index == 0) startSlow = _slow(cdn);
  }
  return _Run(cdn, seekMs, startSlowRequests: startSlow);
}

/// Real timers, 7 s, and the races shift on a loaded machine (the gate runs lanes in parallel): run it by hand with
/// `SIM=1 fvm dart test test/engine/phone_profile_test.dart` when changing placement.
final _simSkip = Platform.environment['SIM'] == '1' ? false : 'real-time simulation; SIM=1 to run';

void main() {
  test('on the phone profile, keepsOffSlow and median estimates keep seeks off the slow nodes', () async {
    final before = await _seeks(_app);
    final after = await _seeks(_app.copyWith(hurryKeepsOffSlow: true, medianEstimates: true));
    printOnFailure('before: $before\nafter: $after');
    // The start races every node to measure them; the seeks after it are what changed.
    // A slow node may still take a third copy when both faster copies of a piece are late, at most about one a seek.
    expect(after.seekSlowRequests, lessThanOrEqualTo(before.seekSlowRequests));
    expect(after.seekSlowRequests, lessThanOrEqualTo(after.seekMs.length));
    expect(after.totalMs, lessThan(before.totalMs * 1.1));
  }, timeout: const Timeout(Duration(seconds: 60)), skip: _simSkip);
}
