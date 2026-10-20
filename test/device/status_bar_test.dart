import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/ios/device_api.g.dart';
import 'package:bilifast/device/ios/ios_device_events.dart';
import 'package:bilifast/device/status_bar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_orientation_host.dart' show settle;

const _setStatusEvents = 'dev.flutter.pigeon.bilifast.DeviceHostApi.setStatusEvents';

Future<void> _report(List<Object?> args) {
  final done = Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    'dev.flutter.pigeon.bilifast.DeviceEventApi.onStatus',
    DeviceEventApi.pigeonChannelCodec.encodeMessage(args),
    (_) => done.complete(),
  );
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<bool> calls;
  late IosStatusBarFeed feed;
  late MemorySink logs;

  /// What the host answers setStatusEvents with: null, or a failure as (code, message).
  (String, String)? failure;

  setUp(() {
    calls = [];
    failure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_setStatusEvents, (
      message,
    ) async {
      calls.add((DeviceHostApi.pigeonChannelCodec.decodeMessage(message) as List<Object?>).single! as bool);
      if (failure case (final code, final text)?) {
        return DeviceHostApi.pigeonChannelCodec.encodeMessage(<Object?>[code, text, null]);
      }
      return DeviceHostApi.pigeonChannelCodec.encodeMessage(<Object?>[null]);
    });
    logs = MemorySink();
    feed = IosStatusBarFeed(DeviceHostApi(), IosDeviceEvents()..connect(), logger: Logger(session: 'test')..add(logs));
  });

  tearDown(() {
    feed.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_setStatusEvents, null);
    DeviceEventApi.setUp(null);
  });

  test('a full battery on Wi-Fi until the first report', () {
    expect(feed.status.value, DeviceStatus.full);
    expect(FixedStatusBarFeed().status.value, DeviceStatus.full);
  });

  test('events turn on with the first watcher and off with the last', () async {
    feed
      ..watch(true)
      ..watch(true)
      ..watch(false);
    await settle();
    expect(calls, [true]);
    feed
      ..watch(false)
      ..watch(false);
    await settle();
    expect(calls, [true, false]);
  });

  test('a host that fails the switch leaves a warning in the log, not a crash', () async {
    failure = ('error', 'battery monitoring unavailable');
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      feed.watch(true);
      await settle();
      feed.watch(false);
      await settle();
    }, (error, _) => uncaught.add(error));
    expect(calls, [true, false]);
    expect(uncaught, isEmpty);
    final warnings = logs.events.where((event) => event.msg == 'status events failed').toList();
    expect(warnings, hasLength(2));
    expect(warnings.first.level, LogLevel.warn);
  });

  test('reports become the status: the level kept to 0-1, unknown as null', () async {
    await _report([0.85, true, NativeNetwork.wifi]);
    expect(feed.status.value, const DeviceStatus(battery: 0.85, charging: true, network: StatusNetwork.wifi));
    await _report([-1.0, false, NativeNetwork.cellular]);
    expect(feed.status.value, const DeviceStatus(battery: null, charging: false, network: StatusNetwork.cellular));
    await _report([1.2, false, NativeNetwork.none]);
    expect(feed.status.value, const DeviceStatus(battery: 1, charging: false, network: StatusNetwork.none));
  });
}
