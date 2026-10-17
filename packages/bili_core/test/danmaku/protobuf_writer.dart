import 'dart:convert';
import 'dart:typed_data';

/// Test-only encoder; the production code only reads protobuf.
final class ProtobufWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  Uint8List get data => _builder.toBytes();

  void _rawVarint(int value) {
    var v = value;
    // Unsigned comparison: a negative int is a 64-bit pattern with the top bit set.
    while (v < 0 || v >= 0x80) {
      _builder.addByte((v & 0x7F) | 0x80);
      v >>>= 7;
    }
    _builder.addByte(v);
  }

  void _tag(int field, int wireType) => _rawVarint(field << 3 | wireType);

  void varint(int field, int value) {
    _tag(field, 0);
    _rawVarint(value);
  }

  void bytes(int field, List<int> value) {
    _tag(field, 2);
    _rawVarint(value.length);
    _builder.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void fixed32(int field, int value) {
    _tag(field, 5);
    for (var shift = 0; shift < 32; shift += 8) {
      _builder.addByte((value >>> shift) & 0xFF);
    }
  }

  void fixed64(int field, int value) {
    _tag(field, 1);
    for (var shift = 0; shift < 64; shift += 8) {
      _builder.addByte((value >>> shift) & 0xFF);
    }
  }
}

Uint8List dropLast(Uint8List bytes) => Uint8List.sublistView(bytes, 0, bytes.length - 1);
