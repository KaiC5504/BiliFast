import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:bili_core/danmaku.dart';
import 'package:test/test.dart';

/// A made-up frame in potrace's shape: the whole picture filled, a person-shaped hole in it.
String svgFrame(int n) =>
    '<svg width="180.000000px" height="320.000000px" viewBox="0 0 180.000000 320.000000">'
    '<g transform="translate(0.000000,320.000000) scale(0.100000,-0.100000)" fill="#000000" stroke="none">'
    '<path d="M0 1605 l0 -1595 900 0 900 0 0 1595 0 1595 -900 0 -900 0 0 -1595z m${600 + n} 800 c-50 0 -90 40 '
    '-90 90 0 50 40 90 90 90 50 0 90 -40 90 -90 0 -50 -40 -90 -90 -90z"/></g></svg>';

Uint8List record(int ms, String uri, {int? length}) {
  final body = utf8.encode(uri);
  final head = ByteData(12)
    ..setUint32(0, length ?? body.length)
    ..setUint64(4, ms);
  return Uint8List.fromList([...head.buffer.asUint8List(), ...body]);
}

String dataUri(String svg) => 'data:image/svg+xml;base64,${base64.encode(utf8.encode(svg))}';

Uint8List segmentOf(List<int> times) =>
    Uint8List.fromList(gzip.encode([for (final ms in times) ...record(ms, dataUri(svgFrame(ms)))]));

Uint8List gzipped(List<int> raw) => Uint8List.fromList(gzip.encode(raw));

/// A `.webmask` file: the head as Bilibili writes it, then [segments] back to back.
Uint8List webmask(
  List<(int startMs, Uint8List segment)> segments, {
  String magic = 'MASK',
  int version = 1,
  int? count,
  List<int>? offsets,
}) {
  final headerLength = 16 + 16 * segments.length;
  final head = ByteData(headerLength)
    ..setUint32(4, version)
    ..setUint8(8, 2)
    ..setUint32(12, count ?? segments.length);
  head.buffer.asUint8List().setAll(0, ascii.encode(magic));
  var offset = headerLength;
  for (final (k, (startMs, segment)) in segments.indexed) {
    head
      ..setInt64(16 + 16 * k, startMs)
      ..setInt64(24 + 16 * k, offsets?[k] ?? offset);
    offset += segment.length;
  }
  return Uint8List.fromList([...head.buffer.asUint8List(), for (final (_, segment) in segments) ...segment]);
}

