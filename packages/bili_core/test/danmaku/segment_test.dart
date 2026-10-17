import 'dart:typed_data';

import 'package:bili_core/danmaku.dart';
import 'package:test/test.dart';

import 'protobuf_writer.dart';

Uint8List elemBytes(int progress, String text) =>
    (ProtobufWriter()
          ..varint(2, progress)
          ..varint(3, 1)
          ..varint(5, 0xFFFFFF)
          ..string(7, text))
        .data;

void main() {
  test('decodes an element and skips unknown fields', () {
    final w = ProtobufWriter()
      ..varint(1, 7)
      ..varint(2, 61500)
      ..varint(3, 5)
      ..varint(4, 25)
      ..varint(5, 0xFE0302)
      ..string(6, '1a2b3c4d')
      ..string(7, '前方高能')
      ..varint(9, 8)
      ..fixed32(99, 1)
      ..varint(24, 60001);
    final e = DanmakuElem.decode(w.data);
    expect(e.id, 7);
    expect(e.progressMs, 61500);
    expect(e.mode, 5);
    expect(e.color, 0xFE0302);
    expect(e.fontSize, 25);
    expect(e.midHash, '1a2b3c4d');
    expect(e.weight, 8);
    expect(e.content, '前方高能');
    expect(e.colorful, 60001);
  });

  test('reads the less common fields', () {
    final w = ProtobufWriter()
      ..varint(8, 1702204169)
      ..varint(11, 1)
      ..string(12, '9007199254740993')
      ..varint(13, 2)
      ..fixed64(77, 5)
      ..string(78, 'ignored');
    final e = DanmakuElem.decode(w.data);
    expect(e.ctime, 1702204169);
    expect(e.pool, 1);
    expect(e.idStr, '9007199254740993');
    expect(e.attr, 2);
  });

  test('a known field in the wrong wire type is skipped, not misread', () {
    final w = ProtobufWriter()
      ..string(2, 'not a number')
      ..string(7, 'still read');
    final e = DanmakuElem.decode(w.data);
    expect(e.progressMs, 0);
    expect(e.content, 'still read');
  });

  test('segment with state 1 is closed', () {
    final w = ProtobufWriter()
      ..bytes(1, elemBytes(1000, '甲'))
      ..bytes(1, elemBytes(2000, '乙'))
      ..varint(2, 1);
    final segment = DanmakuSegment.decode(w.data);
    expect(segment.closed, isTrue);
    expect(segment.elems.map((e) => e.content), ['甲', '乙']);
    expect(segment.elems.map((e) => e.progressMs), [1000, 2000]);
  });

  test('segment without state is open', () {
    final w = ProtobufWriter()
      ..bytes(1, elemBytes(1000, '甲'))
      ..bytes(3, [1, 2, 3]);
    final segment = DanmakuSegment.decode(w.data);
    expect(segment.closed, isFalse);
    expect(segment.elems.length, 1);
  });

  test('empty reply is an empty open segment', () {
    final segment = DanmakuSegment.decode(Uint8List(0));
    expect(segment.elems, isEmpty);
    expect(segment.closed, isFalse);
  });

  test('truncated input throws', () {
    final w = ProtobufWriter()
      ..varint(2, 61500)
      ..string(7, '前方高能')
      ..varint(24, 60001);
    expect(() => DanmakuElem.decode(dropLast(w.data)), throwsA(const ProtobufError.truncated()));

    final s = ProtobufWriter()..bytes(1, elemBytes(1000, '甲'));
    expect(() => DanmakuSegment.decode(dropLast(s.data)), throwsA(const ProtobufError.truncated()));
  });

  test('segment index is 1-based, six minutes', () {
    expect(DanmakuSegments.indexForMs(0), 1);
    expect(DanmakuSegments.indexForMs(359999), 1);
    expect(DanmakuSegments.indexForMs(360000), 2);
    expect(DanmakuSegments.indexForMs(-5), 1);
  });

  test('needed prefetches near the boundary only', () {
    expect(DanmakuSegments.needed(atMs: 10000, loaded: {}, durationMs: 900000), [1]);
    expect(DanmakuSegments.needed(atMs: 335000, loaded: {1}, durationMs: 900000), [2]);
    expect(DanmakuSegments.needed(atMs: 335000, loaded: {1}, durationMs: 350000), <int>[]);
    expect(DanmakuSegments.needed(atMs: 10000, loaded: {1}, durationMs: 900000), <int>[]);
    expect(DanmakuSegments.needed(atMs: 335000, loaded: {}, durationMs: 900000), [1, 2]);
    expect(DanmakuSegments.needed(atMs: 335000, loaded: {1, 2}, durationMs: 900000), <int>[]);
  });
}
