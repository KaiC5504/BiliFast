part of 'bili_client.dart';

sealed class TVLoginState {
  const TVLoginState();

  static const TVLoginState waiting = TVLoginWaiting();
  static const TVLoginState expired = TVLoginExpired();
  const factory TVLoginState.confirmed(AppToken token) = TVLoginConfirmed;
}

final class TVLoginWaiting extends TVLoginState {
  const TVLoginWaiting();

  @override
  String toString() => 'TVLoginState.waiting';
}

final class TVLoginExpired extends TVLoginState {
  const TVLoginExpired();

  @override
  String toString() => 'TVLoginState.expired';
}

final class TVLoginConfirmed extends TVLoginState {
  const TVLoginConfirmed(this.token);

  final AppToken token;

  @override
  bool operator ==(Object other) => other is TVLoginConfirmed && other.token == token;

  @override
  int get hashCode => token.hashCode;

  // AppToken prints its expiry only, so neither token reaches a log or a test's failure message.
  @override
  String toString() => 'TVLoginState.confirmed($token)';
}

/// The TV login's code, asked as PiliPlus's `getHDcode` asks it.
const _tvCodeFields = {'local_id': '0', 'platform': 'android', 'mobi_app': 'android_hd'};

/// The app token's login: a TV login code, confirmed with the web login's cookies, then polled for the token. Both
/// the code and the poll are signed with [AppSigner.android] (the Android HD key), so the token pairs with every
/// official call.
extension BiliClientApp on BiliClient {
  /// The URL is Bilibili's confirm page; [confirmTvLogin] confirms it without the page.
  Future<({String url, String authCode})> tvAuthCode() {
    final form = AppSigner.android.signed(_tvCodeFields, ts: _unixSeconds);
    return post(
      '/x/passport-tv-login/qrcode/auth_code',
      form: form,
      host: BiliClient.passport,
      cookies: false,
      decode: (json) {
        final object = JsonObject.from(json);
        return (
          url: object.required(object.string('url'), 'url'),
          authCode: object.required(object.string('auth_code'), 'auth_code'),
        );
      },
    );
  }

  /// PiliPlus's "cookie转access_key": the web login confirms the code as tapping 确认 on its page would. The client
  /// adds the cookies and the `csrf` field; a refusal throws, and the page is the way left.
  Future<void> confirmTvLogin(String authCode) =>
      postVoid('/x/passport-tv-login/h5/qrcode/confirm', form: {'auth_code': authCode}, host: BiliClient.passport);

  Future<TVLoginState> tvPoll(String authCode) async {
    final form = AppSigner.android.signed({'auth_code': authCode, 'local_id': '0'}, ts: _unixSeconds);
    final envelope = await _postEnvelope(
      '/x/passport-tv-login/qrcode/poll',
      form: form,
      host: BiliClient.passport,
      cookies: false,
      decode: (json) => _issuedToken(json),
    );
    switch (envelope.code) {
      case 0:
        final token = envelope.data;
        if (token == null) throw const BiliError.decoding('tv login: confirmed without a token');
        return TVLoginState.confirmed(token);
      case 86039 || 86090:
        return TVLoginState.waiting;
      case 86038:
        return TVLoginState.expired;
      default:
        throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
    }
  }

  /// The one renewal near [AppToken.expiresAt]: the passport swaps the refresh token for a fresh pair. The helper
  /// adds the current token as `access_key`.
  Future<AppToken> renewAppToken() {
    final current = appToken;
    return _officialPost(
      '/x/passport-login/oauth2/refresh_token',
      {'refresh_token': current?.refreshToken ?? ''},
      (json) => _issuedToken(json, mid: current?.mid),
      host: BiliClient.passport,
    );
  }

  /// The passport's answers carry the token flat (the TV poll's `data`), under `token_info`, or both. A renewal
  /// that leaves out `mid` keeps the account's.
  AppToken _issuedToken(Object? json, {int? mid}) {
    final object = JsonObject.from(json);
    final info = object.map['access_token'] == null ? object.nested('token_info')?.map ?? object.map : object.map;
    return AppToken.issued(info['mid'] == null && mid != null ? {...info, 'mid': mid} : info, now: now());
  }
}
