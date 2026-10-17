import 'dart:convert';

enum LogLevel { debug, info, warn, error }

enum LogCategory { app, api, engine, server, player, ui }

/// A field value: string, int, double or bool, like Swift's `LogValue`.
sealed class LogValue {
  const LogValue();

  /// Wraps a plain Dart value. Anything that is not a string, int, double, bool or LogValue is logged as text.
  factory LogValue.of(Object value) => switch (value) {
    LogValue() => value,
    String() => LogString(value),
    int() => LogInt(value),
    double() => LogDouble(value),
    bool() => LogBool(value),
    Enum() => LogString(value.name),
    _ => LogString(value.toString()),
  };

  static Map<String, LogValue> fields(Map<String, Object> fields) =>
      fields.map((key, value) => MapEntry(key, LogValue.of(value)));

  Object toJson();

  /// Decodes a JSON scalar; null when it is not one.
  static LogValue? fromJson(Object? json) => switch (json) {
    bool() => LogBool(json),
    int() => LogInt(json),
    double() => LogDouble(json),
    String() => LogString(json),
    _ => null,
  };
}

final class LogString extends LogValue {
  const LogString(this.value);

  final String value;

  @override
  Object toJson() => value;

  @override
  bool operator ==(Object other) => other is LogString && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'LogString($value)';
}

final class LogInt extends LogValue {
  const LogInt(this.value);

  final int value;

  @override
  Object toJson() => value;

  @override
  bool operator ==(Object other) => other is LogInt && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'LogInt($value)';
}

final class LogDouble extends LogValue {
  const LogDouble(this.value);

  final double value;

  // jsonEncode throws on non-finite numbers, which would drop the whole event.
  @override
  Object toJson() => value.isFinite ? value : (value.isNaN ? 'nan' : (value < 0 ? '-inf' : 'inf'));

  @override
  bool operator ==(Object other) => other is LogDouble && (other.value == value || (other.value.isNaN && value.isNaN));

  @override
  int get hashCode => value.isNaN ? double.nan.hashCode : value.hashCode;

  @override
  String toString() => 'LogDouble($value)';
}

final class LogBool extends LogValue {
  const LogBool(this.value);

  final bool value;

  @override
  Object toJson() => value;

  @override
  bool operator ==(Object other) => other is LogBool && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'LogBool($value)';
}

final class LogEvent {
  const LogEvent({
    required this.t,
    required this.seq,
    required this.session,
    required this.level,
    required this.cat,
    required this.msg,
    this.f = const {},
  });

  /// Unix time in seconds.
  final double t;
  final int seq;
  final String session;
  final LogLevel level;
  final LogCategory cat;
  final String msg;
  final Map<String, LogValue> f;

  Map<String, Object> toJson() => {
    't': t,
    'seq': seq,
    'session': session,
    'level': level.name,
    'cat': cat.name,
    'msg': msg,
    'f': f.map((key, value) => MapEntry(key, value.toJson())),
  };

  /// One JSON line without the trailing newline. Throws if the event cannot be encoded (a non-finite `t`).
  String encode() => jsonEncode(toJson());

  /// Throws [FormatException] when a field is missing or has the wrong type.
  factory LogEvent.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw const FormatException('log event is not an object');
    final t = json['t'];
    final seq = json['seq'];
    final session = json['session'];
    final level = LogLevel.values.asNameMap()[json['level']];
    final cat = LogCategory.values.asNameMap()[json['cat']];
    final msg = json['msg'];
    final rawFields = json['f'];
    if (t is! num || seq is! int || session is! String || level == null || cat == null || msg is! String) {
      throw const FormatException('log event has a missing or mistyped field');
    }
    final fields = <String, LogValue>{};
    if (rawFields is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in rawFields.entries) {
        fields[key] = LogValue.fromJson(value) ?? (throw FormatException('field $key is not a scalar'));
      }
    } else if (rawFields != null) {
      throw const FormatException('f is not an object');
    }
    return LogEvent(t: t.toDouble(), seq: seq, session: session, level: level, cat: cat, msg: msg, f: fields);
  }

  /// Null for a line that is not a valid event.
  static LogEvent? decode(String line) {
    try {
      return LogEvent.fromJson(jsonDecode(line));
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LogEvent &&
      other.t == t &&
      other.seq == seq &&
      other.session == session &&
      other.level == level &&
      other.cat == cat &&
      other.msg == msg &&
      _sameFields(other.f, f);

  @override
  int get hashCode => Object.hash(
    t,
    seq,
    session,
    level,
    cat,
    msg,
    Object.hashAllUnordered(f.entries.map((e) => Object.hash(e.key, e.value))),
  );

  @override
  String toString() => 'LogEvent(t: $t, seq: $seq, session: $session, ${level.name}, ${cat.name}, $msg, $f)';

  static bool _sameFields(Map<String, LogValue> a, Map<String, LogValue> b) =>
      a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);
}
