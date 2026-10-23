import 'dart:math' as math;
import 'dart:typed_data';

/// A looping GIF89a of [frames], each [width] × [height] palette indexes shown for [delay]. [palette] holds up to four
/// 0xRRGGBB colours; index 0 is transparent. Written uncompressed (a clear code every two pixels keeps every code 3
/// bits), which suits the small stand-ins drawn here for tests and `--fake-account`: never the official art.
Uint8List encodeStandInGif({
  required int width,
  required int height,
  required List<Uint8List> frames,
  required List<int> palette,
  Duration delay = const Duration(milliseconds: 100),
}) {
  assert(palette.length <= 4 && frames.isNotEmpty);
  final out = BytesBuilder(copy: false);
  void word(int value) => out.add([value & 0xFF, value >> 8 & 0xFF]);

  out.add('GIF89a'.codeUnits);
  word(width);
  word(height);
  // A global table of four colours.
  out.add([0x91, 0, 0]);
  for (var index = 0; index < 4; index++) {
    final colour = index < palette.length ? palette[index] : 0;
    out.add([colour >> 16 & 0xFF, colour >> 8 & 0xFF, colour & 0xFF]);
  }
  out
    ..add([0x21, 0xFF, 0x0B])
    ..add('NETSCAPE2.0'.codeUnits)
    ..add([0x03, 0x01, 0, 0, 0]);
  final centiseconds = math.max(delay.inMilliseconds ~/ 10, 1);
  for (final frame in frames) {
    assert(frame.length == width * height);
    // Restored to the background after each frame, index 0 transparent.
    out.add([0x21, 0xF9, 0x04, 0x09]);
    word(centiseconds);
    out.add([0, 0, 0x2C]);
    word(0);
    word(0);
    word(width);
    word(height);
    out.add([0, 2]);
    final data = _uncompressed(frame);
    for (var start = 0; start < data.length; start += 255) {
      final end = math.min(start + 255, data.length);
      out
        ..addByte(end - start)
        ..add(Uint8List.sublistView(data, start, end));
    }
    out.addByte(0);
  }
  out.addByte(0x3B);
  return out.takeBytes();
}

/// LZW with a minimum code size of 2 (clear 4, end 5), cleared before the table would widen the codes past 3 bits.
Uint8List _uncompressed(Uint8List pixels) {
  final bytes = BytesBuilder(copy: false);
  var buffer = 0;
  var bits = 0;
  void code(int value) {
    buffer |= value << bits;
    bits += 3;
    while (bits >= 8) {
      bytes.addByte(buffer & 0xFF);
      buffer >>= 8;
      bits -= 8;
    }
  }

  for (var index = 0; index < pixels.length; index++) {
    if (index % 2 == 0) code(4);
    code(pixels[index] & 3);
  }
  code(5);
  if (bits > 0) bytes.addByte(buffer & 0xFF);
  return bytes.takeBytes();
}
