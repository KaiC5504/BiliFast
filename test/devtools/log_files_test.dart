import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/devtools/log_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory dir;
  late Logger logger;
  late MemorySink seen;
  final opened = <FileLogFiles>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('log-files-');
    dir = Directory('${root.path}${Platform.pathSeparator}logs');
    logger = Logger(session: 'now');
    seen = MemorySink();
    logger.add(seen);
  });

  tearDown(() async {
    for (final files in opened) {
      await files.close();
    }
    opened.clear();
    await root.delete(recursive: true);
  });

  FileLogFiles attach({Logger? to, Directory? directory, int maxTotalBytes = FileLogFiles.maxBytes}) {
    final files = FileLogFiles.attach(directory ?? dir, logger: to ?? logger, maxTotalBytes: maxTotalBytes);
    opened.add(files);
    return files;
  }

  Future<List<LogEvent>> exported(FileLogFiles files) async {
    final path = await files.export();
    expect(path, isNotNull);
    return FileSink.readEvents(File(path!));
  }

  List<String> warnings() => [
        for (final event in seen.events)
          if (event.level == LogLevel.warn) event.msg,
      ];

  test('keeps the last 20 MB, as the Swift app did', () {
    expect(FileLogFiles.maxBytes, 20 * 1024 * 1024);
  });

  test('stays under its cap by dropping the oldest lines', () async {
    const cap = 16 * 1024;
    final files = attach(maxTotalBytes: cap);
    await files.ready;
    for (var index = 1; index <= 400; index++) {
      logger.info(LogCategory.app, 'line $index ${'x' * 200}');
    }
    final events = await exported(files);
    final sizes = [for (final file in dir.listSync().whereType<File>()) file.lengthSync()];
    expect(sizes.fold(0, (sum, each) => sum + each), lessThanOrEqualTo(cap));
    expect(events.last.msg, startsWith('line 400 '));
    expect(events.first.msg, isNot(startsWith('line 1 ')));
    final numbers = [for (final event in events) int.parse(event.msg.split(' ')[1])];
    expect(numbers, List.generate(numbers.length, (index) => numbers.first + index), reason: 'newest, unbroken');
  });

  test('what is logged while the files open is kept, first', () async {
    final files = attach();
    logger.info(LogCategory.app, 'launch');
    await files.ready;
    logger.info(LogCategory.app, 'after');
    expect([for (final event in await exported(files)) event.msg], ['launch', 'after']);
  });

  test('exports every session kept into one file beside the logs, oldest first', () async {
    final before = Logger(session: 'before');
    final earlier = attach(to: before);
    before.info(LogCategory.app, 'old one');
    before.info(LogCategory.app, 'old two');
    await earlier.export();
    await earlier.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final files = attach();
    logger.info(LogCategory.app, 'new');
    final path = await files.export();
    expect(path, '${root.path}${Platform.pathSeparator}${FileLogFiles.exportName}');
    final events = await FileSink.readEvents(File(path!));
    expect([for (final event in events) event.msg], ['old one', 'old two', 'new']);
    expect([for (final event in events) event.session], ['before', 'before', 'now']);
  });

  test('nothing logged exports nothing', () async {
    final files = attach(to: Logger(session: 'quiet'));
    expect(await files.export(), isNull);
    expect(files.exportFile.existsSync(), isFalse);
  });

  test('clear empties the log, and logging carries on', () async {
    final files = attach();
    logger.info(LogCategory.app, 'gone');
    expect(await files.export(), isNotNull);
    await files.clear();
    expect(await files.export(), isNull);
    expect(files.exportFile.existsSync(), isFalse);
    logger.info(LogCategory.app, 'kept');
    expect([for (final event in await exported(files)) event.msg], ['kept']);
  });

  test('a folder that cannot be made is logged once and nothing throws', () async {
    final blocker = File('${root.path}${Platform.pathSeparator}blocker')..writeAsStringSync('');
    final files = attach(directory: Directory('${blocker.path}${Platform.pathSeparator}logs'));
    logger.info(LogCategory.app, 'before');
    await files.ready;
    logger.info(LogCategory.app, 'after');
    expect(warnings(), ['log files unavailable']);
    expect(await files.export(), isNull);
    await files.clear();
  });

  test('a write that fails is logged once and the file carries on', () async {
    final files = attach();
    await files.ready;
    final sink = files.sink!;
    logger.info(LogCategory.app, 'one');
    await sink.flush();
    await sink.closeHandleForTesting();
    logger.info(LogCategory.app, 'lost');
    await sink.flush();
    logger.info(LogCategory.app, 'two');
    await Future<void>.delayed(Duration.zero);
    await sink.closeHandleForTesting();
    logger.info(LogCategory.app, 'lost again');
    await sink.flush();
    logger.info(LogCategory.app, 'three');
    await Future<void>.delayed(Duration.zero);
    expect(warnings(), ['log file write failed, lines dropped']);
    final messages = [for (final event in await exported(files)) event.msg];
    expect(messages, containsAllInOrder(['one', 'two', 'log file write failed, lines dropped', 'three']));
    expect(messages, isNot(contains('lost')));
    expect(messages, isNot(contains('lost again')));
  });

  group('concatenateLogFiles', () {
    File write(String name, String text) =>
        File('${root.path}${Platform.pathSeparator}$name')..writeAsStringSync(text);

    test('takes whole lines up to each file\'s length and skips files that are gone', () {
      final first = write('a.jsonl', 'a1\na2\n');
      final second = write('b.jsonl', 'b1\nb2\nb3 still being writ');
      final target = '${root.path}${Platform.pathSeparator}out.jsonl';
      final written = concatenateLogFiles([
        (first.path, first.lengthSync()),
        ('${root.path}${Platform.pathSeparator}missing.jsonl', 10),
        (second.path, 'b1\nb2\nb3 still'.length),
      ], target);
      expect(File(target).readAsStringSync(), 'a1\na2\nb1\nb2\n');
      expect(written, 'a1\na2\nb1\nb2\n'.length);
    });
  });
}
