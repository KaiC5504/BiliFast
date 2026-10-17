import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:test/test.dart';

void main() {
  test('batches events, and a warning goes at once with what came before', () async {
    final batches = <List<LogEvent>>[];
    final sink = ForwardingLogSink(batches.add, interval: const Duration(milliseconds: 50));
    final logger = Logger(session: 'engine')..add(sink);
    logger
      ..debug(LogCategory.engine, 'a')
      ..info(LogCategory.engine, 'b');
    expect(batches, isEmpty);
    logger.warn(LogCategory.engine, 'c');
    expect(batches.single.map((event) => event.msg), ['a', 'b', 'c']);
    logger.debug(LogCategory.engine, 'd');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(batches, hasLength(2));
    expect(batches.last.single.msg, 'd');
  });

  test('a full batch goes without waiting', () {
    final batches = <List<LogEvent>>[];
    final logger = Logger(session: 'engine')..add(ForwardingLogSink(batches.add, batchSize: 3));
    for (var index = 0; index < 7; index++) {
      logger.debug(LogCategory.engine, 'piece $index');
    }
    expect(batches.map((batch) => batch.length), [3, 3]);
  });

  test("replay logs the events again under this isolate's session", () {
    final target = Logger(session: 'ui');
    final memory = MemorySink();
    target.add(memory);
    ForwardingLogSink.replay([
      const LogEvent(
        t: 1,
        seq: 41,
        session: 'engine',
        level: LogLevel.warn,
        cat: LogCategory.server,
        msg: 'listener stopped',
        f: {'port': LogInt(5000)},
      ),
    ], target);
    final event = memory.events.single;
    expect(event.session, 'ui');
    expect(event.seq, 1);
    expect(event.level, LogLevel.warn);
    expect(event.cat, LogCategory.server);
    expect(event.msg, 'listener stopped');
    expect(event.f, {'port': const LogInt(5000)});
  });
}
