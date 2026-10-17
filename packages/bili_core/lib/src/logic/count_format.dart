abstract final class CountFormat {
  /// Bilibili's compact counts. Truncates rather than rounds so 99 999 999 never reads as 10000万.
  static String short(int n) {
    if (n < 10000) return '$n';
    if (n < 100000000) return _scaled(n ~/ 1000, '万');
    return _scaled(n ~/ 10000000, '亿');
  }

  static String _scaled(int tenths, String unit) {
    final whole = tenths ~/ 10, fraction = tenths.remainder(10);
    return fraction == 0 ? '$whole$unit' : '$whole.$fraction$unit';
  }
}
