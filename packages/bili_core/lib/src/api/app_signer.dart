import 'md5.dart';
import 'wbi.dart';

/// The app API's request signing: the secret is appended to the sorted, percent-encoded query and hashed.
final class AppSigner {
  const AppSigner({required this._appKey, required this._appSecret});

  /// The Android app's public pair (PiliPlus's for the app API), the same for everyone and tied to no account, so
  /// KaiC allowed it in the repo.
  static const android = AppSigner(appKey: 'dfca71928277209b', appSecret: 'b5475a8825547a4fc26c7d518eaaa02e');

  /// The iPhone app's public pair, the same in every copy of the official app: its own requests' signatures
  /// reproduce with it (docs/reference/official-iphone-calls.md).
  static const iphone = AppSigner(appKey: '27eb53fc9058f8c3', appSecret: 'c2ed53a74eeefe3cf99fbd01d8c9c375');

  final String _appKey;
  final String _appSecret;

  Map<String, String> signed(Map<String, String> params, {required int ts}) {
    final fields = Map.of(params);
    fields['appkey'] = _appKey;
    fields['ts'] = '$ts';
    fields['sign'] = MD5.hex(WBI.encodeQuery(fields) + _appSecret);
    return fields;
  }
}
