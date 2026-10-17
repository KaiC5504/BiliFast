import 'dart:convert';
import 'dart:typed_data';

abstract final class MP4Builder {
  static List<int> be16(int value) => [(value >> 8) & 0xff, value & 0xff];
  static List<int> be32(int value) => [for (var i = 0; i < 4; i++) (value >> (24 - 8 * i)) & 0xff];

  /// The raw 64 bits: pass -1 for UInt64.max.
  static List<int> be64(int value) => [for (var i = 0; i < 8; i++) (value >> (56 - 8 * i)) & 0xff];

  static List<int> box(String type, List<int> payload) => [...be32(8 + payload.length), ...ascii.encode(type), ...payload];

  /// refs: (reference word including the type bit, duration in timescale units)
  static List<int> sidx({
    required int version,
    required int timescale,
    required int earliest,
    required int firstOffset,
    required List<(int, int)> refs,
  }) {
    final payload = <int>[version, 0, 0, 0, ...be32(1), ...be32(timescale)];
    if (version == 0) {
      payload.addAll([...be32(earliest), ...be32(firstOffset)]);
    } else {
      payload.addAll([...be64(earliest), ...be64(firstOffset)]);
    }
    payload.addAll([0, 0, ...be16(refs.length)]);
    for (final (reference, duration) in refs) {
      payload.addAll([...be32(reference), ...be32(duration), ...be32(0x90000000)]);
    }
    return box('sidx', payload);
  }

  static List<int> hvcC(List<int> nalTypes) {
    final payload = <int>[...zeros(22), nalTypes.length];
    for (final type in nalTypes) {
      payload.addAll([type & 0x3f, ...be16(1), ...be16(2), 0xAA, 0xBB]);
    }
    return box('hvcC', payload);
  }

  static List<int> initSegment({required String entryType, required List<int> nalTypes}) {
    final entry = box(entryType, [...zeros(78), ...hvcC(nalTypes)]);
    final stsd = box('stsd', [0, 0, 0, 0, ...be32(1), ...entry]);
    final trak = box('trak', [...box('tkhd', zeros(84)), ...box('mdia', box('minf', box('stbl', stsd)))]);
    final moov = box('moov', [...box('mvhd', zeros(100)), ...trak]);
    return [...box('ftyp', [...ascii.encode('iso6'), ...be32(0)]), ...moov];
  }

  static List<int> zeros(int count) => List<int>.filled(count, 0);
}

Uint8List bytesOf(List<int> list) => Uint8List.fromList(list);
