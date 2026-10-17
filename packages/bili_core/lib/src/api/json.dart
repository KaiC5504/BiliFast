/// A field missing or of the wrong type, the counterpart of Swift's DecodingError.
final class DecodeError implements Exception {
  const DecodeError(this.message);

  final String message;

  @override
  String toString() => 'DecodeError: $message';
}

/// The decoding rules of Swift's keyed containers: a key that is absent or null reads as absent, a value of the
/// wrong type throws. Bilibili spells many fields two ways (baseUrl/base_url); the first present one wins.
extension type const JsonObject(Map<String, Object?> map) {
  static JsonObject from(Object? value, [String what = 'object']) {
    if (value is Map<String, Object?>) return JsonObject(value);
    throw DecodeError('expected $what, got ${value.runtimeType}');
  }

  T? _first<T>(List<String> keys, T? Function(Object value) convert, String type) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final converted = convert(value);
      if (converted == null) throw DecodeError('$key: expected $type, got ${value.runtimeType}');
      return converted;
    }
    return null;
  }

  int? integer(String key, [String? alt]) => _first(_keys(key, alt), asInt, 'integer');
  double? number(String key, [String? alt]) => _first(_keys(key, alt), asDouble, 'number');
  String? string(String key, [String? alt]) => _first(_keys(key, alt), (v) => v is String ? v : null, 'string');
  bool? boolean(String key, [String? alt]) => _first(_keys(key, alt), (v) => v is bool ? v : null, 'bool');
  List<Object?>? list(String key, [String? alt]) =>
      _first(_keys(key, alt), (v) => v is List ? List<Object?>.of(v) : null, 'array');

  /// The first key holding an object; never throws.
  JsonObject? nested(String key) {
    final value = map[key];
    return value is Map<String, Object?> ? JsonObject(value) : null;
  }

  T required<T extends Object>(T? value, String key) => value ?? (throw DecodeError('missing $key'));

  /// Counts are numbers, but a hidden one arrives as a string such as "--".
  int count(String key, [String? alt]) {
    for (final name in _keys(key, alt)) {
      final value = map[name];
      final number = asInt(value);
      if (number != null) return number;
      if (value is String) return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  /// A string, or null when absent or of another type.
  String? text(String key) {
    final value = map[key];
    return value is String ? value : null;
  }

  /// Some endpoints answer a flag as 0/1, others as true/false.
  bool flag(String key, [String? alt]) {
    for (final name in _keys(key, alt)) {
      final value = map[name];
      if (value is bool) return value;
      final number = asInt(value);
      if (number != null) return number != 0;
    }
    return false;
  }

  /// An array where an undecodable element is dropped instead of failing the whole array.
  /// The array itself must be an array when present.
  List<T> lossyList<T>(String key, T Function(Object? json) decode) => lossy(list(key) ?? const [], decode);

  /// Like [lossyList], but a value of the wrong type also reads as empty.
  List<T> lenientList<T>(String key, T Function(Object? json) decode) {
    final value = map[key];
    return value is List ? lossy(value, decode) : <T>[];
  }

  /// A malformed value costs that entry, not the dictionary.
  Map<String, T> table<T>(String key, T Function(Object? json) decode) {
    final value = map[key];
    if (value is! Map<String, Object?>) return {};
    final result = <String, T>{};
    for (final entry in value.entries) {
      if (_attemptElement(() => decode(entry.value)) case (final T decoded,)) result[entry.key] = decoded;
    }
    return result;
  }

  static List<String> _keys(String key, String? alt) => alt == null ? [key] : [key, alt];
}

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.truncateToDouble() && value.isFinite) return value.toInt();
  return null;
}

double? asDouble(Object? value) => value is num ? value.toDouble() : null;

/// Swift's `try?` over a decode: a DecodeError reads as null.
T? attempt<T extends Object>(T? Function() decode) {
  try {
    return decode();
  } on DecodeError {
    return null;
  }
}

List<T> lossy<T>(List<Object?> values, T Function(Object? json) decode) => [
      for (final value in values)
        if (_attemptElement(() => decode(value)) case (final T decoded,)) decoded,
    ];

/// A record so that a decoder whose result type is nullable still tells "null" from "failed".
(T,)? _attemptElement<T>(T Function() decode) {
  try {
    return (decode(),);
  } on DecodeError {
    return null;
  }
}

/// A strict array: one bad element fails it.
List<T> strictList<T>(List<Object?>? values, T Function(Object? json) decode) =>
    [for (final value in values ?? const <Object?>[]) decode(value)];

String asString(Object? value, String what) => value is String ? value : throw DecodeError('$what: expected string');

int asRequiredInt(Object? value, String what) => asInt(value) ?? (throw DecodeError('$what: expected integer'));

bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
