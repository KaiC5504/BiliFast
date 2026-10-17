import 'dart:typed_data';

enum ProtobufErrorKind { truncated, badWireType }

final class ProtobufError implements Exception {
  const ProtobufError.truncated() : kind = ProtobufErrorKind.truncated, wireType = null;
  const ProtobufError.badWireType(int this.wireType) : kind = ProtobufErrorKind.badWireType;

  final ProtobufErrorKind kind;
  final int? wireType;

  @override
  bool operator ==(Object other) => other is ProtobufError && other.kind == kind && other.wireType == wireType;

  @override
  int get hashCode => Object.hash(kind, wireType);

  @override
  String toString() => wireType == null ? 'ProtobufError.${kind.name}' : 'ProtobufError.${kind.name}($wireType)';
}

/// Just enough protobuf to read Bilibili's danmaku replies without a package.
final class ProtobufReader {
  ProtobufReader(this._data);

  final Uint8List _data;
  int _position = 0;

  /// The next field's number and wire type, or null at the end of the input.
  ({int field, int wireType})? next() {
    if (_position >= _data.length) return null;
    final tag = varint();
    return (field: tag >>> 3, wireType: tag & 7);
  }

  /// The raw 64 bits; a value above 2^63 - 1 comes back negative, as Swift's `Int64(bitPattern:)` would give.
  int varint() {
    var result = 0;
    var shift = 0;
    while (_position < _data.length) {
      final byte = _data[_position++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
      // A varint is at most 10 bytes; more is not a protobuf we can read.
      if (shift > 63) throw const ProtobufError.truncated();
    }
    throw const ProtobufError.truncated();
  }

  /// A view into the input, not a copy.
  Uint8List lengthDelimited() {
    final length = varint();
    // A negative length is a varint above 2^63, so it is longer than any input.
    if (length < 0 || length > _data.length - _position) throw const ProtobufError.truncated();
    final start = _position;
    _position += length;
    return Uint8List.sublistView(_data, start, _position);
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        varint();
      case 1:
        _advance(8);
      case 2:
        lengthDelimited();
      case 5:
        _advance(4);
      default:
        throw ProtobufError.badWireType(wireType);
    }
  }

  void _advance(int count) {
    if (count > _data.length - _position) throw const ProtobufError.truncated();
    _position += count;
  }
}
