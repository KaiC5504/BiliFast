import 'package:bilifast/device/ios/device_api.g.dart';
import 'package:bilifast/settings/app_icon.dart';
import 'package:bilifast/settings/ios_app_icon_host.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _prefix = 'dev.flutter.pigeon.bilifast.DeviceHostApi.';
const _methods = ['alternateIconName', 'setAlternateIconName'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<List<Object?>> calls;
  late String? iconName;
  late PlatformException? failure;
  late IosAppIconHost host;

  MessageCodec<Object?> codec() => DeviceHostApi.pigeonChannelCodec;

  setUp(() {
    calls = [];
    iconName = null;
    failure = null;
    host = IosAppIconHost();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in _methods) {
      messenger.setMockMessageHandler('$_prefix$method', (message) async {
        final args = codec().decodeMessage(message) as List<Object?>? ?? const [];
        calls.add([method, ...args]);
        final error = failure;
        if (error != null) return codec().encodeMessage(<Object?>[error.code, error.message, error.details]);
        return codec().encodeMessage(<Object?>[method == 'alternateIconName' ? iconName : null]);
      });
    }
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in _methods) {
      messenger.setMockMessageHandler('$_prefix$method', null);
    }
  });

  test('reads the icon set the home screen shows, an unknown one as the primary icon', () async {
    expect(await host.current(), AppIconChoice.standard);
    iconName = 'AppIconCat';
    expect(await host.current(), AppIconChoice.cat);
    iconName = 'AppIconRemoved';
    expect(await host.current(), AppIconChoice.standard);
    expect(calls, everyElement(['alternateIconName']));
  });

  test("sends the choice's icon set, null for the primary icon", () async {
    await host.choose(AppIconChoice.cat);
    await host.choose(AppIconChoice.standard);
    expect(calls, [
      ['setAlternateIconName', 'AppIconCat'],
      ['setAlternateIconName', null],
    ]);
  });

  test("the host's refusal reaches the caller", () async {
    failure = PlatformException(code: 'alternate-icons', message: 'unsupported');
    await expectLater(
      host.choose(AppIconChoice.cat),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'alternate-icons')
            .having((error) => error.message, 'message', 'unsupported'),
      ),
    );
    await expectLater(host.current(), throwsA(isA<PlatformException>()));
  });
}
