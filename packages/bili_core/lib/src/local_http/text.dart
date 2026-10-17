/// Foundation's `trimmingCharacters(in: .whitespaces)`: tab and the Unicode space separators, not line breaks
/// (Dart's `trim` also strips those).
String trimSpaces(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && _isSpace(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
    end--;
  }
  return text.substring(start, end);
}

bool _isSpace(int unit) =>
    unit == 0x09 ||
    unit == 0x20 ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200A) ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000;

final _decimal = RegExp(r'^[+-]?[0-9]+$');

/// Swift's `Int64(String)`: an optional sign and ASCII digits only. `int.tryParse` alone would also take
/// surrounding whitespace and a `0x` prefix.
int? parseInt64(String text) => _decimal.hasMatch(text) ? int.tryParse(text, radix: 10) : null;
