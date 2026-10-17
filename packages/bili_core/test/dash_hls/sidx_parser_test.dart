import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/dash_hls.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

import 'mp4_builder.dart';

const int _int64Max = 0x7FFFFFFFFFFFFFFF;

void main() {
  test('version 0 after another box', () {
    final bytes = bytesOf([
      ...MP4Builder.box('free', []),
      ...MP4Builder.sidx(
          version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(1000, 2000), (2000, 2000), (1500, 1000)]),
    ]);
    final segments = SidxParser.parse(bytes, absoluteStart: 500)!;
    // sidx is 68 bytes at offset 8, so media starts at 500 + 76.
    expect(segments.map((s) => s.range), [ByteRange(576, 1575), ByteRange(1576, 3575), ByteRange(3576, 5075)]);
    expect(segments.map((s) => s.startTime), [0, 2, 4]);
    expect(segments.map((s) => s.duration), [2, 2, 1]);
    expect(segments.map((s) => s.index), [0, 1, 2]);
  });

  test('version 1 with earliest time and offset', () {
    final bytes =
        bytesOf(MP4Builder.sidx(version: 1, timescale: 90000, earliest: 90000, firstOffset: 10, refs: [(4000, 180000)]));
    final segment = SidxParser.parse(bytes, absoluteStart: 0)!.first;
    expect(segment.startTime, 1);
    expect(segment.duration, 2);
    expect(segment.range.start, bytes.length + 10);
  });

  test('a hierarchical reference rejects the whole index', () {
    final bytes = bytesOf(MP4Builder.sidx(
        version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(0x80000000 | 100, 10), (200, 10)]));
    expect(SidxParser.parse(bytes, absoluteStart: 0), isNull);
  });

  test('an unknown version and a zero-size reference are rejected', () {
    expect(
        SidxParser.parse(bytesOf(MP4Builder.sidx(version: 2, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(10, 10)])),
            absoluteStart: 0),
        isNull);
    expect(
        SidxParser.parse(bytesOf(MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(0, 10)])),
            absoluteStart: 0),
        isNull);
  });

  test('rejects broken input', () {
    expect(SidxParser.parse(bytesOf([1, 2, 3]), absoluteStart: 0), isNull);
    expect(SidxParser.parse(bytesOf(MP4Builder.box('free', [0, 0])), absoluteStart: 0), isNull);
    expect(
        SidxParser.parse(bytesOf(MP4Builder.sidx(version: 0, timescale: 0, earliest: 0, firstOffset: 0, refs: [(10, 10)])),
            absoluteStart: 0),
        isNull);
  });

  test('BoxReader stops at a truncated box', () {
    final bytes = bytesOf([...MP4Builder.box('ftyp', [1, 2, 3, 4]), ...MP4Builder.be32(100), ...ascii.encode('moov')]);
    expect(BoxReader.boxes(bytes, from: 0, to: bytes.length).map((b) => b.type), ['ftyp']);
  });

  test('a truncated sidx returns null for both versions', () {
    for (final version in [0, 1]) {
      final full = bytesOf(
          MP4Builder.sidx(version: version, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(10, 10), (10, 10)]));
      expect(SidxParser.parse(full, absoluteStart: 0), isNotNull);
      for (var length = 0; length < full.length; length++) {
        expect(SidxParser.parse(Uint8List.sublistView(full, 0, length), absoluteStart: 0), isNull,
            reason: 'version $version, $length bytes');
      }
    }
  });

  test('a box size covering a payload too short for the version 1 header', () {
    // The box is well-formed, but its payload ends before the 64-bit fields do.
    final payload = [1, 0, 0, 0, ...MP4Builder.be32(1), ...MP4Builder.be32(1000), ...MP4Builder.be64(0)];
    expect(SidxParser.parse(bytesOf(MP4Builder.box('sidx', payload)), absoluteStart: 0), isNull);
  });

  test('a reference count larger than the available bytes is rejected', () {
    final payload = [
      0, 0, 0, 0, ...MP4Builder.be32(1), ...MP4Builder.be32(1000), ...MP4Builder.be32(0), ...MP4Builder.be32(0),
      0, 0, ...MP4Builder.be16(60000),
      ...MP4Builder.be32(10), ...MP4Builder.be32(10), ...MP4Builder.be32(0),
    ];
    expect(SidxParser.parse(bytesOf(MP4Builder.box('sidx', payload)), absoluteStart: 0), isNull);
  });

  test('large indexes parse up to the 16-bit reference limit', () {
    for (final count in [10001, 0xFFFF]) {
      final refs = List.filled(count, (100, 10));
      final bytes = bytesOf(MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: refs));
      final segments = SidxParser.parse(bytes, absoluteStart: 0);
      expect(segments, isNotNull, reason: '$count references');
      expect(segments!.length, count);
      expect(segments.last.range.end, bytes.length + count * 100 - 1);
    }
  });

  test('huge offsets and sizes do not overflow', () {
    final hugeOffset =
        bytesOf(MP4Builder.sidx(version: 1, timescale: 1000, earliest: -1, firstOffset: -1, refs: [(10, 10)]));
    expect(SidxParser.parse(hugeOffset, absoluteStart: 0), isNull);
    final nearLimit = bytesOf(MP4Builder.sidx(
        version: 1, timescale: 1000, earliest: 0, firstOffset: _int64Max - 10, refs: [(0x7fffffff, 10)]));
    expect(SidxParser.parse(nearLimit, absoluteStart: 100), isNull);
    final hugeStart = bytesOf(MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(10, 10)]));
    expect(SidxParser.parse(hugeStart, absoluteStart: _int64Max), isNull);
  });

  test('BoxReader rejects huge sizes', () {
    final largeSize = bytesOf([...MP4Builder.be32(1), ...ascii.encode('free'), ...MP4Builder.be64(_int64Max)]);
    expect(BoxReader.boxes(largeSize, from: 0, to: largeSize.length), isEmpty);
    final belowHeader = bytesOf([...MP4Builder.be32(1), ...ascii.encode('free'), ...MP4Builder.be64(4)]);
    expect(BoxReader.boxes(belowHeader, from: 0, to: belowHeader.length), isEmpty);
    final tail = bytesOf([...MP4Builder.be32(0), ...ascii.encode('mdat'), 1, 2, 3]);
    expect(BoxReader.boxes(tail, from: 0, to: tail.length).map((b) => b.end), [11]);
  });

  test('a 64-bit size above Int64.max is rejected rather than read as negative', () {
    final aboveMax = bytesOf([...MP4Builder.be32(1), ...ascii.encode('free'), ...MP4Builder.be64(-16)]);
    expect(BoxReader.boxes(aboveMax, from: 0, to: aboveMax.length), isEmpty);
    expect(BoxReader.uint64(aboveMax, 8), -16, reason: 'the raw 64 bits, as Int64(bitPattern:) would give');
  });

  test('a version 1 earliest time above Int64.max counts as unsigned', () {
    final bytes = bytesOf(MP4Builder.sidx(version: 1, timescale: 1, earliest: -1, firstOffset: 0, refs: [(10, 10)]));
    expect(SidxParser.parse(bytes, absoluteStart: 0)!.first.startTime, 18446744073709551615.0);
  });

  test('a negative absolute start gives no segments', () {
    final bytes = bytesOf(MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(10, 10)]));
    expect(SidxParser.parse(bytes, absoluteStart: -1000), isNull);
  });
}
