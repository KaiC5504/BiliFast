import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../shared/byte_range.dart';

/// What a `.ranges` or `.bg-ranges` file says (`DownloadRanges`): the part's total, 0 while unknown, and the bytes it
/// holds, sorted and merged.
final class RangesRecord {
  const RangesRecord(this.total, this.done);

  final int total;
  final List<ByteRange> done;

  /// Null when the file is missing or isn't a ranges file: its part's bytes are then taken as unknown.
  static Future<RangesRecord?> read(String path) async {
    final String text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
    return parse(text);
  }

  static RangesRecord? parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final total = _integer(json['total']);
    final done = json['done'];
    if (total == null || total < 0 || done is! List<Object?>) return null;
    final ranges = <ByteRange>[];
    for (final item in done) {
      if (item is! List<Object?> || item.length != 2) return null;
      final start = _integer(item[0]);
      final end = _integer(item[1]);
      final range = start == null || end == null ? null : ByteRange.of(start, end);
      if (range == null || (total > 0 && range.end >= total)) return null;
      ranges.add(range);
    }
    return RangesRecord(total, mergeRanges(ranges));
  }

  // The host writes from Swift, where a number may come out as 1.048576e6.
  static int? _integer(Object? value) => switch (value) {
    final int whole => whole,
    final double number when number.isFinite && number == number.roundToDouble() => number.toInt(),
    _ => null,
  };

  /// Through a temporary file and a rename, so a crash leaves the old record or the new one, never half of one.
  Future<void> write(String path) async {
    final temporary = File('$path.tmp');
    await temporary.writeAsString(jsonEncode(toJson()), flush: true);
    await temporary.rename(path);
  }

  Map<String, Object> toJson() => {
    'total': total,
    'done': [
      for (final range in done) [range.start, range.end],
    ],
  };
}

/// [ranges] sorted, with overlapping and touching ones joined.
List<ByteRange> mergeRanges(Iterable<ByteRange> ranges) {
  final sorted = ranges.toList()..sort((a, b) => a.start.compareTo(b.start));
  final merged = <ByteRange>[];
  for (final range in sorted) {
    final last = merged.lastOrNull;
    if (last != null && range.start <= last.end + 1) {
      if (range.end > last.end) merged[merged.length - 1] = ByteRange(last.start, range.end);
    } else {
      merged.add(range);
    }
  }
  return merged;
}

/// [ranges] cut to a file of [total] bytes.
List<ByteRange> clipRanges(List<ByteRange> ranges, int total) => [
  for (final range in ranges)
    if (range.start < total) ByteRange(range.start, min(range.end, total - 1)),
];

int coveredBytes(List<ByteRange> ranges) => ranges.fold(0, (sum, range) => sum + range.length);
