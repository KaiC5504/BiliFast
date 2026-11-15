import '../device/ios/device_api.g.dart';
import 'app_icon.dart';

/// The home screen icon through DeviceChannel.swift (UIApplication's alternate icons).
final class IosAppIconHost implements AppIconHost {
  IosAppIconHost({DeviceHostApi? host}) : _host = host ?? DeviceHostApi();

  final DeviceHostApi _host;

  @override
  Future<AppIconChoice> current() async => AppIconChoice.of(await _host.alternateIconName());

  @override
  Future<void> choose(AppIconChoice choice) => _host.setAlternateIconName(choice.iconSet);
}
