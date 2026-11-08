import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bili_core/danmaku.dart' show WebMaskFrame;

/// A made-up `.webmask` file in Bilibili's layout: `MASK`, version 1, a check byte, three zero bytes, the segment
/// count, the (start ms, offset) pairs, then each segment gzipped as (u32 length, i64 ms, a base64 SVG data URI, its
/// base64 in 76-character lines as Bilibili's files have it).
final class WebMaskFile {
  WebMaskFile(this.segments, {required this.startsMs}) : assert(segments.length == startsMs.length) {
    final head = BytesBuilder();
    final bodies = [for (final frames in segments) Uint8List.fromList(gzip.encode(_records(frames)))];
    headerLength = 16 + 16 * segments.length;
    head
      ..add(ascii.encode('MASK'))
      ..add(_u32(1))
      ..add([0x02, 0, 0, 0])
      ..add(_u32(segments.length));
    var offset = headerLength;
    offsets = [];
    for (var i = 0; i < segments.length; i++) {
      offsets.add(offset);
      head
        ..add(_i64(startsMs[i]))
        ..add(_i64(offset));
      offset += bodies[i].length;
    }
    final out = BytesBuilder()..add(head.toBytes());
    bodies.forEach(out.add);
    bytes = out.toBytes();
  }

  /// Ten-second segments of 30 fps frames, each frame's path a square whose left edge is the frame's ms (so
  /// `path.getBounds().left` tells frames apart); a segment's first frame comes [firstFrameMs] after its start.
  factory WebMaskFile.tagged({required int segments, int framesPerSegment = 300, int firstFrameMs = 0}) {
    int msOf(int s, int f) => s * 10000 + firstFrameMs + (f * 1000 / 30).round();
    return WebMaskFile(
      [
        for (var s = 0; s < segments; s++)
          [for (var f = 0; f < framesPerSegment; f++) (ms: msOf(s, f), svg: squareSvg(msOf(s, f)))],
      ],
      startsMs: [for (var s = 0; s < segments; s++) s * 10000],
    );
  }

  final List<List<WebMaskFrame>> segments;
  final List<int> startsMs;
  late final int headerLength;
  late final List<int> offsets;
  late final Uint8List bytes;

  /// The inclusive range segment [k] takes.
  (int, int?) rangeOf(int k) => (offsets[k], k + 1 < offsets.length ? offsets[k + 1] - 1 : null);

  static List<int> _records(List<WebMaskFrame> frames) {
    final out = BytesBuilder();
    for (final frame in frames) {
      final encoded = base64.encode(utf8.encode(frame.svg));
      final lines = [
        for (var at = 0; at < encoded.length; at += 76) encoded.substring(at, math.min(at + 76, encoded.length)),
      ];
      final uri = ascii.encode('data:image/svg+xml;base64,${lines.join('\n')}\n');
      out
        ..add(_u32(uri.length))
        ..add(_i64(frame.ms))
        ..add(uri);
    }
    return out.toBytes();
  }

  static List<int> _u32(int value) => (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

  static List<int> _i64(int value) => (ByteData(8)..setInt64(0, value)).buffer.asUint8List();
}

/// potrace's SVG of a 10 × 10 square with its left edge at [left] and its top at 10, in the box's units.
String squareSvg(num left) => potraceSvg(['M${left * 10} 3100 l100 0 0 -100 -100 0z']);

/// [paths] in potrace's wrapping: a 180 × 320 viewBox, and a `<g>` flipping its 0.1-unit paths back up.
String potraceSvg(List<String> paths) =>
    '<?xml version="1.0" standalone="no"?>\n'
    '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 20010904//EN"\n'
    ' "http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd">\n'
    '<svg version="1.0" xmlns="http://www.w3.org/2000/svg"\n'
    ' width="180.000000pt" height="320.000000pt" viewBox="0 0 180.000000 320.000000"\n'
    ' preserveAspectRatio="xMidYMid meet">\n'
    '<metadata>\nCreated by potrace 1.16, written by Peter Selinger 2001-2019\n</metadata>\n'
    '<g transform="translate(0.000000,320.000000) scale(0.100000,-0.100000)"\n'
    'fill="#000000" stroke="none">\n'
    '${[for (final d in paths) '<path d="$d"/>'].join('\n')}\n'
    '</g>\n</svg>\n';
