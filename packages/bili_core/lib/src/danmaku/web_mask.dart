import 'dart:typed_data';

/// The head of a `.webmask` file (人像防挡): `MASK`, a big-endian u32 version (1), a check byte, three spare bytes, a
/// u32 segment count, then that many pairs of i64 (start in ms, byte offset of the segment). Each segment runs to the
/// next one's offset, or to the end of the file, and covers about 10 s.
final class WebMaskIndex {
  const WebMaskIndex({required this.segments, required this.headerLength});

  /// Reads the head; [bytes] must hold at least [headerLengthOf] bytes. Throws [FormatException] on anything else.
  factory WebMaskIndex.parse(Uint8List bytes) => throw UnimplementedError();

  /// How many bytes the head takes, from its first 16.
  static int headerLengthOf(Uint8List first16) => throw UnimplementedError();

  final List<({int startMs, int offset})> segments;
  final int headerLength;

  /// The segment [ms] falls in, or null before the first.
  int? segmentAt(int ms) => throw UnimplementedError();
}

/// One mask frame: its time in the video and its picture, an SVG (potrace's output: a `<g>` transform and one
/// path whose filled area is where danmaku may draw; the people are its holes).
typedef WebMaskFrame = ({int ms, String svg});

/// The frames of one segment: gzip, then repeated (u32 length, u64 ms, a `data:image/svg+xml;base64,` URI of that
/// length). Throws [FormatException] on a damaged segment.
List<WebMaskFrame> decodeWebMaskSegment(Uint8List gzipped) => throw UnimplementedError();
