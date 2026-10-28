import 'package:bilifast/app/form_factor.dart';
import 'package:bilifast/device/ios/device_api.g.dart';
import 'package:bilifast/device/launch_form_factor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// DeviceChannel.swift's idiom, or its failure.
final class _Host extends DeviceHostApi {
  _Host(this.answer);

  final Object answer;
  var asked = 0;

  @override
  Future<bool> isPad() async {
    asked++;
    if (answer is bool) return answer as bool;
    throw answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('on iOS the idiom decides', () {
    test('an iPad is the iPad whatever the view, an iPhone the phone', () async {
      final pad = _Host(true);
      final launched = await launchFormFactor(const [], platform: TargetPlatform.iOS, host: pad);
      expect(launched.kind, FormFactor.pad);
      expect(launched.logFields, {'kind': 'pad', 'via': 'native'});
      expect(pad.asked, 1);

      final phone = await launchFormFactor(const [], platform: TargetPlatform.iOS, host: _Host(false));
      expect(phone.logFields, {'kind': 'phone', 'via': 'native'});
    });

    test('--pad means nothing on the phone', () async {
      final launched = await launchFormFactor(const ['--pad'], platform: TargetPlatform.iOS, host: _Host(false));
      expect(launched.kind, FormFactor.phone);
    });

    test('a host that fails leaves the phone and says why', () async {
      final launched = await launchFormFactor(const [],
          platform: TargetPlatform.iOS, host: _Host(PlatformException(code: 'channel-error')));
      expect(launched.kind, FormFactor.phone);
      expect(launched.logFields, {'kind': 'phone', 'via': 'default', 'error': 'PlatformException'});
    });

    test("over Pigeon's channel", () async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = 'dev.flutter.pigeon.bilifast.DeviceHostApi.isPad';
      messenger.setMockMessageHandler(
          channel, (_) async => DeviceHostApi.pigeonChannelCodec.encodeMessage(<Object?>[true]));
      addTearDown(() => messenger.setMockMessageHandler(channel, null));
      expect((await launchFormFactor(const [], platform: TargetPlatform.iOS)).kind, FormFactor.pad);
    });
  });

  test('Windows takes --pad, without it the phone', () async {
    final flagged = await launchFormFactor(const ['--mute', '--pad'], platform: TargetPlatform.windows);
    expect(flagged.logFields, {'kind': 'pad', 'via': 'flag'});
    final plain = await launchFormFactor(const ['--mute'], platform: TargetPlatform.windows);
    expect(plain.logFields, {'kind': 'phone', 'via': 'default'});
  });

  test('other platforms are the phone and never ask a host', () async {
    final host = _Host(true);
    final launched = await launchFormFactor(const ['--pad'], platform: TargetPlatform.android, host: host);
    expect(launched.kind, FormFactor.phone);
    expect(host.asked, 0);
  });
}
