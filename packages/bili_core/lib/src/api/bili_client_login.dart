part of 'bili_client.dart';

/// The website's QR login and its logout, for the Windows build (`login_models.dart`).
extension BiliClientLogin on BiliClient {
  /// `GET /x/passport-login/web/qrcode/generate` on [BiliClient.passport].
  Future<WebLoginQr> webLoginQr() => throw UnimplementedError();

  /// `GET /x/passport-login/web/qrcode/poll?qrcode_key=` on [BiliClient.passport].
  Future<WebLoginPoll> webLoginPoll(String key) => throw UnimplementedError();

  /// `POST /login/exit/v2` on [BiliClient.passport]: ends this session on Bilibili's side, so the cookies stop
  /// working even where a copy survives. Throws when Bilibili refuses.
  Future<void> webLogout() => throw UnimplementedError();
}
