import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:test/test.dart';

void main() {
  test('batches events, and a warning goes at once with what came before', () async {
    final batches = <List<LogEvent>>[];
    final sink = ForwardingLogSink(batches.add, interval: const Duration(milliseconds: 50));
    final logger = Logger(session: 'engine')..add(sink);
    logger
      ..info(LogCategory.engine, 'a')
      ..info(LogCategory.engine, 'b');
    expect(batches, isEmpty);
    logger.warn(LogCategory.engine, 'c');
    expect(batches.single.map((event) => event.msg), ['a', 'b', 'c']);
    logger.info(LogCategory.engine, 'd');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(batches, hasLength(2));
    expect(batches.last.single.msg, 'd');
  });

  test('a full batch goes without waiting', () {
    final batches = <List<LogEvent>>[];
    final logger = Logger(session: 'engine')..add(ForwardingLogSink(batches.add, batchSize: 3));
    for (var index = 0; index < 7; index++) {
      logger.info(LogCategory.engine, 'piece $index');
    }
    expect(batches.map((batch) => batch.length), [3, 3]);
  });

  test('debug events are not forwarded', () {
    final batches = <List<LogEvent>>[];
    final sink = ForwardingLogSink(batches.add);
    Logger(session: 'engine')
      ..add(sink)
      ..debug(LogCategory.engine, 'piece')
      ..warn(LogCategory.engine, 'slow');
    expect(batches.single.map((event) => event.msg), ['slow']);
    sink.flush();
    expect(batches, hasLength(1));
  });

  test('replay delivers the forwarded event as it is, without redacting it again', () {
    final target = Logger(session: 'ui');
    final memory = MemorySink();
    target.add(memory);
    // Text the Redactor would rewrite proves the replay does not run it a second time.
    ForwardingLogSink.replay([
      const LogEvent(
        t: 12.5,
        seq: 7,
        session: 'engine',
        level: LogLevel.info,
        cat: LogCategory.engine,
        msg: 'cookie SESSDATA=abc',
        f: {'url': LogString('https://upos-sz-mirrorcos.bilivideo.com/v.m4s?upsig=x')},
      ),
    ], target);
    final event = memory.events.single;
    expect(event.msg, 'cookie SESSDATA=abc');
    expect(event.f['url'], const LogString('https://upos-sz-mirrorcos.bilivideo.com/v.m4s?upsig=x'));
    expect(event.t, 12.5);
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
