import 'dart:typed_data';

final class BoxHeader {
  const BoxHeader({required this.type, required this.start, required this.headerSize, required this.end});

  final String type;
  final int start;
  final int headerSize;
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
  static int uint16(Uint8List bytes, int offset) => throw UnimplementedError('port of BoxReader.swift');

  static int uint32(Uint8List bytes, int offset) => throw UnimplementedError('port of BoxReader.swift');

  static int uint64(Uint8List bytes, int offset) => throw UnimplementedError('port of BoxReader.swift');

  static List<BoxHeader> boxes(Uint8List bytes, {required int from, required int to}) =>
      throw UnimplementedError('port of BoxReader.swift');
}
