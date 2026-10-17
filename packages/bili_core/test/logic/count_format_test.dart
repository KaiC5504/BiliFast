import 'package:bili_core/logic.dart';
import 'package:test/test.dart';

void main() {
  test('short counts', () {
    expect(CountFormat.short(0), '0');
    expect(CountFormat.short(9131), '9131');
    expect(CountFormat.short(9999), '9999');
    expect(CountFormat.short(10000), '1万');
    expect(CountFormat.short(37000), '3.7万');
    expect(CountFormat.short(82838000), '8283.8万');
    expect(CountFormat.short(120000000), '1.2亿');
    expect(CountFormat.short(100000000), '1亿');
  });

  test('short counts truncate instead of rounding up', () {
    expect(CountFormat.short(10999), '1万');
    expect(CountFormat.short(99999999), '9999.9万');
    expect(CountFormat.short(199999999), '1.9亿');
  });
}
