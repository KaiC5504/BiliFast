import 'dart:typed_data';

/// C's `%.<digits>f`, which Swift's `String(format:)` uses: the exact binary value rounded half to even.
/// Dart's toStringAsFixed rounds an exact tie up (0.0625 gives 0.063, printf 0.062) and switches to
/// exponent notation from 1e21; AVPlayer accepted printf's text in the Swift builds.
String formatFixed(double value, int digits) {
  if (value.isNaN) return 'nan';
  if (value.isInfinite) return value > 0 ? 'inf' : '-inf';
  final bits = (ByteData(8)..setFloat64(0, value.abs())).getInt64(0);
  final biased = bits >> 52;
  final fraction = bits & 0xFFFFFFFFFFFFF;
  final mantissa = biased == 0 ? fraction : fraction | (1 << 52);
  final exponent = (biased == 0 ? 1 : biased) - 1075;
  final units = _scaled(mantissa, exponent, digits);
  final text = units.padLeft(digits + 1, '0');
  final whole = text.substring(0, text.length - digits);
  final sign = value.isNegative ? '-' : '';
  return digits == 0 ? '$sign$whole' : '$sign$whole.${text.substring(text.length - digits)}';
}

/// mantissa * 2^exponent * 10^digits, rounded half to even, in decimal.
String _scaled(int mantissa, int exponent, int digits) {
  // mantissa < 2^53, so with up to three digits the product stays below 2^63.
  if (exponent < 0 && exponent > -63 && digits <= 3) {
    var scaled = mantissa;
    for (var i = 0; i < digits; i++) {
      scaled *= 10;
    }
    final shift = -exponent;
    var units = scaled >> shift;
    final remainder = scaled & ((1 << shift) - 1);
    final half = 1 << (shift - 1);
    if (remainder > half || (remainder == half && units.isOdd)) units += 1;
    return '$units';
  }
  final scaled = BigInt.from(mantissa) * BigInt.from(10).pow(digits);
  if (exponent >= 0) return '${scaled << exponent}';
  final shift = -exponent;
  var units = scaled >> shift;
  final remainder = scaled - (units << shift);
  final half = BigInt.one << (shift - 1);
  if (remainder > half || (remainder == half && units.isOdd)) units += BigInt.one;
  return '$units';
}
