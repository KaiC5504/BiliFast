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

/// The same code under the iPhone pair (docs/reference/official-iphone-calls.md).
const _iphoneTvCodeFields = {'local_id': '0', 'mobi_app': 'iphone', 'platform': 'ios'};

/// The app token's login: a TV login code, confirmed in the official app (its confirm page takes nothing else: a call
/// with the web login's cookies gets -101), then polled for the token. Both the code and the poll are signed with
/// [BiliClient.loginIdentity]'s pair, and the token keeps that identity: Bilibili takes it only under the pair that
/// issued it.
extension BiliClientApp on BiliClient {
  /// The URL is Bilibili's confirm page.
  Future<({String url, String authCode})> tvAuthCode() {
    final identity = loginIdentity;
    final fields = switch (identity) {
      OfficialIdentity.android => _tvCodeFields,
      OfficialIdentity.iphone => _iphoneTvCodeFields,
    };
    final form = identity.signer.signed(fields, ts: _unixSeconds);
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

  Future<TVLoginState> tvPoll(String authCode) async {
    final identity = loginIdentity;
    final form = identity.signer.signed({'auth_code': authCode, 'local_id': '0'}, ts: _unixSeconds);
    final envelope = await _postEnvelope(
      '/x/passport-tv-login/qrcode/poll',
      form: form,
      host: BiliClient.passport,
      cookies: false,
      decode: (json) => _issuedToken(json, identity: identity),
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
  /// adds the current token as `access_key` and signs as its identity, which the renewed token keeps.
  Future<AppToken> renewAppToken() async {
    final current = appToken ?? (throw BiliError.noAppToken);
    return _officialPost(
      '/x/passport-login/oauth2/refresh_token',
      {'refresh_token': current.refreshToken},
      (json) => _issuedToken(json, mid: current.mid, identity: current.identity),
      host: BiliClient.passport,
    );
  }

  /// The passport's answers carry the token flat (the TV poll's `data`), under `token_info`, or both. A renewal
  /// that leaves out `mid` keeps the account's.
  AppToken _issuedToken(Object? json, {int? mid, required OfficialIdentity identity}) {
    final object = JsonObject.from(json);
    final info = object.map['access_token'] == null ? object.nested('token_info')?.map ?? object.map : object.map;
    return AppToken.issued(
      info['mid'] == null && mid != null ? {...info, 'mid': mid} : info,
      now: now(),
      identity: identity,
    );
  }
}
