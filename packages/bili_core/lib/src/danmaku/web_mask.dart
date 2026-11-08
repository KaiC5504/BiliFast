import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

/// The head of a `.webmask` file (人像防挡): `MASK`, a big-endian u32 version (1), a check byte, three spare bytes, a
/// u32 segment count, then that many pairs of i64 (start in ms, byte offset of the segment). Each segment runs to the
/// next one's offset, or to the end of the file, and covers about 10 s.
final class WebMaskIndex {
  const WebMaskIndex({required this.segments, required this.headerLength});

  /// Reads the head; [bytes] must hold at least [headerLengthOf] bytes. Throws [FormatException] on anything else.
  factory WebMaskIndex.parse(Uint8List bytes) {
    final headerLength = headerLengthOf(bytes);
    if (bytes.length < headerLength) {
      throw FormatException('webmask head: $headerLength bytes needed, ${bytes.length} given');
    }
    final data = ByteData.sublistView(bytes);
    final segments = <({int startMs, int offset})>[];
    for (var at = prefixLength; at < headerLength; at += 16) {
      final segment = (startMs: data.getInt64(at), offset: data.getInt64(at + 8));
      // The first segment starts right after the head, which also catches a count that is off.
      final ordered = switch (segments.lastOrNull) {
        null => segment.startMs >= 0 && segment.offset == headerLength,
        final previous => segment.startMs > previous.startMs && segment.offset > previous.offset,
      };
      if (!ordered) throw FormatException('webmask head: segment ${segments.length} out of order');
      segments.add(segment);
    }
    return WebMaskIndex(segments: List.unmodifiable(segments), headerLength: headerLength);
  }

  /// How many bytes [headerLengthOf] reads.
  static const prefixLength = 16;

  /// A day and more of 10 s segments; a bigger count is a damaged head, and would ask for megabytes of it.
  static const maxSegments = 1 << 14;

  /// How many bytes the head takes, from its first 16.
  static int headerLengthOf(Uint8List first16) {
    if (first16.length < prefixLength) throw FormatException('webmask head: ${first16.length} bytes, 16 needed');
    if (first16[0] != 0x4D || first16[1] != 0x41 || first16[2] != 0x53 || first16[3] != 0x4B) {
      throw const FormatException('webmask head: not a mask file');
    }
    final data = ByteData.sublistView(first16);
    final version = data.getUint32(4);
    if (version != 1) throw FormatException('webmask head: version $version');
    final count = data.getUint32(12);
    if (count == 0 || count > maxSegments) throw FormatException('webmask head: $count segments');
    return prefixLength + 16 * count;
  }

  final List<({int startMs, int offset})> segments;
  final int headerLength;

  /// The segment [ms] falls in, or null before the first.
  int? segmentAt(int ms) {
    var low = 0;
    var high = segments.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (segments[middle].startMs <= ms) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low == 0 ? null : low - 1;
  }

  /// Segment [index]'s bytes in the file, [end] inclusive as BiliClient.maskRange takes them; null for the last
  /// segment, which runs to the end of the file.
  ({int start, int? end}) rangeOf(int index) {
    RangeError.checkValidIndex(index, segments, 'index');
    final next = index + 1 < segments.length ? segments[index + 1].offset : null;
    return (start: segments[index].offset, end: next == null ? null : next - 1);
  }
}

/// One mask frame: its time in the video and its picture, an SVG (potrace's output: a `<g>` transform and paths
/// whose filled area is where danmaku may draw; the people are the holes).
typedef WebMaskFrame = ({int ms, String svg});

const _svgDataUri = 'data:image/svg+xml;base64,';
final _lineBreaks = RegExp(r'\s');

/// The frames of one segment: gzip, then repeated (u32 length, i64 ms, a `data:image/svg+xml;base64,` URI of that
/// length). Throws [FormatException] on a damaged segment.
List<WebMaskFrame> decodeWebMaskSegment(Uint8List gzipped) {
  final bytes = _inflate(gzipped);
  final data = ByteData.sublistView(bytes);
  final frames = <WebMaskFrame>[];
  var at = 0;
  while (at < bytes.length) {
    if (bytes.length - at < 12) throw FormatException('webmask segment: record at byte $at cut short');
    final length = data.getUint32(at);
    final ms = data.getInt64(at + 4);
    final start = at + 12;
    if (bytes.length - start < length) throw FormatException('webmask segment: record at byte $at cut short');
    if (ms < 0 || (frames.isNotEmpty && ms < frames.last.ms)) {
      throw FormatException('webmask segment: record at byte $at out of order');
    }
    frames.add((ms: ms, svg: _svgOf(Uint8List.sublistView(bytes, start, start + length), at)));
    at = start + length;
  }
  return frames;
}

Uint8List _inflate(Uint8List gzipped) {
  if (gzipped.length < 18 || gzipped[0] != 0x1F || gzipped[1] != 0x8B) {
    throw const FormatException('webmask segment: not gzip');
  }
  final List<int> inflated;
  try {
    inflated = gzip.decode(gzipped);
  } on FormatException {
    throw const FormatException('webmask segment: damaged gzip');
  }
  // dart:io inflates a stream cut off mid-way without complaint; the trailer's length (mod 2^32) tells.
  final size = ByteData.sublistView(gzipped).getUint32(gzipped.length - 4, Endian.little);
  if (inflated.length & 0xFFFFFFFF != size) throw const FormatException('webmask segment: gzip cut short');
  return inflated is Uint8List ? inflated : Uint8List.fromList(inflated);
}

String _svgOf(Uint8List record, int at) {
  final uri = latin1.decode(record);
  if (!uri.startsWith(_svgDataUri)) throw FormatException('webmask segment: record at byte $at is not an SVG');
  try {
    // Bilibili's files wrap the base64 in 76-character lines, which dart:convert refuses.
    return utf8.decode(base64.decode(uri.substring(_svgDataUri.length).replaceAll(_lineBreaks, '')));
  } on FormatException {
    throw FormatException('webmask segment: record at byte $at does not decode');
  }
}
