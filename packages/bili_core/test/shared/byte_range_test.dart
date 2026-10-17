import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

void main() {
  test('parses Bilibili notation', () {
    expect(ByteRange.parse('0-1234'), ByteRange.of(0, 1234));
    expect(ByteRange.parse('0-1234')?.length, 1235);
    expect(ByteRange.parse('12-3'), isNull);
    expect(ByteRange.parse('abc'), isNull);
    expect(ByteRange.of(-1, 4), isNull);
  });

  test('header value and contains', () {
    final outer = ByteRange(10, 99);
    expect(outer.headerValue, 'bytes=10-99');
    expect(outer.contains(ByteRange(20, 30)), isTrue);
    expect(outer.contains(ByteRange(90, 100)), isFalse);
  });

  test('content range', () {
    final parsed = ContentRange.parse('bytes 100-199/1000');
    expect(parsed?.range, ByteRange(100, 199));
    expect(parsed?.total, 1000);
    expect(ContentRange.parse('bytes 0-9/*'), isNotNull);
    expect(ContentRange.parse('bytes 0-9/*')?.total, isNull);
    expect(ContentRange.parse('bytes 0-9/5'), isNull);
    expect(ContentRange.parse('items 0-9/50'), isNull);
    expect(ContentRange.parse(null), isNull);
  });

  test('split matches BTR', () {
    final mebibyte = ByteRange(0, 1048575);
    expect(mebibyte.split(concurrency: 4, minChunk: 65536).map((r) => r.length), [262144, 262144, 262144, 262144]);
    expect(ByteRange(0, 99).split(concurrency: 8, minChunk: 65536).length, 1);
    final odd = ByteRange(10, 100010);
    final parts = odd.split(concurrency: 3, minChunk: 32768);
    expect(parts.map((r) => r.length), [33334, 33334, 33333]);
    expect(parts.first.start, 10);
    expect(parts.last.end, 100010);
  });
}
