/// An inclusive byte range, like HTTP Range and Bilibili's SegmentBase notation.
class ByteRange {
  const ByteRange(this.start, this.end) : assert(start >= 0 && end >= start);

  final int start;
  final int end;

  int get length => end - start + 1;
  String get header => 'bytes=$start-$end';

  static ByteRange? parse(String text) {
    final parts = text.trim().split('-');
    if (parts.length != 2) return null;
    final s = int.tryParse(parts[0]);
    final e = int.tryParse(parts[1]);
    if (s == null || e == null || s < 0 || e < s) return null;
    return ByteRange(s, e);
  }

  /// BTR range-core `splitRange`: at most `concurrency` pieces, none smaller than `minChunk`
  /// (and never below 32 KiB), sizes differing by at most one byte.
  List<ByteRange> split(int concurrency, int minChunk) {
    final limit = concurrency.clamp(1, 512);
    final minimum = minChunk < 32 * 1024 ? 32 * 1024 : minChunk;
    final count = ((length + minimum - 1) ~/ minimum).clamp(1, limit);
    final base = length ~/ count;
    final remainder = length % count;
    final pieces = <ByteRange>[];
    var cursor = start;
    for (var i = 0; i < count; i++) {
      final size = base + (i < remainder ? 1 : 0);
      pieces.add(ByteRange(cursor, cursor + size - 1));
      cursor += size;
    }
    return pieces;
  }

  @override
  bool operator ==(Object other) => other is ByteRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start-$end';
}

/// "bytes a-b/total" or "bytes a-b/*".
(ByteRange, int?)? parseContentRange(String? text) {
  if (text == null) return null;
  final t = text.trim().toLowerCase();
  if (!t.startsWith('bytes ')) return null;
  final halves = t.substring(6).split('/');
  if (halves.length != 2) return null;
  final range = ByteRange.parse(halves[0]);
  if (range == null) return null;
  if (halves[1] == '*') return (range, null);
  final total = int.tryParse(halves[1]);
  if (total == null || total <= range.end) return null;
  return (range, total);
}
