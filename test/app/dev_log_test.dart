import 'dart:async';
import 'dart:convert';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/devtools/crash_log.dart';
import 'package:bilifast/devtools/log_forwarder.dart';
import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeDiscovery implements LogServerDiscovery {
  final controller = StreamController<List<LogServerEndpoint>>.broadcast(sync: true);
  int browsing = 0;

  @override
  Stream<List<LogServerEndpoint>> browse() {
    browsing += 1;
    return controller.stream;
  }
}

void main() {
  group('LogForwarder', () {
    late Logger logger;
    late FakeDiscovery discovery;
    late List<(LogServerEndpoint, String)> posted;
    late LogForwarder forwarder;

    setUp(() {
      logger = Logger(session: 'test');
      discovery = FakeDiscovery();
      posted = [];
      forwarder = LogForwarder(
        logger: logger,
        discovery: discovery,
        poster: (endpoint) => (body) async => posted.add((endpoint, utf8.decode(body))),
        initialTarget: '',
      );
    });

    tearDown(() => forwarder.dispose());

    test('reads host:port, or a bare host on the default port', () {
      final full = LogForwarder.parseManual(' 192.168.1.5:5000 ')!;
      expect((full.host, full.port), ('192.168.1.5', 5000));
      final bare = LogForwarder.parseManual('192.168.1.5')!;
      expect(bare.port, LogServerEndpoint.defaultPort);
      expect(LogForwarder.parseManual(''), isNull);
      expect(LogForwarder.parseManual(':5000'), isNull);
      expect(LogForwarder.parseManual('host:port'), isNull);
      expect(LogForwarder.parseManual('host:70000'), isNull);
    });

    test('off by default; on, every redacted log line goes to the PC', () async {
      expect(forwarder.enabled, isFalse);
      expect(forwarder.status, '未开启');
      forwarder.setEnabled(true);
      expect(forwarder.status, '请选择电脑，或输入 IP:端口');
      forwarder.setManual('nonsense:x');
      expect(forwarder.status, '地址无效，格式为 IP:端口');

      forwarder.setManual('10.0.0.2');
      expect(forwarder.sink, isNotNull);
      expect(forwarder.status, '连接中…');
      logger.info(LogCategory.api, 'nav', {'SESSDATA': 'secret', 'status': 200});
      await forwarder.sink!.flushOnce();

      final (endpoint, body) = posted.single;
      expect((endpoint.host, endpoint.port), ('10.0.0.2', LogServerEndpoint.defaultPort));
      final events = const LineSplitter().convert(body).map(LogEvent.decode).toList();
      expect(events.map((event) => event!.msg), ['log server on', 'nav']);
      expect(body, isNot(contains('secret')));
      expect(forwarder.status, '已连接，待发送 0 条');

      forwarder.setEnabled(false);
      expect(forwarder.sink, isNull);
      expect(forwarder.status, '未开启');
    });

    test('a discovered server wins over the typed address', () {
      forwarder.setEnabled(true);
      expect(discovery.browsing, 1);
      const pc = LogServerEndpoint(name: 'BiliNative log on PC', host: '192.168.1.9', port: 47321);
      discovery.controller.add([pc]);
      expect(forwarder.discovered.single.name, pc.name);
      forwarder.setManual('10.0.0.2:1234');
      forwarder.selectService(pc);
      expect(forwarder.target?.host, '192.168.1.9');
      forwarder.selectService(null);
      expect(forwarder.target?.port, 1234);
    });

    test('LOG_SERVER starts it on', () {
      final started = LogForwarder(
        logger: logger,
        discovery: discovery,
        poster: (endpoint) => (body) async {},
        initialTarget: '127.0.0.1:47321',
      );
      expect(started.enabled, isTrue);
      expect(started.target?.host, '127.0.0.1');
      expect(started.sink, isNotNull);
      started.dispose();
    });
  });

  group('CrashLog', () {
    test('a long stack is split into parts that share one report id', () {
      final stack = List.generate(6, (index) => '#$index ${'frame' * 20}').join('\n');
      final events = CrashLog.events(source: 'flutter', error: 'boom', stack: stack, maxBytes: 256);
      expect(events.length, greaterThan(1));
      expect(events.map((event) => event['report']).toSet(), hasLength(1));
      expect(events.map((event) => event['part']), List.generate(events.length, (index) => index + 1));
      expect(events.every((event) => event['parts'] == events.length), isTrue);
      expect(events.first['error'], 'boom');
      expect(events.first['source'], 'flutter');
      expect(events[1].containsKey('error'), isFalse);
      expect(events.map((event) => event['stack']).join('\n'), stack);
    });

    test('a line longer than a part is cut inside', () {
      final parts = CrashLog.split('x' * 600, maxBytes: 256);
      expect(parts.map((part) => part.length), [256, 256, 88]);
    });

    test('Dart errors go to the log as app crash events, redacted', () {
      final logger = Logger(session: 'test');
      final sink = MemorySink();
      logger.add(sink);
      CrashLog.report(StateError('bad cookie SESSDATA=abc123'), StackTrace.fromString('#0 main'),
          source: 'platform', logger: logger);
      final event = sink.events.single;
      expect((event.cat, event.level, event.msg), (LogCategory.app, LogLevel.error, 'crash'));
      expect(event.f['source'], const LogString('platform'));
      expect(event.encode(), isNot(contains('abc123')));
      expect(event.f['stack'], const LogString('#0 main'));
    });
  });
}
