import 'package:bili_core/src/engine/hurry_placement.dart';
import 'package:bili_core/src/engine/node_stats.dart';
import 'package:test/test.dart';

const _piece = 64 * 1024;

String _url(String host, [String query = 'os=cosovbv']) => 'https://$host/upgcxcode/1/2/3/v.m4s?$query';

/// One finished transfer: the node is known, with `load` 1, so its expected time holds up to four in flight.
void _measure(NodeStats stats, String url, {required double ttfbMs, required double bytesPerSecond}) {
  stats
    ..begin(url)
    ..firstByte(url, ms: ttfbMs)
    ..body(url, bytes: 1000000, ms: 1000000 / bytesPerSecond * 1000)
    ..end(url, receiving: true);
}

Map<String, int> _counts(List<String> primaries) {
  final counts = <String, int>{};
  for (final url in primaries) {
    counts[url] = (counts[url] ?? 0) + 1;
  }
  return counts;
}

bool _always(String _) => true;

void main() {
  test('no node known spreads by inflight', () {
    final urls = [_url('a.example'), _url('b.example'), _url('c.example')];
    final primaries = HurryPlacement.assign(
      urls: urls,
      count: 6,
      pieceBytes: _piece,
      nodes: NodeStats(),
      delivered: _always,
    );
    expect(primaries, [...urls, ...urls]);
  });

  test('later copies go by expected finish', () {
    final stats = NodeStats();
    final slowStart = _url('cosov.example');
    final quick = _url('akamai.example');
    final unknown = _url('new.example');
    final full = _url('full.example');
    _measure(stats, slowStart, ttfbMs: 660, bytesPerSecond: 8000000);
    _measure(stats, quick, ttfbMs: 20, bytesPerSecond: 4000000);
    _measure(stats, full, ttfbMs: 50, bytesPerSecond: 4000000);
    stats
      ..begin(full)
      ..firstByte(full, ms: 50)
      ..silent(full, waitedMs: 5500);
    // quick: about 36 ms; unknown: twice that; slowStart: about 668 ms; full last.
    expect(
      HurryPlacement.byExpectedFinish(
        [slowStart, full, unknown, quick],
        pieceBytes: _piece,
        nodes: stats,
        delivered: _always,
      ),
      [quick, unknown, slowStart, full],
    );
    final twin = _url('akamai.example', 'os=akam');
    expect(
      HurryPlacement.byExpectedFinish([quick, twin], pieceBytes: _piece, nodes: stats, delivered: (url) => url == twin),
      [twin, quick],
      reason: 'an address that has not delivered loses the tie',
    );
  });

  test('unknown nodes take a share at twice the best cost', () {
    final stats = NodeStats();
    final known = _url('known.example');
    _measure(stats, known, ttfbMs: 20, bytesPerSecond: 10000000);
    final urls = [known, _url('u1.example'), _url('u2.example')];
    final result = _counts(
      HurryPlacement.assign(urls: urls, count: 8, pieceBytes: _piece, nodes: stats, delivered: _always),
    );
    for (final url in urls) {
      expect(result[url] ?? 0, greaterThanOrEqualTo(1), reason: '$result');
    }
    expect(result[known] ?? 0, greaterThan(result[urls[1]] ?? 0));
    expect(result[known] ?? 0, greaterThan(result[urls[2]] ?? 0));
  });

  test('no node takes more than half with three hosts', () {
    final stats = NodeStats();
    final fast = _url('fast.example');
    final slowOne = _url('slow1.example');
    final slowTwo = _url('slow2.example');
    _measure(stats, fast, ttfbMs: 10, bytesPerSecond: 100000000);
    _measure(stats, slowOne, ttfbMs: 10, bytesPerSecond: 1000000);
    _measure(stats, slowTwo, ttfbMs: 10, bytesPerSecond: 1000000);
    // Fast costs about 11 ms however full it gets, a slow node 75.5 ms up to four in flight. Virtual
    // counts (fast, slow1, slow2), carried = their sum; fast pays 1e5 when it has ≥ 2 and more than half:
    //  1: (0,0,0) fast           2: (1,0,0) fast
    //  3: (2,0,0) 4 > 2, slows tie with none in flight → slow1
    //  4: (2,1,0) 4 > 3, slows tie at 75.5 → slow2, carrying less
    //  5: (2,1,1) 4 = 4 → fast   6: (3,1,1) 6 > 5 → slow1
    //  7: (3,2,1) 6 = 6 → fast   8: (4,2,1) 8 > 7 → slow2, carrying less
    //  9: (4,2,2) 8 = 8 → fast  10: (5,2,2) 10 > 9 → slow1
    final primaries = HurryPlacement.assign(
      urls: [fast, slowOne, slowTwo],
      count: 10,
      pieceBytes: _piece,
      nodes: stats,
      delivered: _always,
    );
    expect(primaries, [fast, fast, slowOne, slowTwo, fast, slowOne, fast, slowTwo, fast, slowOne]);
    expect(_counts(primaries), {fast: 5, slowOne: 3, slowTwo: 2});
  });

  // Review focus 1: an Akamai-only account has one host; the half-share rule must not push pieces nowhere.
  test('a single host takes every piece', () {
    final stats = NodeStats();
    final akamai = _url('upos-hz-mirrorakam.akamaized.net', 'os=akam');
    _measure(stats, akamai, ttfbMs: 30, bytesPerSecond: 20000000);
    final primaries = HurryPlacement.assign(
      urls: [akamai],
      count: 5,
      pieceBytes: _piece,
      nodes: stats,
      delivered: _always,
    );
    expect(primaries, List.filled(5, akamai));
  });

  test('full nodes and undelivered addresses go last', () {
    final stats = NodeStats();
    final full = _url('full.example');
    final open = _url('open.example');
    _measure(stats, full, ttfbMs: 5, bytesPerSecond: 100000000);
    _measure(stats, open, ttfbMs: 50, bytesPerSecond: 1000000);
    // Silent while receiving: capped at the one transfer it carries.
    stats
      ..begin(full)
      ..firstByte(full, ms: 5)
      ..silent(full, waitedMs: 5500);
    expect(stats.isFull(full), isTrue);
    final primaries = HurryPlacement.assign(
      urls: [full, open],
      count: 6,
      pieceBytes: _piece,
      nodes: stats,
      delivered: _always,
    );
    expect(primaries, List.filled(6, open));

    // Capped at two but idle: the pieces placed on it count toward the cap.
    final capped = _url('capped.example');
    _measure(stats, capped, ttfbMs: 5, bytesPerSecond: 100000000);
    stats
      ..begin(capped)
      ..begin(capped)
      ..firstByte(capped, ms: 5)
      ..firstByte(capped, ms: 5)
      ..silent(capped, waitedMs: 5500)
      ..end(capped, receiving: true)
      ..end(capped, receiving: true);
    expect(stats.isFull(capped), isFalse);
    final spilled = HurryPlacement.assign(
      urls: [capped, open],
      count: 5,
      pieceBytes: _piece,
      nodes: stats,
      delivered: _always,
    );
    expect(_counts(spilled), {capped: 2, open: 3});

    // Two addresses of one node cost the same; the one that has delivered goes first.
    final refused = _url('akam.example', 'os=cosovbv');
    final served = _url('akam.example', 'os=akam');
    final first = HurryPlacement.assign(
      urls: [refused, served],
      count: 3,
      pieceBytes: _piece,
      nodes: NodeStats(),
      delivered: (url) => url == served,
    );
    expect(first, [served, served, served]);
  });
}
