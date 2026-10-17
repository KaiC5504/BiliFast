import 'md5.dart';
import 'wbi.dart';

/// The app API's request signing: the secret is appended to the sorted, percent-encoded query and hashed.
/// The key pair is a parameter because it comes from a build-time secret and never lives in this package.
final class AppSigner {
  const AppSigner({required this._appKey, required this._appSecret});

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
