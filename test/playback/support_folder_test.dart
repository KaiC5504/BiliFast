import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/playback/playback_setup.dart';
import 'package:flutter_test/flutter_test.dart';

class _Events implements LogSink {
  final events = <LogEvent>[];

  @override
  void receive(LogEvent event) => events.add(event);

  String get text => events.map((event) => event.encode()).join('\n');

  LogEvent named(String msg) => events.singleWhere((event) => event.msg == msg);
}

void main() {
  late Directory looked;
  late _Events events;
  late Logger logger;
  const home = '/var/mobile/Containers/Data/Application/HOME-ID';

  setUp(() async {
    looked = await Directory.systemTemp.createTemp('support_folder_test');
    addTearDown(() => looked.delete(recursive: true));
    events = _Events();
    logger = Logger(session: 'test')..add(events);
  });

  test('the folder iOS names wins over HOME', () async {
    await resolveSupportFolder(logger: logger, isIOS: true, lookup: () async => looked, home: home);
    expect(supportFilePath('app_device.json', isIOS: true, home: home), '${looked.path}/app_device.json');
    expect(events.named('support folder').f['resolved'], const LogBool(true));
    expect(events.named('support folder').f['sameAsHome'], const LogBool(false));
  });

  test('a failed lookup falls back to HOME and logs only the error type', () async {
    await resolveSupportFolder(logger: logger, isIOS: true, lookup: () async => looked, home: home);
    await resolveSupportFolder(
      logger: logger,
      isIOS: true,
      lookup: () async => throw FileSystemException('no container', looked.path),
      home: home,
    );
    expect(
      supportFilePath('player_prefs.json', isIOS: true, home: home),
      '$home/Library/Application Support/player_prefs.json',
      reason: "the last launch's folder isn't kept",
    );
    expect(events.named('support folder lookup failed').f, {'error': const LogString('FileSystemException')});
    expect(events.text, isNot(contains('no container')));
    expect(events.events.last.f['resolved'], const LogBool(false));
  });

  test('the log names the files it found, never the folder', () async {
    for (final name in ['player_prefs.json', 'app_device.json', 'unrelated.txt']) {
      await File('${looked.path}/$name').writeAsString('{}');
    }
    await resolveSupportFolder(logger: logger, isIOS: true, lookup: () async => looked, home: home);
    final logged = events.named('support folder');
    expect(logged.f['exists'], const LogBool(true));
    expect(logged.f['files'], const LogString('player_prefs.json,app_device.json'));
    expect(events.text, isNot(contains(looked.path.replaceAll(r'\', r'\\'))));
    expect(events.text, isNot(contains('support_folder_test')));
  });

  test('elsewhere it asks nothing', () async {
    var asked = false;
    await resolveSupportFolder(
      logger: logger,
      isIOS: false,
      lookup: () async {
        asked = true;
        return looked;
      },
    );
    expect(asked, isFalse);
    expect(events.events, isEmpty);
  });
}
