import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = EventChannel('bilifast/log_servers');

  test('the native list becomes endpoints with the logs URL', () async {
    var cancelled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success(<Object?>[]);
          events.success(<Object?>[
            {'name': 'KaiC-PC', 'host': '192.168.1.20', 'port': 47321},
            {'name': 'broken', 'host': '192.168.1.21'},
          ]);
        },
        onCancel: (arguments) => cancelled = true,
      ),
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(channel, null));

    final lists = <List<LogServerEndpoint>>[];
    final subscription = const BonjourLogServerDiscovery().browse().listen(lists.add);
    await pumpEventQueue();

    expect(lists, hasLength(2));
    expect(lists.first, isEmpty);
    final server = lists.last.single;
    expect(server.name, 'KaiC-PC');
    expect(server.logsUrl, Uri.parse('http://192.168.1.20:47321/logs'));

    await subscription.cancel();
    await pumpEventQueue();
    expect(cancelled, isTrue);
  });

  test('anything that is not a list of servers is no servers', () {
    expect(BonjourLogServerDiscovery.parse(null), isEmpty);
    expect(BonjourLogServerDiscovery.parse('nope'), isEmpty);
    expect(BonjourLogServerDiscovery.parse(<Object?>[42]), isEmpty);
  });

  test('other platforms find nothing', () async {
    expect(await const NoLogServerDiscovery().browse().toList(), isEmpty);
  });
}
