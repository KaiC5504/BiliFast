import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/ban_list.dart';
import 'package:bili_core/src/engine/resolver.dart';
import 'package:test/test.dart';

String _url(String node, String file) => 'https://$node.bilivideo.com/upgcxcode/$file.m4s?deadline=1';

void main() {
  late ManualClock manual;
  late BanList bans;

  void ban(String url) {
    bans
      ..record(url, receivedBytes: 0)
      ..record(url, receivedBytes: 0);
  }

  setUp(() {
    manual = ManualClock(100000);
    bans = BanList()..probation = BanProbation(clock: manual.clock);
  });

  test('without probation a banned node gets no turn', () {
    final plain = BanList()
      ..record(_url('a', 'f1'), receivedBytes: 0)
      ..record(_url('a', 'f1'), receivedBytes: 0);
    manual.advance(3600000);
    expect(plain.probationDue(_url('a', 'f1')), isFalse);
  });

  // Build 100 banned Akamai about 96 s into a video and stalled 7 times after.
  test("a banned node's turns come 15 s after the ban, then twice as far apart up to two minutes", () {
    final a = _url('a', 'f1');
    expect(bans.probationDue(a), isFalse, reason: 'not banned');
    ban(a);
    final turns = <double>[];
    for (var at = 0.0; at <= 600000; at += 100) {
      if (bans.probationDue(a)) {
        turns.add(at);
        bans.takeProbation(a);
      }
      manual.advance(100);
    }
    expect(turns, [15000, 45000, 105000, 225000, 345000, 465000, 585000]);
  });

  test('a success on probation lifts the ban; a new ban starts over', () {
    final a = _url('a', 'f1');
    ban(a);
    manual.advance(15000);
    expect(bans.probationDue(a), isTrue);
    bans
      ..takeProbation(a)
      ..success(a);
    expect(bans.allowsNode(a), isTrue);
    expect(bans.probationDue(a), isFalse);
    manual.advance(1000);
    ban(a);
    manual.advance(14900);
    expect(bans.probationDue(a), isFalse);
    manual.advance(100);
    expect(bans.probationDue(a), isTrue);
  });

  test('a refused address or pair gets no turn: it would only be refused again', () {
    final good = _url('a', 'f1');
    final refused = _url('a', 'f2');
    bans
      ..success(good)
      ..record(refused, receivedBytes: 0, status: 403)
      ..record(refused, receivedBytes: 0, status: 403);
    manual.advance(60000);
    expect(bans.allows(refused), isFalse);
    expect(bans.probationDue(refused), isFalse);

    final pair = _url('b', 'f1');
    bans
      ..record(pair, receivedBytes: 0, status: 403)
      ..record(pair, receivedBytes: 0, status: 403);
    expect(bans.allows(pair), isFalse);
    expect(bans.probationDue(pair), isFalse);
  });

  test('a network change forgets the turns with the bans', () {
    final a = _url('a', 'f1');
    ban(a);
    manual.advance(15000);
    bans.reset();
    expect(bans.probationDue(a), isFalse);
    ban(a);
    expect(bans.probationDue(a), isFalse, reason: 'a fresh ban waits again');
  });

  test('switched on after a ban, the wait starts then', () {
    final switched = BanList();
    final a = _url('a', 'f1');
    switched
      ..record(a, receivedBytes: 0)
      ..record(a, receivedBytes: 0)
      ..probation = BanProbation(clock: manual.clock);
    expect(switched.probationDue(a), isFalse);
    manual.advance(15000);
    expect(switched.probationDue(a), isTrue);
  });

  group('Resolver', () {
    const primary = 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv';
    late Resolver resolver;

    setUp(() {
      resolver = Resolver(
        primary: primary,
        backups: const [],
        mode: NodeMode.overseas,
        bans: bans,
        clock: manual.clock,
      );
    });

    void strike(String url) {
      resolver.failure(url, status: null, receivedBytes: 0);
      manual.advance(1000);
      resolver.failure(url, status: null, receivedBytes: 0);
    }

    test('a banned node gets one backup copy per turn, never in a hurry', () {
      final a = resolver.urls()[0];
      strike(a);
      expect(resolver.urls(), isNot(contains(a)));
      final piece = ByteRange(0, 65535);
      manual.advance(14900);
      expect(resolver.probationCopy(piece), isNull, reason: 'its turn has not come');
      manual.advance(100);
      expect(resolver.probationCopy(piece, hurried: true), isNull);
      expect(resolver.probationCopy(piece), a);
      expect(resolver.probationCopy(piece), isNull, reason: 'the turn is taken');
      resolver.success(a, bps: 1e6);
      expect(resolver.urls(), contains(a), reason: 'the success lifted the ban');
      expect(resolver.probationCopy(piece), isNull);
    });

    test('no probation copy over a span the node has damaged', () {
      final a = resolver.urls()[0];
      resolver
        ..success(a, bps: 0)
        ..failure(a, status: null, receivedBytes: 10, range: ByteRange(100000, 199999));
      strike(a);
      manual.advance(15000);
      expect(resolver.probationCopy(ByteRange(100000, 165535)), isNull);
      expect(resolver.probationCopy(ByteRange(2 << 20, (2 << 20) + 65535)), a);
    });

    test('without probation there is never a copy', () {
      final plain = Resolver(
        primary: primary,
        backups: const [],
        mode: NodeMode.overseas,
        bans: BanList(),
        clock: manual.clock,
      );
      final a = plain.urls()[0];
      plain
        ..failure(a, status: null, receivedBytes: 0)
        ..failure(a, status: null, receivedBytes: 0);
      manual.advance(3600000);
      expect(plain.probationCopy(ByteRange(0, 65535)), isNull);
    });
  });
}
