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
  late MemorySink logs;
  late IosReminderHost host;

  MessageCodec<Object?> codec() => DeviceHostApi.pigeonChannelCodec;

  setUp(() {
    calls = [];
    replies = {'requestReminderPermission': true};
    failing = {};
    logs = MemorySink();
    host = IosReminderHost(logger: Logger(session: 'test')..add(logs));
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in _methods) {
      messenger.setMockMessageHandler('$_prefix$method', (message) async {
        final args = codec().decodeMessage(message) as List<Object?>? ?? const [];
        calls.add([method, ...args].join(' | '));
        if (failing.contains(method)) return codec().encodeMessage(<Object?>['denied', 'secret detail', null]);
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
    await host.schedule(at, 'title', 'body');
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
    await host.schedule(DateTime.utc(2026, 11, 10), 'title', 'body');
    await host.cancel();
    expect([for (final event in logs.events) event.f['call']?.toJson()], ['permission', 'schedule', 'cancel']);
    expect([for (final event in logs.events) event.f['error']?.toJson()], everyElement('PlatformException'));
    expect(logs.events.map((event) => event.encode()).join(), isNot(contains('secret')));
  });
}
