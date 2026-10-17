part of 'bili_client.dart';

sealed class TVLoginState {
  const TVLoginState();

  static const TVLoginState waiting = TVLoginWaiting();
  static const TVLoginState expired = TVLoginExpired();
  const factory TVLoginState.confirmed({required String accessToken, required int mid}) = TVLoginConfirmed;
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
  const TVLoginConfirmed({required this.accessToken, required this.mid});

  final String accessToken;
  final int mid;

  @override
  bool operator ==(Object other) => other is TVLoginConfirmed && other.accessToken == accessToken && other.mid == mid;

  @override
  int get hashCode => Object.hash(accessToken, mid);

  // The token is a credential, so it never lands in a log or test failure message.
  @override
  String toString() => 'TVLoginState.confirmed(mid: $mid)';
}

({String accessToken, int mid}) _tvToken(Object? json) {
  final object = JsonObject.from(json);
  final token = object.required(object.string('access_token'), 'access_token');
  final mid = object.required(object.integer('mid'), 'mid');
  if (token.isEmpty) throw const DecodeError('missing access_token');
  return (accessToken: token, mid: mid);
}

/// The app API (and the passport TV login that issues its token) wants a signature and an access token, not cookies.
extension BiliClientApp on BiliClient {
  /// The URL is Bilibili's confirm page; the user opens it in a signed-in web view and taps 确认登录.
  Future<({String url, String authCode})> tvAuthCode({required AppSigner signer}) {
    final form = signer.signed({'local_id': '0'}, ts: _unixSeconds);
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

  Future<TVLoginState> tvPoll({required AppSigner signer, required String authCode}) async {
    final form = signer.signed({'auth_code': authCode, 'local_id': '0'}, ts: _unixSeconds);
    final envelope = await _postEnvelope(
      '/x/passport-tv-login/qrcode/poll',
      form: form,
      host: BiliClient.passport,
      cookies: false,
      decode: _tvToken,
    );
    switch (envelope.code) {
      case 0:
        final token = envelope.data;
        if (token == null) throw const BiliError.decoding('tv login: confirmed without a token');
        return TVLoginState.confirmed(accessToken: token.accessToken, mid: token.mid);
      case 86039 || 86090:
        return TVLoginState.waiting;
      case 86038:
        return TVLoginState.expired;
      default:
        throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
    }
  }

  /// `on: true` dislikes the video, `on: false` takes it back.
  Future<void> dislike({required int aid, required bool on, required String accessToken, required AppSigner signer}) {
    final form = signer.signed({'aid': '$aid', 'dislike': on ? '0' : '1', 'access_key': accessToken}, ts: _unixSeconds);
    return postVoid('/x/v2/view/dislike', form: form, host: BiliClient.appAPI, cookies: false);
  }
}
