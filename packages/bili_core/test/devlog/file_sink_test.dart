import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory dir;
  final sinks = <FileSink>[];

  // The export lands in the log directory's parent, so each test gets its own parent too.
  setUp(() async {
    root = await Directory.systemTemp.createTemp('devlog-');
    dir = await Directory('${root.path}${Platform.pathSeparator}logs').create();
  });

  tearDown(() async {
    for (final sink in sinks) {
      await sink.close();
    }
    sinks.clear();
    await root.delete(recursive: true);
  });

  Future<FileSink> open(String session, {int? maxTotalBytes}) async {
    final sink = maxTotalBytes == null
        ? await FileSink.open(directory: dir, session: session)
        : await FileSink.open(directory: dir, session: session, maxTotalBytes: maxTotalBytes);
    sinks.add(sink);
    return sink;
  }

  File child(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  Future<List<String>> messages(File file) async => [for (final e in await FileSink.readEvents(file)) e.msg];

  test('writes JSON lines and reads them back', () async {
    final sink = await open('aaa');
    final logger = Logger(session: 'aaa');
    logger.add(sink);
    logger.info(LogCategory.app, 'one');
    logger.info(LogCategory.app, 'two');
    await sink.flush();
    expect(await messages(sink.file), ['one', 'two']);
  });

  test('non-finite field does not drop the event', () async {
    final sink = await open('nf');
    final logger = Logger(session: 'nf');
    logger.add(sink);
    logger.info(LogCategory.engine, 'speed', {'mbps': double.infinity});
    await sink.flush();
    final events = await FileSink.readEvents(sink.file);
    expect(events.map((e) => e.msg), ['speed']);
    expect(events.first.f['mbps'], const LogString('inf'));
  });

  test('failed write drops the line and recovers', () async {
    final sink = await open('w');
    final logger = Logger(session: 'w');
    logger.add(sink);
    logger.info(LogCategory.app, 'before');
    await sink.flush();
    await sink.closeHandleForTesting();
    logger.info(LogCategory.app, 'lost');
    await sink.flush();
    expect(sink.droppedLines, 1);
    logger.info(LogCategory.app, 'after');
    await sink.flush();
    expect(await messages(sink.file), ['before', 'after']);
  });

  test('live session is rolled and stays under the cap', () async {
    const cap = 4000;
    final sink = await open('big', maxTotalBytes: cap);
    final logger = Logger(session: 'big');
    logger.add(sink);
    for (var index = 0; index < 300; index++) {
      logger.info(LogCategory.engine, 'event-$index', {'pad': 'xxxxxxxxxxxxxxxxxxxxxxxx'});
    }
    await sink.flush();

    final files = await sink.sessionFiles();
    expect(files.length, greaterThan(1));
    var total = 0;
    for (final file in files) {
      total += await file.length();
    }
    expect(total, lessThanOrEqualTo(cap));

    final events = [for (final file in files) ...await FileSink.readEvents(file)];
    expect(events.last.msg, 'event-299');
    expect(events.first.msg, isNot('event-0'));
    expect(events.map((e) => e.seq), [for (var seq = events.first.seq; seq <= events.last.seq; seq++) seq]);

    final ack = await AckStore.load(child('ack.json'));
    expect(await ReplayPlanner.unsent(files: files, currentSession: 'big', ack: ack), isEmpty);
    expect(await ReplayPlanner.unsent(files: files, currentSession: 'other', ack: ack), isNotEmpty);
  });

  test('prunes the oldest session files', () async {
    final filler = List.filled(600, 0x41);
    for (final (name, year) in [('old', 2020), ('mid', 2021)]) {
      final file = child('$name.jsonl');
      await file.writeAsBytes(filler);
      await file.setLastModified(DateTime(year));
    }
    await open('new', maxTotalBytes: 1000);
    expect(child('old.jsonl').existsSync(), isFalse);
    expect(child('mid.jsonl').existsSync(), isTrue);
    expect(child('new.jsonl').existsSync(), isTrue);
  });

  test('removeAllFiles deletes every session and keeps logging', () async {
    await child('older.jsonl').writeAsString('{}\n');
    final sink = await open('rm', maxTotalBytes: 4000);
    final logger = Logger(session: 'rm');
    logger.add(sink);
    for (var index = 0; index < 100; index++) {
      logger.info(LogCategory.app, 'before-$index', {'pad': 'xxxxxxxxxxxxxxxxxxxxxxxx'});
    }
    final exported = await sink.exportFile();
    expect((await sink.sessionFiles()).length, greaterThan(2));

    await sink.removeAllFiles();
    expect([for (final file in await sink.sessionFiles()) file.uri.pathSegments.last], ['rm.jsonl']);
    expect(await FileSink.readEvents(sink.file), isEmpty);
    expect(exported.existsSync(), isFalse);

    logger.info(LogCategory.app, 'after');
    await sink.flush();
    expect(await messages(sink.file), ['after']);
  });

  test('replay skips acknowledged events and the current session', () async {
    final oldSink = await open('s1');
    final oldLogger = Logger(session: 's1');
    oldLogger.add(oldSink);
    oldLogger.info(LogCategory.app, 'a');
    oldLogger.info(LogCategory.app, 'b');
    oldLogger.info(LogCategory.app, 'c');
    await oldSink.flush();

    final currentSink = await open('s2');
    final currentLogger = Logger(session: 's2');
    currentLogger.add(currentSink);
    currentLogger.info(LogCategory.app, 'live');
    await currentSink.flush();

    final ack = await AckStore.load(child('ack.json'));
    await ack.record('s1', 2);
    final unsent = await ReplayPlanner.unsent(files: await currentSink.sessionFiles(), currentSession: 's2', ack: ack);
    expect(unsent.map((e) => e.msg), ['c']);
    expect((await AckStore.load(child('ack.json'))).lastSeq('s1'), 2);
  });

  test('replay includes the current session between ack and cut', () async {
    final sink = await open('now');
    final logger = Logger(session: 'now');
    logger.add(sink);
    for (var index = 1; index <= 5; index++) {
      logger.info(LogCategory.app, 'e$index');
    }
    await sink.flush();
    final ack = await AckStore.load(child('ack.json'));
    final unsent = await ReplayPlanner.unsent(
      files: await sink.sessionFiles(),
      currentSession: 'now',
      ack: ack,
      current: (after: 1, through: 4),
    );
    expect(unsent.map((e) => e.msg), ['e2', 'e3', 'e4']);
  });

  test('replay limit keeps the newest events', () async {
    for (final (session, year) in [('a', 2020), ('b', 2021)]) {
      final sink = await open(session);
      final logger = Logger(session: session);
      logger.add(sink);
      for (var index = 1; index <= 3; index++) {
        logger.info(LogCategory.app, '$session$index');
      }
      await sink.flush();
      await sink.file.setLastModified(DateTime(year));
    }
    final probe = await open('c');
    final ack = await AckStore.load(child('ack.json'));
    final unsent =
        await ReplayPlanner.unsent(files: await probe.sessionFiles(), currentSession: 'c', ack: ack, limit: 4);
    expect(unsent.map((e) => e.msg), ['a3', 'b1', 'b2', 'b3']);
  });
}
