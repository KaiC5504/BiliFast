import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

void main() {
  test('delivers to sinks with increasing seq', () {
    final logger = Logger(session: 's1');
    final sink = MemorySink();
    logger.add(sink);
    logger.info(LogCategory.engine, 'piece', {'bytes': 65536, 'node': 'a'});
    logger.warn(LogCategory.api, 'Cookie: SESSDATA=x');
    expect(sink.events.map((e) => e.seq), [1, 2]);
    expect(sink.events[0].f['bytes'], const LogInt(65536));
    expect(sink.events[0].session, 's1');
    expect(sink.events[1].level, LogLevel.warn);
    expect(sink.events[1].msg, 'Cookie: SESSDATA=[redacted]');
    logger.remove(sink);
    logger.info(LogCategory.app, 'after removal');
    expect(sink.events.length, 2);
  });

  test('add returns the last seq handed out before the sink', () {
    final logger = Logger(session: 'cut');
    logger.info(LogCategory.app, 'one');
    logger.info(LogCategory.app, 'two');
    final sink = MemorySink();
    final cut = logger.add(sink);
    logger.info(LogCategory.app, 'three');
    expect(cut, 2);
    expect(sink.events.map((e) => e.seq), [3]);
  });

  test('non-finite doubles encode as strings', () {
    const event = LogEvent(
      t: 0,
      seq: 1,
      session: 's',
      level: LogLevel.info,
      cat: LogCategory.engine,
      msg: 'm',
      f: {
        'a': LogDouble(double.infinity),
        'b': LogDouble(double.negativeInfinity),
        'c': LogDouble(double.nan),
        'd': LogDouble(2.5),
      },
    );
    final decoded = LogEvent.decode(event.encode())!;
    expect(decoded.f['a'], const LogString('inf'));
    expect(decoded.f['b'], const LogString('-inf'));
    expect(decoded.f['c'], const LogString('nan'));
    expect(decoded.f['d'], const LogDouble(2.5));
  });

  test('event round trip', () {
    const event = LogEvent(
      t: 1.5,
      seq: 1,
      session: 's',
      level: LogLevel.info,
      cat: LogCategory.app,
      msg: 'm',
      f: {'a': LogString('x'), 'b': LogInt(3), 'c': LogDouble(1.5), 'd': LogBool(true)},
    );
    expect(LogEvent.decode(event.encode()), event);
  });

  test('session IDs are 16 hex characters', () {
    expect(Logger.makeSessionID(), matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(Logger(session: null).session, hasLength(16));
  });
}
