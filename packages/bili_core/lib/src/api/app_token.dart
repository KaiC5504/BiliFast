import 'json.dart';

/// The official app API's login: the access token its account calls carry, and the refresh token that renews it.
/// Kept as JSON in the keychain's app-token item.
final class AppToken {
  const AppToken({required this.accessToken, required this.refreshToken, required this.mid, required this.expiresAt});

  factory AppToken.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final access = object.required(object.string('access_token'), 'access_token');
    final refresh = object.required(object.string('refresh_token'), 'refresh_token');
    if (access.isEmpty || refresh.isEmpty) throw const DecodeError('empty app token');
    return AppToken(
      accessToken: access,
      refreshToken: refresh,
      mid: object.required(object.integer('mid'), 'mid'),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(object.required(object.integer('expires_at'), 'expires_at') * 1000,
          isUtc: true),
    );
  }

  /// The passport's answer (`token_info`, or the TV login's flat `data`), whose `expires_in` counts from [now].
  factory AppToken.issued(Object? json, {required DateTime now}) {
    final object = JsonObject.from(json);
    final access = object.required(object.string('access_token'), 'access_token');
    final refresh = object.required(object.string('refresh_token'), 'refresh_token');
    if (access.isEmpty || refresh.isEmpty) throw const DecodeError('empty app token');
    final seconds = object.required(object.integer('expires_in'), 'expires_in');
    return AppToken(
      accessToken: access,
      refreshToken: refresh,
      mid: object.required(object.integer('mid'), 'mid'),
      expiresAt: now.toUtc().add(Duration(seconds: seconds)),
    );
  }

  /// How close to [expiresAt] the one renewal call is made: until then the launch only compares dates.
  static const renewWithin = Duration(days: 30);

  final String accessToken;
  final String refreshToken;
  final int mid;
  final DateTime expiresAt;

  bool dueForRenewal(DateTime now) => expiresAt.difference(now) < renewWithin;

  bool expired(DateTime now) => !now.isBefore(expiresAt);

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'mid': mid,
    'expires_at': expiresAt.millisecondsSinceEpoch ~/ 1000,
  };

  @override
  bool operator ==(Object other) =>
      other is AppToken &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.mid == mid &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, mid, expiresAt);

  // Both tokens are credentials, so they never reach a log or a test's failure message.
  @override
  String toString() => 'AppToken(expiresAt: ${expiresAt.toIso8601String()})';
}
