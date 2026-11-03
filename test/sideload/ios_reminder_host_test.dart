import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/ios/device_api.g.dart';
import 'package:bilifast/sideload/ios_reminder_host.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _prefix = 'dev.flutter.pigeon.bilifast.DeviceHostApi.';
const _methods = ['requestReminderPermission', 'scheduleReminder', 'cancelReminder'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;
  late Map<String, Object?> replies;
  late Set<String> failing;
  late (String, String) failure;
  late MemorySink logs;
  late IosReminderHost host;

  MessageCodec<Object?> codec() => DeviceHostApi.pigeonChannelCodec;

  setUp(() {
    calls = [];
    replies = {'requestReminderPermission': true};
    failing = {};
    failure = ('denied', 'secret detail');
    logs = MemorySink();
    host = IosReminderHost(logger: Logger(session: 'test')..add(logs));
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in _methods) {
      messenger.setMockMessageHandler('$_prefix$method', (message) async {
        final args = codec().decodeMessage(message) as List<Object?>? ?? const [];
        calls.add([method, ...args].join(' | '));
        if (failing.contains(method)) return codec().encodeMessage(<Object?>[failure.$1, failure.$2, null]);
        return codec().encodeMessage(<Object?>[replies[method]]);
      });
    }
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in _methods) {
      messenger.setMockMessageHandler('$_prefix$method', null);
    }
  });

  test("passes the permission, the reminder's moment in epoch ms with its texts, and the cancel", () async {
    expect(await host.requestPermission(), isTrue);
    replies['requestReminderPermission'] = false;
    expect(await host.requestPermission(), isFalse);
    final at = DateTime.utc(2026, 11, 10, 8, 30);
    expect(await host.schedule(at, 'title', 'body'), isTrue);
    await host.cancel();
    expect(calls, [
      'requestReminderPermission',
      'requestReminderPermission',
      'scheduleReminder | ${at.millisecondsSinceEpoch} | title | body',
      'cancelReminder',
    ]);
    expect(logs.events, isEmpty);
  });

  test("the host's errors stop here: a refusal for the permission, logged by type only", () async {
    failing.addAll(_methods);
    expect(await host.requestPermission(), isFalse);
    expect(await host.schedule(DateTime.utc(2026, 11, 10), 'title', 'body'), isTrue, reason: 'not a refusal');
    await host.cancel();
    expect([for (final event in logs.events) event.f['call']?.toJson()], ['permission', 'schedule', 'cancel']);
    expect([for (final event in logs.events) event.f['error']?.toJson()], everyElement('PlatformException'));
    expect([for (final event in logs.events) event.f['code']], everyElement(isNull));
    expect(logs.events.map((event) => event.encode()).join(), isNot(contains('secret')));
  });

  test("a schedule refused as UNErrorDomain 1 is iOS no longer allowing notifications, logged by its code", () async {
    failing.add('scheduleReminder');
    failure = ('notifications', 'UNErrorDomain 1');
    expect(await host.schedule(DateTime.utc(2026, 11, 10), 'title', 'body'), isFalse);
    final line = logs.events.single;
    expect(line.msg, 'sideload reminder failed');
    expect(line.f.map((key, value) => MapEntry(key, value.toJson())), {
      'call': 'schedule',
      'error': 'PlatformException',
      'code': 'notifications',
      'message': 'UNErrorDomain 1',
    });

    failure = ('notifications', 'UNErrorDomain 3');
    expect(await host.schedule(DateTime.utc(2026, 11, 10), 'title', 'body'), isTrue, reason: 'another error passes');
    expect(logs.events.last.f['message']?.toJson(), 'UNErrorDomain 3');

    failure = ('channel-error', 'UNErrorDomain 1');
    expect(await host.schedule(DateTime.utc(2026, 11, 10), 'title', 'body'), isTrue, reason: 'only our own error');
    expect(logs.events.last.f['message'], isNull);
  });
}
