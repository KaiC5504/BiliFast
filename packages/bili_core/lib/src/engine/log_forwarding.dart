import 'dart:async';

import '../devlog/log_event.dart';
import '../devlog/logger.dart';

/// Carries the engine isolate's log events to the UI isolate, whose Logger.shared owns the file and network
/// sinks. Batched, because the engine logs every piece; a warning or an error goes at once. Debug events stay
/// behind unless [forwardDebug]: copying them across the port for every piece costs more than they are worth,
/// except to a developer timing the engine from the phone's log.
final class ForwardingLogSink implements LogSink {
  ForwardingLogSink(
    this._send, {
    this.interval = const Duration(milliseconds: 100),
    this.batchSize = 200,
    this.forwardDebug = false,
  });

  final void Function(List<LogEvent> events) _send;
  final Duration interval;
  final int batchSize;
  final bool forwardDebug;
  var _pending = <LogEvent>[];
  Timer? _timer;

  @override
  void receive(LogEvent event) {
    if (event.level == LogLevel.debug && !forwardDebug) return;
    _pending.add(event);
    if (event.level.index >= LogLevel.warn.index || _pending.length >= batchSize) {
      flush();
    } else {
      _timer ??= Timer(interval, flush);
    }
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final events = _pending;
    _pending = [];
    _send(events);
  }

  /// Logs forwarded events again in this isolate, so they take its session and sequence numbers. The engine's
  /// Logger redacted them already.
  static void replay(List<LogEvent> events, [Logger? logger]) {
    final target = logger ?? Logger.shared;
    for (final event in events) {
      target.logRedacted(event);
    }
  }
}