void main() {
  final first = segmentOf([0, 33, 67]);
  final second = segmentOf([10000, 10033]);
  final file = webmask([(0, first), (10000, second)]);

  group('the head', () {
    test('reads the segments, their starts and offsets', () {
      final index = WebMaskIndex.parse(file);
      expect(index.headerLength, 48);
      expect(index.segments, [(startMs: 0, offset: 48), (startMs: 10000, offset: 48 + first.length)]);
    });

    test('its length comes from the first 16 bytes', () {
      expect(WebMaskIndex.headerLengthOf(Uint8List.sublistView(file, 0, WebMaskIndex.prefixLength)), 48);
      final seventeen = webmask([for (var k = 0; k < 17; k++) (k * 10000, first)]);
      expect(WebMaskIndex.headerLengthOf(Uint8List.sublistView(seventeen, 0, 16)), 288);
    });

    test('parses from the head alone', () {
      expect(WebMaskIndex.parse(Uint8List.sublistView(file, 0, 48)).segments, hasLength(2));
    });

    test('finds the segment a time falls in, none before the first', () {
      final index = WebMaskIndex.parse(file);
      expect(index.segmentAt(0), 0);
      expect(index.segmentAt(9999), 0);
      expect(index.segmentAt(10000), 1);
      expect(index.segmentAt(999999), 1);
      expect(index.segmentAt(-1), isNull);
      final later = WebMaskIndex.parse(webmask([(500, first), (10000, second), (20000, first)]));
      expect(later.segmentAt(499), isNull);
      expect(later.segmentAt(500), 0);
      expect(later.segmentAt(15000), 1);
      expect(later.segmentAt(20000), 2);
    });

    test('gives each segment its byte range, the last running to the end', () {
      final index = WebMaskIndex.parse(file);
      expect(index.rangeOf(0), (start: 48, end: 48 + first.length - 1));
      expect(index.rangeOf(1), (start: 48 + first.length, end: null));
      expect(() => index.rangeOf(2), throwsRangeError);
      expect(() => index.rangeOf(-1), throwsRangeError);
    });
  });

  group('a segment', () {
    test('decodes its frames from the ranges the head gives', () {
      final index = WebMaskIndex.parse(file);
      Uint8List bytesOf(int k) {
        final (:start, :end) = index.rangeOf(k);
        return Uint8List.sublistView(file, start, end == null ? file.length : end + 1);
      }

      expect(decodeWebMaskSegment(bytesOf(0)), [
        (ms: 0, svg: svgFrame(0)),
        (ms: 33, svg: svgFrame(33)),
        (ms: 67, svg: svgFrame(67)),
      ]);
      expect(decodeWebMaskSegment(bytesOf(1)), [
        (ms: 10000, svg: svgFrame(10000)),
        (ms: 10033, svg: svgFrame(10033)),
      ]);
    });

    test('with no records has no frames', () {
      expect(decodeWebMaskSegment(gzipped([])), isEmpty);
    });

    test('frames sharing a time are kept in order', () {
      final frames = decodeWebMaskSegment(
        gzipped([...record(40, dataUri('<svg>a</svg>')), ...record(40, dataUri('<svg>b</svg>'))]),
      );
      expect(frames, [(ms: 40, svg: '<svg>a</svg>'), (ms: 40, svg: '<svg>b</svg>')]);
    });

    test("base64 wrapped in 76-character lines, as Bilibili's files have it", () {
      final svg = svgFrame(0);
      final encoded = base64.encode(utf8.encode(svg));
      final wrapped = [
        for (var at = 0; at < encoded.length; at += 76) encoded.substring(at, (at + 76).clamp(0, encoded.length)),
      ].join('\n');
      expect(wrapped, contains('\n'));
      final frames = decodeWebMaskSegment(gzipped(record(0, 'data:image/svg+xml;base64,$wrapped\n')));
      expect(frames.single.svg, svg);
    });
  });

  group('a damaged file throws FormatException', () {
    test('a head shorter than 16 bytes', () {
      expect(() => WebMaskIndex.headerLengthOf(Uint8List.sublistView(file, 0, 15)), throwsFormatException);
      expect(() => WebMaskIndex.parse(Uint8List(0)), throwsFormatException);
    });

    test('another magic', () {
      expect(() => WebMaskIndex.parse(webmask([(0, first)], magic: 'MASQ')), throwsFormatException);
    });

    test('another version', () {
      expect(() => WebMaskIndex.parse(webmask([(0, first)], version: 2)), throwsFormatException);
    });

    test('no segments, or more than any video has', () {
      expect(() => WebMaskIndex.parse(webmask([])), throwsFormatException);
      expect(
        () => WebMaskIndex.headerLengthOf(webmask([(0, first)], count: WebMaskIndex.maxSegments + 1)),
        throwsFormatException,
      );
    });

    test('a count that does not fit the bytes given, or the head', () {
      final miscounted = webmask([(0, first), (10000, second)], count: 3);
      expect(() => WebMaskIndex.parse(Uint8List.sublistView(miscounted, 0, 48)), throwsFormatException);
      expect(() => WebMaskIndex.parse(miscounted), throwsFormatException);
      expect(() => WebMaskIndex.parse(Uint8List.sublistView(file, 0, 47)), throwsFormatException);
    });

    test('offsets out of order, or not starting right after the head', () {
      final swapped = webmask([(0, first), (10000, second)], offsets: [48 + first.length, 48]);
      expect(() => WebMaskIndex.parse(swapped), throwsFormatException);
      final same = webmask([(0, first), (10000, second)], offsets: [48, 48]);
      expect(() => WebMaskIndex.parse(same), throwsFormatException);
      final inHead = webmask([(0, first), (10000, second)], offsets: [40, 48 + first.length]);
      expect(() => WebMaskIndex.parse(inHead), throwsFormatException);
      final gap = webmask([(0, first), (10000, second)], offsets: [56, 56 + first.length]);
      expect(() => WebMaskIndex.parse(gap), throwsFormatException);
    });

    test('starts out of order, or before 0', () {
      expect(() => WebMaskIndex.parse(webmask([(10000, first), (0, second)])), throwsFormatException);
      expect(() => WebMaskIndex.parse(webmask([(0, first), (0, second)])), throwsFormatException);
      expect(() => WebMaskIndex.parse(webmask([(-1, first)])), throwsFormatException);
    });

    test('a segment that is not gzip, or whose gzip is damaged', () {
      expect(() => decodeWebMaskSegment(utf8.encode('not a segment at all')), throwsFormatException);
      final damaged = Uint8List.fromList(first);
      for (var i = 10; i < damaged.length - 8; i++) {
        damaged[i] = 0xFF;
      }
      expect(() => decodeWebMaskSegment(damaged), throwsFormatException);
    });

    test('a segment cut short in the gzip', () {
      for (final cut in [1, 4, 8, first.length ~/ 2]) {
        expect(
          () => decodeWebMaskSegment(Uint8List.sublistView(first, 0, first.length - cut)),
          throwsFormatException,
          reason: 'cut $cut',
        );
      }
    });

    test('a record cut short', () {
      final uri = dataUri(svgFrame(0));
      expect(() => decodeWebMaskSegment(gzipped(record(0, uri, length: uri.length + 1))), throwsFormatException);
      expect(() => decodeWebMaskSegment(gzipped([...record(0, uri), 0, 0, 0, 5, 0, 0])), throwsFormatException);
    });

    test('a record that is not an SVG data URI, or whose base64 is bad', () {
      expect(() => decodeWebMaskSegment(gzipped(record(0, 'data:image/png;base64,AAAA'))), throwsFormatException);
      expect(
        () => decodeWebMaskSegment(gzipped(record(0, 'data:image/svg+xml;base64,@@not base64@@'))),
        throwsFormatException,
      );
    });

    test('frames going back in time', () {
      final backwards = gzipped([...record(67, dataUri(svgFrame(67))), ...record(33, dataUri(svgFrame(33)))]);
      expect(() => decodeWebMaskSegment(backwards), throwsFormatException);
    });
  });
}
