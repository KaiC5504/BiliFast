import 'dart:collection';

import 'log_event.dart';
import 'logger.dart';

final class MemorySink implements LogSink {
  /// With a [capacity], only the newest that many events are kept.
  MemorySink({this.capacity});

  final int? capacity;
  final ListQueue<LogEvent> _events = ListQueue();

  @override
  void receive(LogEvent event) {
    _events.add(event);
    final limit = capacity;
    if (limit != null && _events.length > limit) _events.removeFirst();
  }

  List<LogEvent> get events => List.unmodifiable(_events);
}
