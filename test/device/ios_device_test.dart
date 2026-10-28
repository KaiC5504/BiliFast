import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/ios/device_api.g.dart';
import 'package:bilifast/device/ios/ios_device_controls.dart';
import 'package:bilifast/device/ios/ios_device_events.dart';
import 'package:bilifast/device/ios/ios_orientation_host.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/orientation_host.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_orientation_host.dart';

const _hostPrefix = 'dev.flutter.pigeon.bilifast.DeviceHostApi.';
const _eventPrefix = 'dev.flutter.pigeon.bilifast.DeviceEventApi.';
const _methods = [
  'isPad',
  'setOrientationEvents',
  'deviceOrientation',
  'interfaceOrientation',
  'requestOrientations',
  'brightness',
  'setBrightness',
  'volume',
  'setVolume',
  'attachVolumeView',
  'detachVolumeView',
];

/// DeviceChannel.swift on the far end of the test messenger: records each message as it arrives, in order, and keeps
/// the brightness it is set to, as the screen does.
final class _NativeSide {
  final calls = <String>[];
  final replies = <String, Object?>{
    'deviceOrientation': NativeDeviceOrientation.faceUp,
    'interfaceOrientation': NativeInterfaceOrientation.landscapeLeft,
    'brightness': 0.25,
    'volume': 0.75,
    'isPad': false,
  };
  final errors = <String, PlatformException>{};

  MessageCodec<Object?> get _codec => DeviceHostApi.pigeonChannelCodec;

