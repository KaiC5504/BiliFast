import 'package:bili_core/api.dart';

/// The equipped 装扮 and its package.
abstract interface class SkinApi {
  /// The official app's `/x/resource/show/skin`, with the app token; null when nothing with a package is equipped.
  Future<SkinEquip?> equipped();

  /// The package zip, a public file on Bilibili's CDN (no account, no cookies).
  Future<List<int>> download(Uri package);
}

class ClientSkinApi implements SkinApi {
  ClientSkinApi(this._client);

  final BiliClient _client;

  @override
  Future<SkinEquip?> equipped() => _client.skin();

  @override
  Future<List<int>> download(Uri package) => throw UnimplementedError('skin data builder');
}
