sealed class BiliError implements Exception {
  const BiliError();

  const factory BiliError.http(int status) = BiliHTTPError;
  const factory BiliError.api({required int code, required String message}) = BiliAPIError;
  const factory BiliError.decoding(String detail) = BiliDecodingError;
  static const BiliError notDash = BiliNotDashError();
  static const BiliError invalidLink = BiliInvalidLinkError();

  bool get needsLogin => switch (this) {
        BiliAPIError(code: -101) => true,
        _ => false,
      };

  String get userMessage => switch (this) {
        BiliHTTPError(status: 412) => 'B 站暂时拒绝了请求（风控），稍后再试',
        BiliHTTPError(:final status) => '网络请求失败（HTTP $status）',
        BiliAPIError(code: -101) => '需要登录',
        BiliAPIError(code: -352 || -412) => '请求过于频繁，请稍后再试',
        BiliAPIError(code: -404 || 62002 || 62004) => '视频不存在或已被删除',
        BiliAPIError(:final code, :final message) => 'B 站返回错误 $code：$message',
        BiliDecodingError() => 'B 站返回的数据无法解析',
        BiliNotDashError() => '这个视频不是 DASH 格式，暂不支持',
        BiliInvalidLinkError() => '没有找到视频链接',
      };
}

final class BiliHTTPError extends BiliError {
  const BiliHTTPError(this.status);

  final int status;

  @override
  bool operator ==(Object other) => other is BiliHTTPError && other.status == status;

  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => 'BiliError.http($status)';
}

final class BiliAPIError extends BiliError {
  const BiliAPIError({required this.code, required this.message});

  final int code;
  final String message;

  @override
  bool operator ==(Object other) => other is BiliAPIError && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'BiliError.api($code, $message)';
}

final class BiliDecodingError extends BiliError {
  const BiliDecodingError(this.detail);

  final String detail;

  @override
  bool operator ==(Object other) => other is BiliDecodingError && other.detail == detail;

  @override
  int get hashCode => detail.hashCode;

  @override
  String toString() => 'BiliError.decoding($detail)';
}

final class BiliNotDashError extends BiliError {
  const BiliNotDashError();

  @override
  String toString() => 'BiliError.notDash';
}

final class BiliInvalidLinkError extends BiliError {
  const BiliInvalidLinkError();

  @override
  String toString() => 'BiliError.invalidLink';
}
