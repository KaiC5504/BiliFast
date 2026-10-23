part of 'bili_client.dart';

const _skinPath = '/x/resource/show/skin';

/// The equipped 装扮 and 加载动画, the official app's own call (no web call reads them), with the app token.
extension BiliClientSkin on BiliClient {
  /// Nothing worn when nothing is equipped, an answer whose `data` is null included (`_officialGet` would throw on
  /// that). An answer of a shape [SkinWorn.fromJson] doesn't know throws [BiliError.decoding].
  Future<SkinWorn> skin() async {
    final token = _officialToken(true);
    final envelope = await _getEnvelope(
      _skinPath,
      // The official app asks with 0 unless it is showing a free colour theme; the equipped package is what's wanted.
      query: _officialSigned({'is_free_theme': '0'}, token),
      signed: false,
      host: BiliClient.appAPI,
      sendCookies: false,
      extraHeaders: _officialHeaders(const {}),
      decode: SkinWorn.fromJson,
    );
    final checked = _officialChecked(envelope, token);
    if (checked.code != 0) throw BiliError.api(code: checked.code, message: checked.message ?? '');
    return checked.data ?? const SkinWorn();
  }
}
