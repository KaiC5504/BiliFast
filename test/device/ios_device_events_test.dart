import 'dart:async';
import 'dart:math';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/ios/device_api.g.dart';
import 'package:bilifast/device/ios/ios_device_events.dart';
import 'package:bilifast/device/ios/ios_orientation_host.dart';
import 'package:bilifast/device/orientation_host.dart';
import 'package:bilifast/device/turn_style.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_orientation_host.dart' show settle;

const _hostPrefix = 'dev.flutter.pigeon.bilifast.DeviceHostApi.';
const _eventPrefix = 'dev.flutter.pigeon.bilifast.DeviceEventApi.';
const _hostMethods = ['setTurnTakeover', 'turnDrawn'];

MessageCodec<Object?> get _codec => DeviceEventApi.pigeonChannelCodec;

/// A DeviceEventApi call from DeviceChannel.swift, through the codec.
Future<void> _send(String event, List<Object?> args) {
  final done = Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    '$_eventPrefix$event',
    _codec.encodeMessage(args),
    (_) => done.complete(),
  );
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySink logs;
  late IosDeviceEvents events;
  late List<String> hostCalls;

  setUp(() {
    logs = MemorySink();
    events = IosDeviceEvents(logger: Logger(session: 'test')..add(logs))..connect();
    hostCalls = [];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in _hostMethods) {
      messenger.setMockMessageHandler('$_hostPrefix$method', (message) async {
        final args = DeviceHostApi.pigeonChannelCodec.decodeMessage(message) as List<Object?>;
        hostCalls.add([method, for (final arg in args) arg is Enum ? arg.name : '$arg'].join(' '));
        return DeviceHostApi.pigeonChannelCodec.encodeMessage(<Object?>[null]);
      });
    }
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in _hostMethods) {
      messenger.setMockMessageHandler('$_hostPrefix$method', null);
    }
    DeviceEventApi.setUp(null);
  });

  group('IosDeviceEvents', () {
    test('onTurn becomes a TurnStart with the id, the angle and the duration', () async {
      final turns = <TurnStart>[];
      final subscription = events.turns.listen(turns.add);
      await _send('onTurn', [7, -pi / 2, 0.3]);
      await _send('onTurn', [8, pi / 2, 0.4166667]);
      await settle();
      expect(turns, [
        (id: 7, angle: -pi / 2, duration: const Duration(milliseconds: 300)),
        (id: 8, angle: pi / 2, duration: const Duration(microseconds: 416667)),
      ]);
      await subscription.cancel();
    });

    test('onTurnPictureGone reaches picturesGone', () async {
      final gone = <int>[];
      final subscription = events.picturesGone.listen(gone.add);
      await _send('onTurnPictureGone', [4]);
      await _send('onTurnPictureGone', [3]);
      await settle();
      expect(gone, [4, 3]);
      await subscription.cancel();
    });

    test('onTurnLog writes turn native <kind> in category ui, its null fields dropped', () async {
      await _send('onTurnLog', [
        'begin',
        <String, Object?>{
          'wUs': 1760000000000000,
          'turn': 2,
          'method': 'remove',
          'picture': 'cut',
          'angle': 1.5707963,
          'animated': false,
          'snapshotMs': null,
        },
      ]);
      await _send('onTurnLog', [
        'container',
        <String, Object?>{'wUs': 1760000000500000, 'turn': 0, 'event': 'installed', 'method': 'counter'},
      ]);
      expect(logs.events.every((event) => event.cat == LogCategory.ui && event.level == LogLevel.info), isTrue);
      expect([
        for (final event in logs.events)
          {'msg': event.msg, ...event.f.map((key, value) => MapEntry(key, value.toJson()))},
      ], [
        {
          'msg': 'turn native begin',
          'wUs': 1760000000000000,
          'turn': 2,
          'method': 'remove',
          'picture': 'cut',
          'angle': 1.5707963,
          'animated': false,
        },
        {'msg': 'turn native container', 'wUs': 1760000000500000, 'turn': 0, 'event': 'installed', 'method': 'counter'},
      ]);
    });
  });

  group('IosOrientationHost', () {
    late IosOrientationHost host;

    setUp(() => host = IosOrientationHost(DeviceHostApi(), events));

    test('every method and picture reaches the native side; 系统 goes as legacy, only ever sent switched off', () async {
      for (final method in TurnMethod.values) {
        await host.setTurnTakeover(method.drawn, method: method, picture: TurnPicture.cut);
      }
      for (final picture in TurnPicture.values) {
        await host.setTurnTakeover(true, method: TurnMethod.remove, picture: picture);
      }
      expect(hostCalls, [
        'setTurnTakeover false legacy cut',
        'setTurnTakeover true legacy cut',
        'setTurnTakeover true remove cut',
        'setTurnTakeover true counter cut',
        'setTurnTakeover true noActions cut',
        'setTurnTakeover true quietRequest cut',
        'setTurnTakeover true noSpin cut',
        'setTurnTakeover true remove cut',
        'setTurnTakeover true remove fade',
        'setTurnTakeover true remove none',
      ]);
    });

    test('turnDrawn sends the id; turns and pictures gone come from the events', () async {
      await host.turnDrawn(12);
      expect(hostCalls, ['turnDrawn 12']);

      final turns = <TurnStart>[];
      final gone = <int>[];
      final subscriptions = [host.turns.listen(turns.add), host.picturesGone.listen(gone.add)];
      await _send('onTurn', [12, pi / 2, 0.3]);
      await _send('onTurnPictureGone', [12]);
      await settle();
      expect(turns.map((turn) => turn.id), [12]);
      expect(gone, [12]);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });
  });
}
