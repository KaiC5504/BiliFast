import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/ban_list.dart';
import 'package:bili_core/src/engine/resolver.dart';
import 'package:test/test.dart';

const _primary = 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv';

void main() {
  late ManualClock manual;
  late Resolver resolver;

  setUp(() {
    manual = ManualClock(100000);
    resolver = Resolver(
      primary: _primary,
      backups: const [],
      mode: NodeMode.overseas,
      bans: BanList(),
      clock: manual.clock,
    );
  });

  String node(int index) => resolver.urls()[index];

  String? stateOf(String url) =>
      resolver.status().where((status) => status.node == NodeCatalog.nodeKey(url)).firstOrNull?.state;

  test('ordered rotates', () {
    final first = resolver.ordered();
    final second = resolver.ordered();
    expect(first, hasLength(4));
    expect(second, [...first.sublist(1), ...first.sublist(0, 1)]);
  });

  test('a failure backs off', () {
    final a = node(0);
    resolver.failure(a, status: 503, receivedBytes: 0);
    expect(resolver.ordered(), isNot(contains(a)));
    manual.advance(6001);
    expect(resolver.ordered(), contains(a));
  });

  test('speed is averaged and expires', () {
    final a = node(0);
    resolver.success(a, bps: 1000000);
    expect(resolver.speed(a), 1000000);
    resolver.success(a, bps: 2000000);
    expect(resolver.speed(a), closeTo(1350000, 0.1));
    manual.advance(90001);
    expect(resolver.speed(a), 0);
  });

  test('sample measures without proving the address', () {
    final a = node(1);
    resolver.sample(a, bps: 500000);
    expect(resolver.speed(a), 500000);
    expect(stateOf(a), 'untested');
  });

  test('a new signature keeps the route speed', () {
    final a = node(0);
    resolver
      ..success(a, bps: 3000000)
      ..replaceURLs(primary: _primary.replaceAll('deadline=9', 'deadline=99'), backups: const []);
    final renewed = node(0);
    expect(renewed, isNot(a));
    expect(resolver.speed(renewed), 3000000);
  });

  test('range candidates warm up, then prefer measured nodes', () {
    expect(resolver.rangeCandidates(), hasLength(4));
    final fast = node(2);
    resolver.success(fast, bps: 9000000);
    for (var range = 0; range < 3; range++) {
      resolver.rangeCandidates();
    }
    final after = resolver.rangeCandidates();
    expect(after.first, fast);
    expect(after.length, greaterThanOrEqualTo(3));
  });

  test('status shows pair bans', () {
    final a = node(0);
    resolver
      ..success(a, bps: 0)
      ..failure(a, status: 403, receivedBytes: 0)
      ..failure(a, status: 403, receivedBytes: 0);
    expect(resolver.bans?.allowsNode(a) ?? false, isTrue);
    manual.advance(60001);
    expect(stateOf(a), 'banned');
  });

  // Akamai, 2026-10-16: its copy of one file lacked 109972 through the end of the first MiB. A request crossing
  // 109972 was cut there; one starting in the gap got no response at all; everything else was served.
  test('a cut copy is avoided over its block without strikes or backoff', () {
    final a = node(0);
    final b = node(1);
    resolver
      ..success(a, bps: 0)
      ..failure(a, status: null, receivedBytes: 9972, range: ByteRange(100000, 199999))
      ..failure(a, status: null, receivedBytes: 0, range: ByteRange(300000, 399999))
      ..failure(a, status: null, receivedBytes: 0, range: ByteRange(400000, 499999));
    expect(resolver.avoids(a, ByteRange(100000, 199999)), isTrue);
    expect(resolver.avoids(a, ByteRange(109972, 109972)), isTrue);
    expect(resolver.avoids(a, ByteRange(1000000, 1100000)), isTrue, reason: 'the rest of the block');
    expect(resolver.avoids(a, ByteRange(0, 109971)), isFalse);
    expect(resolver.avoids(a, ByteRange(1048576, 2000000)), isFalse);
    expect(resolver.avoids(b, ByteRange(100000, 199999)), isFalse);
    expect(resolver.allows(a), isTrue);
    expect(resolver.ordered(), contains(a), reason: 'no backoff');
    expect(stateOf(a), 'healthy');
  });

  test('damage is per file', () {
    final a = node(0);
    resolver
      ..success(a, bps: 0)
      ..failure(a, status: null, receivedBytes: 10, range: ByteRange(100000, 199999));
    final other = Resolver(
      primary: _primary.replaceAll('v.m4s', 'a.m4s'),
      backups: const [],
      mode: NodeMode.overseas,
      bans: resolver.bans,
      clock: manual.clock,
    );
    expect(other.avoids(other.urls()[0], ByteRange(100000, 199999)), isFalse);
  });

  test('damage in a third block is struck as before', () {
    final a = node(0);
    resolver.success(a, bps: 0);
    for (var block = 0; block < 2; block++) {
      resolver
        ..failure(a, status: null, receivedBytes: 0, range: ByteRange((block << 20) + 5000, (block << 20) + 9999))
        ..failure(a, status: null, receivedBytes: 0, range: ByteRange((block << 20) + 6000, (block << 20) + 9999));
    }
    expect(resolver.allows(a), isTrue);
    resolver.failure(a, status: null, receivedBytes: 0, range: ByteRange(2 << 20, (2 << 20) + 9999));
    manual.advance(1000);
    resolver.failure(a, status: null, receivedBytes: 0, range: ByteRange(3 << 20, (3 << 20) + 9999));
    expect(resolver.allows(a), isFalse);
  });

  test('damage past the limit is not recorded', () {
    final a = node(0);
    resolver.success(a, bps: 0);
    for (var block = 0; block < 3; block++) {
      resolver.failure(a, status: null, receivedBytes: 0, range: ByteRange((block << 20) + 1000, (block << 20) + 9999));
    }
    expect(resolver.avoids(a, ByteRange((1 << 20) + 1000, (1 << 20) + 9999)), isTrue);
    expect(resolver.avoids(a, ByteRange((2 << 20) + 1000, (2 << 20) + 9999)), isFalse);
    expect(resolver.ordered(), isNot(contains(a)), reason: 'struck and backed off as before');
  });

  test('bytes from a cut copy show the node is up', () {
    final a = node(0);
    resolver
      ..failure(a, status: null, receivedBytes: 9972, range: ByteRange(100000, 199999))
      ..failure(a, status: null, receivedBytes: 0, range: ByteRange(300000, 399999))
      ..failure(a, status: null, receivedBytes: 0, range: ByteRange(400000, 499999));
    expect(resolver.allows(a), isTrue);
    expect(resolver.avoids(a, ByteRange(300000, 399999)), isTrue);
  });

  test('empty replies from a node that never delivered are struck as before', () {
    final a = node(0);
    resolver.failure(a, status: null, receivedBytes: 0, range: ByteRange(300000, 399999));
    manual.advance(1000);
    resolver.failure(a, status: null, receivedBytes: 0, range: ByteRange(400000, 499999));
    expect(resolver.allows(a), isFalse);
    expect(resolver.avoids(a, ByteRange(300000, 399999)), isFalse);
  });

  test('timeouts are not positional', () {
    final a = node(0);
    resolver
      ..success(a, bps: 0)
      ..failure(a, status: null, receivedBytes: 0, range: ByteRange(300000, 399999), timedOut: true);
    expect(resolver.avoids(a, ByteRange(300000, 399999)), isFalse);
    expect(resolver.ordered(), isNot(contains(a)));
  });

  test('status shows bans', () {
    final a = node(0);
    resolver.failure(a, status: null, receivedBytes: 0);
    manual.advance(1000);
    resolver.failure(a, status: null, receivedBytes: 0);
    expect(stateOf(a), 'banned');
    expect(resolver.urls(), isNot(contains(a)));
  });

  test('the best status prefers healthy, then faster addresses', () {
    const states = [
      NodeStatus(node: 'a', state: 'banned', bps: 9000000),
      NodeStatus(node: 'a', state: 'healthy', bps: 1000000),
      NodeStatus(node: 'a', state: 'healthy', bps: 2000000),
      NodeStatus(node: 'b', state: 'blocked', bps: 0),
      NodeStatus(node: 'b', state: 'untested', bps: 0),
    ];
    expect(NodeStatus.best('a', states), same(states[2]));
    expect(NodeStatus.best('b', states)?.state, 'untested');
    expect(NodeStatus.best('c', states), isNull);
  });
}
