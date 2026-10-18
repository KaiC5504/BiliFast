import '../orientation_host.dart';
import 'device_api.g.dart';
import 'ios_device_events.dart';

/// DeviceChannel.swift's masks and reports, over Pigeon (pigeons/device_api.dart).
final class IosOrientationHost implements OrientationHost {
  IosOrientationHost(this._host, this._events);

  final DeviceHostApi _host;
  final IosDeviceEvents _events;

  @override
  Future<void> setOrientationEvents(bool enabled) => _host.setOrientationEvents(enabled);

  @override
  Stream<PhoneOrientation> get deviceOrientations => _events.deviceOrientations.map(_phone);

  @override
  Future<PhoneOrientation> deviceOrientation() async => _phone(await _host.deviceOrientation());

  @override
  Future<ScreenOrientation> interfaceOrientation() async => switch (await _host.interfaceOrientation()) {
        NativeInterfaceOrientation.portrait => ScreenOrientation.portrait,
        NativeInterfaceOrientation.landscapeLeft => ScreenOrientation.landscapeLeft,
        NativeInterfaceOrientation.landscapeRight => ScreenOrientation.landscapeRight,
        NativeInterfaceOrientation.unknown => ScreenOrientation.unknown,
      };

  @override
  Future<void> requestOrientations(int request, OrientationMask mask) => _host.requestOrientations(
        request,
        switch (mask) {
          OrientationMask.portrait => NativeOrientationMask.portrait,
          OrientationMask.landscape => NativeOrientationMask.landscape,
          OrientationMask.landscapeLeft => NativeOrientationMask.landscapeLeft,
          OrientationMask.landscapeRight => NativeOrientationMask.landscapeRight,
        },
      );

  @override
  Stream<OrientationRefusal> get refusals => _events.refusals;

  static PhoneOrientation _phone(NativeDeviceOrientation orientation) => switch (orientation) {
        NativeDeviceOrientation.portrait => PhoneOrientation.portrait,
        NativeDeviceOrientation.portraitUpsideDown => PhoneOrientation.portraitUpsideDown,
        NativeDeviceOrientation.landscapeLeft => PhoneOrientation.landscapeLeft,
        NativeDeviceOrientation.landscapeRight => PhoneOrientation.landscapeRight,
        NativeDeviceOrientation.faceUp => PhoneOrientation.faceUp,
        NativeDeviceOrientation.faceDown => PhoneOrientation.faceDown,
        NativeDeviceOrientation.unknown => PhoneOrientation.unknown,
      };
}
