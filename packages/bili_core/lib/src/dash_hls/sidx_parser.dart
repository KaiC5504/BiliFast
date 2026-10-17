import 'dart:typed_data';

import '../shared/byte_range.dart';
import '../shared/media_segment.dart';
import 'box_reader.dart';

abstract final class SidxParser {
  /// Segments from the first `sidx` box in `bytes`, which begins at file offset `absoluteStart`.
  static List<MediaSegment>? parse(Uint8List bytes, {required int absoluteStart}) {
    final box = BoxReader.boxes(bytes, from: 0, to: bytes.length).where((box) => box.type == 'sidx').firstOrNull;
    if (box == null) return null;
    var cursor = box.payloadStart;
    if (cursor + 12 > box.end) return null;
    final version = bytes[cursor];
    cursor += 8;
    final timescale = BoxReader.uint32(bytes, cursor).toDouble();
    cursor += 4;
    if (timescale <= 0) return null;

    final int earliest;
    final int firstOffset;
    if (version == 0) {
      if (cursor + 8 > box.end) return null;
      earliest = BoxReader.uint32(bytes, cursor);
      firstOffset = BoxReader.uint32(bytes, cursor + 4);
      cursor += 8;
    } else if (version == 1) {
      if (cursor + 16 > box.end) return null;
      earliest = BoxReader.uint64(bytes, cursor);
      firstOffset = BoxReader.uint64(bytes, cursor + 8);
      cursor += 16;
    } else {
      return null;
    }
    cursor += 2;
    if (cursor + 2 > box.end) return null;
    final count = BoxReader.uint16(bytes, cursor);
    cursor += 2;
    if (count < 1 || cursor + count * 12 > box.end) return null;

    // Version 1 offsets are 64-bit; anything beyond Int64 (read back negative) is hostile, and so is a sum
    // that overflows.
    if (firstOffset < 0) return null;
    final afterBox = _add(absoluteStart, box.end);
    final firstByte = afterBox == null ? null : _add(afterBox, firstOffset);
    if (firstByte == null) return null;
    var byteCursor = firstByte;
    var time = _unsignedToDouble(earliest);
    final segments = <MediaSegment>[];
    for (var i = 0; i < count; i++) {
      final reference = BoxReader.uint32(bytes, cursor);
      final size = reference & 0x7fffffff;
      final duration = BoxReader.uint32(bytes, cursor + 4).toDouble();
      cursor += 12;
      final next = _add(byteCursor, size);
      if (size <= 0 || next == null) return null;
      final range = ByteRange.of(byteCursor, next - 1);
      if (range == null) return null;
      // Type 1 points at another sidx; dropping it would leave byte and time gaps, so the caller falls back
      // to direct mode.
      if (reference >> 31 != 0) return null;
      segments.add(
        MediaSegment(index: segments.length, range: range, startTime: time / timescale, duration: duration / timescale),
      );
      byteCursor = next;
      time += duration;
    }
    return segments.isEmpty ? null : segments;
  }

  /// Null where Swift's `addingReportingOverflow` reports an overflow; Dart's ints wrap silently.
  static int? _add(int a, int b) {
    final sum = a + b;
    return ((a ^ sum) & (b ^ sum)) < 0 ? null : sum;
  }

  /// Swift's `Double(UInt64)`: the raw 64 bits read as unsigned, rounded once to the nearest double.
  static double _unsignedToDouble(int bits) {
    if (bits >= 0) return bits.toDouble();
    // The value is in [2^63, 2^64), where doubles are 2^11 apart.
    var high = bits >>> 11;
    final low = bits & 0x7ff;
    if (low > 0x400 || (low == 0x400 && high.isOdd)) high += 1;
    return high.toDouble() * 2048;
  }
}
