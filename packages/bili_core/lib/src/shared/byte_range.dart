/// An inclusive byte range, like HTTP Range and Bilibili's SegmentBase notation.
final class ByteRange {
  ByteRange(this.start, this.end) {
    if (start < 0 || end < start) throw ArgumentError('invalid range $start-$end');
  }

  final int start;
  final int end;

  /// The checked constructor: null where Swift's failable init returns nil.
  static ByteRange? of(int start, int end) => start >= 0 && end >= start ? ByteRange(start, end) : null;

  int get length => end - start + 1;
  String get headerValue => 'bytes=$start-$end';

  bool contains(ByteRange other) => other.start >= start && other.end <= end;

  /// Bilibili's "a-b" notation from SegmentBase.
  static ByteRange? parse(String text) {
    final parts = text.trim().split('-');
    if (parts.length != 2) return null;
    final start = int.tryParse(parts[0]);
    final end = int.tryParse(parts[1]);
    if (start == null || end == null) return null;
    return of(start, end);
  }

  /// BTR range-core `splitRange`: at most `concurrency` pieces, none smaller than `minChunk`
  /// (and never below 32 KiB), sizes differing by at most one byte.
  List<ByteRange> split({required int concurrency, required int minChunk}) {
    final limit = concurrency.clamp(1, 512);
    final minimum = minChunk < 32 * 1024 ? 32 * 1024 : minChunk;
    final count = ((length + minimum - 1) ~/ minimum).clamp(1, limit);
    final base = length ~/ count;
    final remainder = length % count;
    final pieces = <ByteRange>[];
    var cursor = start;
    for (var index = 0; index < count; index++) {
      final size = base + (index < remainder ? 1 : 0);
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

final class ContentRange {
  const ContentRange(this.range, this.total);

  final ByteRange range;
  final int? total;

  /// "bytes a-b/total" or "bytes a-b/*".
  static ContentRange? parse(String? text) {
    final value = text?.trim().toLowerCase();
    if (value == null || !value.startsWith('bytes ')) return null;
    final halves = value.substring(6).split('/');
    if (halves.length != 2) return null;
    final range = ByteRange.parse(halves[0]);
    if (range == null) return null;
    if (halves[1] == '*') return ContentRange(range, null);
    final total = int.tryParse(halves[1]);
    if (total == null || total <= range.end) return null;
    return ContentRange(range, total);
  }

  @override
  bool operator ==(Object other) => other is ContentRange && other.range == range && other.total == total;

  @override
  int get hashCode => Object.hash(range, total);
}
