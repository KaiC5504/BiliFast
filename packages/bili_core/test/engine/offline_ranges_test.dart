import 'dart:io';

import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/offline_download.dart';
import 'package:bili_core/src/engine/offline_ranges.dart';
import 'package:test/test.dart';

void main() {
  group('missingRanges', () {
    test('nothing done is the whole file', () {
      expect(missingRanges(const [], 100), [ByteRange(0, 99)]);
    });

    test('everything done leaves nothing', () {
      expect(missingRanges([ByteRange(0, 99)], 100), isEmpty);
    });

    test('the holes between, before and after what is done', () {
      expect(missingRanges([ByteRange(10, 19), ByteRange(40, 49)], 100), [
        ByteRange(0, 9),
        ByteRange(20, 39),
        ByteRange(50, 99),
      ]);
    });

    test('unsorted, overlapping and touching ranges are merged first', () {
      expect(missingRanges([ByteRange(50, 59), ByteRange(0, 9), ByteRange(5, 20), ByteRange(21, 30)], 70), [
        ByteRange(31, 49),
        ByteRange(60, 69),
      ]);
    });

    test('ranges past the total are ignored', () {
      expect(missingRanges([ByteRange(0, 9), ByteRange(95, 150), ByteRange(200, 300)], 100), [ByteRange(10, 94)]);
    });

    test('an unknown total has no gaps', () {
      expect(missingRanges([ByteRange(0, 9)], 0), isEmpty);
    });
  });

  group('RangesRecord', () {
    test('parses the format the host writes, numbers as doubles included', () {
      final record = RangesRecord.parse('{"total": 100, "done": [[50, 59], [0, 9], [10, 1.9e1]]}');
      expect(record?.total, 100);
      expect(record?.done, [ByteRange(0, 19), ByteRange(50, 59)]);
    });

    test('anything else is no record', () {
      for (final text in [
        '',
        'not json',
        '[]',
        '{"total": -1, "done": []}',
        '{"total": 10, "done": [[5, 2]]}',
        '{"total": 10, "done": [[0, 10]]}',
        '{"total": 10, "done": [[0]]}',
        '{"total": "10", "done": []}',
      ]) {
        expect(RangesRecord.parse(text), isNull, reason: text);
      }
    });

    test('writes through a temporary file and reads back', () async {
      final dir = await Directory.systemTemp.createTemp('ranges');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}v.m4s.ranges';
      await RangesRecord(100, [ByteRange(0, 9)]).write(path);
      await RangesRecord(100, [ByteRange(0, 19), ByteRange(30, 39)]).write(path);
      final record = await RangesRecord.read(path);
      expect(record?.done, [ByteRange(0, 19), ByteRange(30, 39)]);
      expect(File('$path.tmp').existsSync(), isFalse);
      expect(await RangesRecord.read('$path.missing'), isNull);
    });
  });
}
