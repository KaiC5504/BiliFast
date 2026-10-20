import '../orientation_host.dart';
import '../turn_style.dart';
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

  @override
  Future<void> setTurnTakeover(bool enabled, {required TurnMethod method, required TurnPicture picture}) =>
      _host.setTurnTakeover(
        enabled,
        switch (method) {
          TurnMethod.system || TurnMethod.legacy => NativeTurnMethod.legacy,
          TurnMethod.remove => NativeTurnMethod.remove,
          TurnMethod.counter => NativeTurnMethod.counter,
          TurnMethod.noActions => NativeTurnMethod.noActions,
          TurnMethod.quietRequest => NativeTurnMethod.quietRequest,
          TurnMethod.noSpin => NativeTurnMethod.noSpin,
        },
        switch (picture) {
          TurnPicture.cut => NativeTurnPicture.cut,
          TurnPicture.fade => NativeTurnPicture.fade,
          TurnPicture.none => NativeTurnPicture.none,
        },
      );

  @override
  Stream<TurnStart> get turns => _events.turns;

  @override
  Future<void> turnDrawn(int turn) => _host.turnDrawn(turn);

  @override
  Stream<int> get picturesGone => _events.picturesGone;

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
