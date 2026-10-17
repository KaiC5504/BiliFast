import 'log_event.dart';
import 'logger.dart';

final class MemorySink implements LogSink {
  final List<LogEvent> _events = [];

  @override
  void receive(LogEvent event) => _events.add(event);

  List<LogEvent> get events => List.unmodifiable(_events);
}
