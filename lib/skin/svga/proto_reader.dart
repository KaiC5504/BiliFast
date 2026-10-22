import 'dart:convert';
import 'dart:typed_data';

/// Protobuf's wire format, read by hand: SVGA 2's `MovieEntity` is all this needs, so no generated code.
final class ProtoReader {
  ProtoReader(Uint8List bytes) : _bytes = bytes, _data = ByteData.sublistView(bytes);

  static const varint = 0;
  static const fixed64 = 1;
  static const lengthDelimited = 2;
  static const fixed32 = 5;

  final Uint8List _bytes;
  final ByteData _data;
  int _pos = 0;

  bool get done => _pos >= _bytes.length;

  /// The next field's tag; its number is `tag >> 3`, its wire type `tag & 7`.
  int readTag() {
    final tag = readVarint();
    if (tag >> 3 == 0) throw const FormatException('protobuf field number 0');
    return tag;
  }

  int readVarint() {
    var result = 0;
    for (var shift = 0; shift < 70; shift += 7) {
      _need(1);
      final byte = _bytes[_pos++];
      result |= (byte & 0x7F) << shift;
      if (byte < 0x80) return result;
    }
    throw const FormatException('protobuf varint too long');
  }

  double readFloat() {
    _need(4);
    final value = _data.getFloat32(_pos, Endian.little);
    _pos += 4;
    return value;
  }

  Uint8List readBytes() {
    final length = readVarint();
    if (length < 0) throw const FormatException('protobuf length is negative');
    _need(length);
    final view = Uint8List.sublistView(_bytes, _pos, _pos + length);
    _pos += length;
    return view;
  }

  String readString() => utf8.decode(readBytes(), allowMalformed: true);

  ProtoReader readMessage() => ProtoReader(readBytes());

  /// A float field; 0 when it isn't finite, or when the writer used another wire type (which is skipped).
  double floatField(int tag) {
    if (tag & 7 != fixed32) {
      skip(tag);
      return 0;
    }
    final value = readFloat();
    return value.isFinite ? value : 0;
  }

  int intField(int tag) {
    if (tag & 7 == varint) return readVarint().toSigned(32);
    skip(tag);
    return 0;
  }

  String stringField(int tag) {
    if (tag & 7 == lengthDelimited) return readString();
    skip(tag);
    return '';
  }

  ProtoReader? messageField(int tag) {
    if (tag & 7 == lengthDelimited) return readMessage();
    skip(tag);
    return null;
  }

  void skip(int tag) {
    switch (tag & 7) {
      case varint:
        readVarint();
      case fixed64:
        _need(8);
        _pos += 8;
      case lengthDelimited:
        readBytes();
      case fixed32:
        _need(4);
        _pos += 4;
      default:
        throw FormatException('protobuf wire type ${tag & 7} is not supported');
    }
  }

  void _need(int count) {
    if (_pos + count > _bytes.length) throw const FormatException('protobuf message is truncated');
  }
}