  void install() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in _methods) {
      messenger.setMockMessageHandler('$_hostPrefix$method', (message) async {
        final args = _codec.decodeMessage(message) as List<Object?>? ?? const [];
        calls.add([method, for (final arg in args) arg is Enum ? arg.name : '$arg'].join(' '));
        final error = errors[method];
        if (error != null) return _codec.encodeMessage(<Object?>[error.code, error.message, error.details]);
        if (method == 'setBrightness') replies['brightness'] = args.single;
        return _codec.encodeMessage(<Object?>[replies[method]]);
      });
    }
  }

  void uninstall() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in _methods) {
      messenger.setMockMessageHandler('$_hostPrefix$method', null);
    }
  }

  /// A DeviceEventApi call from Swift.
  Future<void> send(String event, List<Object?> args) {
    final done = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      '$_eventPrefix$event',
      _codec.encodeMessage(args),
      (_) => done.complete(),
    );
    return done.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _NativeSide native;
  late IosDeviceEvents events;

  setUp(() {
    native = _NativeSide()..install();
    events = IosDeviceEvents()..connect();
  });

  tearDown(() {
    native.uninstall();
    DeviceEventApi.setUp(null);
  });

  group('IosDeviceControls', () {
    late MemorySink logs;
    late IosDeviceControls controls;

    setUp(() {
      logs = MemorySink();
      controls = IosDeviceControls(DeviceHostApi(), events, logger: Logger(session: 'test')..add(logs));
    });

    test('levels are read from and set on the native side, clamped', () async {
      expect(await controls.brightness(), 0.25);
      expect(await controls.volume(), 0.75);
      await controls.setBrightness(1.4);
      await controls.setVolume(-0.2);
      await controls.setVolume(0.5);
      expect(native.calls, ['brightness', 'volume', 'setBrightness 1.0', 'setVolume 0.0', 'setVolume 0.5']);
    });

    test('full screen only attaches the volume view and leaving only detaches it, in order', () async {
      final entering = controls.enterFullScreen();
      final leaving = controls.leaveFullScreen();
      await Future.wait([entering, leaving]);
      expect(native.calls, ['attachVolumeView', 'detachVolumeView']);
    });

    test('a brightness set in full screen is still the brightness after leaving it', () async {
      await controls.enterFullScreen();
      await controls.setBrightness(0.8);
      await controls.leaveFullScreen();
      expect(await controls.brightness(), 0.8);
      expect(native.calls, ['attachVolumeView', 'setBrightness 0.8', 'detachVolumeView', 'brightness']);
    });

    test('a volume view without a slider is logged once and the gesture goes on', () async {
      native.errors['setVolume'] = PlatformException(code: IosDeviceControls.missingSliderCode, message: 'no slider');
      await controls.setVolume(0.3);
      await controls.setVolume(0.4);
      expect(logs.events.where((event) => event.msg.startsWith('volume slider not found')), hasLength(1));
    });

    test('any other native failure reaches the caller', () async {
      native.errors['setVolume'] = PlatformException(code: 'error', message: 'boom');
      await expectLater(controls.setVolume(0.3), throwsA(isA<PlatformException>()));
    });

    test('hardware volume changes arrive from onHardwareVolume', () async {
      final heard = <double>[];
      final subscription = controls.hardwareVolume.listen(heard.add);
      await native.send('onHardwareVolume', [0.6]);
      await settle();
      expect(heard, [0.6]);
      await subscription.cancel();
    });
  });

  group('IosOrientationHost', () {
    late IosOrientationHost host;

    setUp(() => host = IosOrientationHost(DeviceHostApi(), events));

    test('masks and orientations map one to one', () async {
      for (final mask in OrientationMask.values) {
        await host.requestOrientations(4, mask);
      }
      await host.setOrientationEvents(true);
      expect(await host.deviceOrientation(), PhoneOrientation.faceUp);
      expect(await host.interfaceOrientation(), ScreenOrientation.landscapeLeft);
      expect(native.calls, [
        for (final mask in OrientationMask.values) 'requestOrientations 4 ${mask.name}',
        'setOrientationEvents true',
        'deviceOrientation',
        'interfaceOrientation',
      ]);
    });

    test('every native interface orientation maps to the same one', () async {
      for (final each in NativeInterfaceOrientation.values) {
        native.replies['interfaceOrientation'] = each;
        expect((await host.interfaceOrientation()).name, each.name);
      }
    });

    test('device orientations and refusals arrive as events', () async {
      final turned = <PhoneOrientation>[];
      final refused = <OrientationRefusal>[];
      final subscriptions = [host.deviceOrientations.listen(turned.add), host.refusals.listen(refused.add)];
      for (final each in NativeDeviceOrientation.values) {
        await native.send('onDeviceOrientation', [each]);
      }
      await native.send('onOrientationRefused', [3, 'UISceneErrorDomain 101']);
      await settle();
      expect(turned.map((each) => each.name), [for (final each in NativeDeviceOrientation.values) each.name]);
      expect(refused, [(request: 3, error: 'UISceneErrorDomain 101')]);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });

    test("the iPad's refusal reverts a move the phone's rules made", () async {
      final logs = MemorySink();
      final orientation =
          OrientationController(controls: RecordingDeviceControls(), host: host, logger: Logger(session: 'test')..add(logs));
      addTearDown(orientation.dispose);
      orientation.begin(Object(), videoIsVertical: false);
      orientation.enterLandscape();
      await settle();
      expect(orientation.presentation, Presentation.landscape);
      final request = int.parse(native.calls.lastWhere((call) => call.startsWith('requestOrientations')).split(' ')[1]);

      await native.send('onOrientationRefused', [request, 'pad']);
      await settle();
      expect(orientation.presentation, Presentation.inline);
      expect(logs.events.singleWhere((event) => event.msg == 'orientation request refused').f['error']?.toJson(), 'pad');
    });
  });

  group('PlayerDevice', () {
    test('on iOS, full screen goes through the native side end to end', () async {
      final device = PlayerDevice.ios(events: events);
      final orientation = device.orientation;
      final page = Object();
      orientation.begin(page, videoIsVertical: false);
      orientation.enterLandscape();
      await settle();
      expect(native.calls, [
        'setOrientationEvents true',
        'attachVolumeView',
        'deviceOrientation',
        'requestOrientations 1 landscape',
      ]);

      native.calls.clear();
      await native.send('onOrientationRefused', [1, 'UISceneErrorDomain 101']);
      await settle();
      expect(orientation.presentation, Presentation.inline);
      expect(native.calls, ['detachVolumeView', 'requestOrientations 1 portrait']);

      native.calls.clear();
      await native.send('onDeviceOrientation', [NativeDeviceOrientation.landscapeRight]);
      await settle();
      expect(orientation.presentation, Presentation.landscape);
      orientation.end(page);
      await settle();
      expect(orientation.presentation, Presentation.inline);
      expect(native.calls.last, 'requestOrientations 3 portrait');
      expect(native.calls, contains('setOrientationEvents false'));
      orientation.dispose();
    });

    test('a brightness set in landscape stays after going back inline', () async {
      final device = PlayerDevice.ios(events: events);
      final orientation = device.orientation;
      final page = Object();
      orientation.begin(page, videoIsVertical: false);
      orientation.enterLandscape();
      await settle();
      await device.controls.setBrightness(0.8);
      orientation.exitToInline();
      await settle();
      expect(orientation.presentation, Presentation.inline);
      expect(await device.controls.brightness(), 0.8);
      expect(native.calls.where((call) => call.toLowerCase().contains('brightness')), [
        'setBrightness 0.8',
        'brightness',
      ]);
      orientation.end(page);
      await settle();
      orientation.dispose();
    });

    test('platform() is the native side on iOS and the window elsewhere', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        expect(PlayerDevice.platform().controls, isA<IosDeviceControls>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        expect(PlayerDevice.platform().controls, isA<NoDeviceControls>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
