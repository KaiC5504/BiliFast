part of 'bili_client.dart';

const _skinPath = '/x/resource/show/skin';

/// The equipped 装扮, the official app's own call (no web call reads it), with the app token.
extension BiliClientSkin on BiliClient {
  /// Null when nothing with a package is equipped.
  Future<SkinEquip?> skin() => _officialGet(_skinPath, {'is_free_theme': '0'}, SkinEquip.fromJson);
}
