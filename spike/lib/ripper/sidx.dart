import 'dart:typed_data';

import 'byte_range.dart';

class MediaSegment {
  MediaSegment(this.index, this.range, this.startTime, this.duration);
  final int index;
  final ByteRange range;
  final double startTime;
  final double duration;
}

/// Segments from the first `sidx` box in `bytes`, which begins at file offset 0.
List<MediaSegment>? parseSidx(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 0;
  while (offset + 8 <= bytes.length) {
    var size = data.getUint32(offset);
    var header = 8;
    if (size == 1) {
      if (offset + 16 > bytes.length) return null;
      size = data.getUint64(offset + 8);
      header = 16;
    } else if (size == 0) {
      size = bytes.length - offset;
    }
    if (size < header || size > bytes.length - offset) return null;
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (type == 'sidx') return _segments(data, offset + header, offset + size);
    offset += size;
  }
  return null;
}

List<MediaSegment>? _segments(ByteData d, int start, int end) {
  var c = start;
  if (c + 12 > end) return null;
  final version = d.getUint8(c);
  c += 8;
  final timescale = d.getUint32(c).toDouble();
  c += 4;
  if (timescale <= 0) return null;
  int earliest, firstOffset;
  if (version == 0) {
    earliest = d.getUint32(c);
    firstOffset = d.getUint32(c + 4);
    c += 8;
  } else {
    earliest = d.getUint64(c);
    firstOffset = d.getUint64(c + 8);
    c += 16;
  }
  c += 2;
  final count = d.getUint16(c);
  c += 2;
  if (count < 1 || c + count * 12 > end) return null;
  var byteCursor = end + firstOffset;
  var time = earliest.toDouble();
  final out = <MediaSegment>[];
  for (var i = 0; i < count; i++) {
    final reference = d.getUint32(c);
    final size = reference & 0x7fffffff;
    final duration = d.getUint32(c + 4).toDouble();
    c += 12;
    // Type 1 points at another sidx.
    if (reference >> 31 != 0 || size <= 0) return null;
    out.add(MediaSegment(i, ByteRange(byteCursor, byteCursor + size - 1), time / timescale, duration / timescale));
    byteCursor += size;
    time += duration;
  }
  return out;
}
