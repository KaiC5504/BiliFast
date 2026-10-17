import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/danmaku.dart';
import 'package:test/test.dart';

import 'protobuf_writer.dart';

void main() {
  test('reads multi-byte varints and field tags', () {
    final w = ProtobufWriter()
      ..varint(1, 300)
      ..varint(2, 0xFFFFFFFFFFFFFFFF);
    final r = ProtobufReader(w.data);
    final first = r.next()!;
    expect(first.field, 1);
    expect(first.wireType, 0);
    expect(r.varint(), 300);
    r.next();
    expect(r.varint(), 0xFFFFFFFFFFFFFFFF);
    expect(r.next(), isNull);
  });

  test('length-delimited returns the bytes and advances', () {
    final w = ProtobufWriter()
      ..string(3, '弹幕')
      ..varint(4, 9);
    final r = ProtobufReader(w.data);
    expect(r.next()?.wireType, 2);
    expect(utf8.decode(r.lengthDelimited()), '弹幕');
    expect(r.next()?.field, 4);
  });

  test('skip passes every known wire type and rejects the rest', () {
    final w = ProtobufWriter()
      ..varint(1, 5)
      ..fixed64(2, 7)
      ..string(3, 'x')
      ..fixed32(4, 9)
      ..varint(5, 1);
    final r = ProtobufReader(w.data);
    final seen = <int>[];
    for (var tag = r.next(); tag != null; tag = r.next()) {
      seen.add(tag.field);
      r.skip(tag.wireType);
    }
    expect(seen, [1, 2, 3, 4, 5]);
    final r2 = ProtobufReader(Uint8List.fromList([0x0B]));
    final tag = r2.next()!;
    expect(tag.wireType, 3);
    expect(() => r2.skip(3), throwsA(const ProtobufError.badWireType(3)));
  });

  test('truncated input throws', () {
    final overlong = ProtobufReader(Uint8List.fromList([0x80]));
    expect(overlong.varint, throwsA(const ProtobufError.truncated()));

    final w = ProtobufWriter()..string(1, 'hello');
    final short = ProtobufReader(dropLast(w.data));
    try {
      short.next();
    } on ProtobufError {
      // Swift's `try?`: the tag may or may not read; only lengthDelimited is under test.
    }
    expect(short.lengthDelimited, throwsA(const ProtobufError.truncated()));

    final f = ProtobufWriter()..fixed64(1, 1);
    final fixed = ProtobufReader(dropLast(f.data));
    expect(fixed.next()?.wireType, 1);
    expect(() => fixed.skip(1), throwsA(const ProtobufError.truncated()));
  });

  test('a reader over a slice keeps its own offsets', () {
    final w = ProtobufWriter()
      ..varint(1, 1)
      ..varint(2, 2);
    final padded = Uint8List.fromList([0xFF, 0xFF, ...w.data]);
    final r = ProtobufReader(Uint8List.sublistView(padded, 2));
    expect(r.next()?.field, 1);
    expect(r.varint(), 1);
    expect(r.next()?.field, 2);
  });

  test('a varint longer than 10 bytes throws', () {
    final r = ProtobufReader(Uint8List.fromList([...List.filled(10, 0x80), 0x01]));
    expect(r.varint, throwsA(const ProtobufError.truncated()));
  });
}
