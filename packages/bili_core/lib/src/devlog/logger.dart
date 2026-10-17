import 'dart:math';

import 'log_event.dart';
import 'redactor.dart';

abstract interface class LogSink {
  /// Called synchronously from [Logger.log]; must be quick.
  void receive(LogEvent event);
}

final class Logger {
  Logger({String? session}) : session = session ?? makeSessionID();

  static final Logger shared = Logger();

  final String session;
  int _seq = 0;
  final List<LogSink> _sinks = [];

  static final Random _random = Random.secure();

  /// 16 lowercase hex characters (64 random bits).
  static String makeSessionID() {
    String half() => _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return half() + half();
  }

  /// Returns the last seq handed out before the sink joined: every later event reaches it, no earlier one does.
  int add(LogSink sink) {
    _sinks.add(sink);
    return _seq;
  }

  void remove(LogSink sink) => _sinks.removeWhere((each) => identical(each, sink));

  /// [fields] values may be String, int, double, bool or [LogValue]; anything else is logged as text.
  void log(LogLevel level, LogCategory cat, String msg, [Map<String, Object> fields = const {}]) {
    final seq = ++_seq;
    if (_sinks.isEmpty) return;
    _deliver(
      LogEvent(
        t: DateTime.now().microsecondsSinceEpoch / 1e6,
        seq: seq,
        session: session,
        level: level,
        cat: cat,
        msg: Redactor.text(msg),
        f: Redactor.fields(fields),
      ),
    );
  }

  /// An event another Logger built and redacted (another isolate's), under this logger's session and sequence;
  /// its time is kept.
  void logRedacted(LogEvent event) {
    final seq = ++_seq;
    if (_sinks.isEmpty) return;
    _deliver(
      LogEvent(t: event.t, seq: seq, session: session, level: event.level, cat: event.cat, msg: event.msg, f: event.f),
    );
  }

  void _deliver(LogEvent event) {
    for (final sink in List.of(_sinks)) {
      // A logger must never take the app down, so a throwing sink only loses this event.
      try {
        sink.receive(event);
      } catch (_) {}
    }
  }

  void debug(LogCategory cat, String msg, [Map<String, Object> fields = const {}]) =>
      log(LogLevel.debug, cat, msg, fields);
  void info(LogCategory cat, String msg, [Map<String, Object> fields = const {}]) =>
      log(LogLevel.info, cat, msg, fields);
  void warn(LogCategory cat, String msg, [Map<String, Object> fields = const {}]) =>
      log(LogLevel.warn, cat, msg, fields);
  void error(LogCategory cat, String msg, [Map<String, Object> fields = const {}]) =>
      log(LogLevel.error, cat, msg, fields);
}
