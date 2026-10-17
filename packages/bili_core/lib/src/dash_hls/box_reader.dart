import 'dart:convert';
import 'dart:typed_data';

final class BoxHeader {
  const BoxHeader({required this.type, required this.start, required this.headerSize, required this.end});

  final String type;
  final int start;
  final int headerSize;

  /// Exclusive.
  final int end;

  int get payloadStart => start + headerSize;

  @override
  bool operator ==(Object other) =>
      other is BoxHeader &&
      other.type == type &&
      other.start == start &&
      other.headerSize == headerSize &&
      other.end == end;

  @override
  int get hashCode => Object.hash(type, start, headerSize, end);

  @override
  String toString() => 'BoxHeader($type, $start..$end)';
}

abstract final class BoxReader {
  static int uint16(Uint8List bytes, int offset) => bytes[offset] << 8 | bytes[offset + 1];

  static int uint32(Uint8List bytes, int offset) {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      value = value << 8 | bytes[offset + i];
    }
    return value;
  }

  /// The raw 64 bits: a value above 2^63 - 1 comes back negative, as Swift's `Int64(bitPattern:)` would give.
  static int uint64(Uint8List bytes, int offset) {
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = value << 8 | bytes[offset + i];
    }
    return value;
  }

  static String type(Uint8List bytes, int offset) =>
      utf8.decode(Uint8List.sublistView(bytes, offset, offset + 4), allowMalformed: true);

  /// Sibling boxes between `from` and `to`. Stops at the first malformed or truncated box, so a
  /// buffer that ends mid-file still yields the complete boxes before the cut.
  static List<BoxHeader> boxes(Uint8List bytes, {required int from, required int to}) {
    final result = <BoxHeader>[];
    var offset = from;
    final limit = to < bytes.length ? to : bytes.length;
    while (offset >= 0 && limit - offset >= 8) {
      var size = uint32(bytes, offset);
      var header = 8;
      if (size == 1) {
        if (offset + 16 > limit) break;
        final large = uint64(bytes, offset + 8);
        // Negative means above Int64.max.
        if (large < 0) break;
        size = large;
        header = 16;
      } else if (size == 0) {
        size = limit - offset;
      }
      // Compared as a remaining length so a hostile 64-bit size cannot overflow the addition.
      if (size < header || size > limit - offset) break;
      result.add(BoxHeader(type: type(bytes, offset + 4), start: offset, headerSize: header, end: offset + size));
      offset += size;
    }
    return result;
  }
}
