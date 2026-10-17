import '../shared/byte_range.dart';
import 'cancel.dart';

final class TransportResponse {
  const TransportResponse({required this.status, required this.headers, required this.body});

  final int status;

  /// Lowercased header names.
  final Map<String, String> headers;

  /// Single subscription. Cancelling the subscription cancels the request at once, so a losing
  /// hedge copy gives its connection back immediately.
  final Stream<List<int>> body;
}

/// Port of Transport.swift's `RangeTransport`.
abstract interface class RangeTransport {
  /// GET with `Range: bytes=start-end`. Completes once the response headers are in; the body streams.
  /// Cancelling [cancel] before the headers arrive aborts the request and throws [CancelledException].
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel});

  /// How many connections the transport opens to one host; further requests to an HTTP/1.1 host
  /// wait inside it for one to free up. Null when there is no such limit.
  int? get connectionsPerHost;

  /// Shown in the stats overlay, e.g. `URLSession` or `dart:io`.
  String get name;

  void close();
}

enum RipperErrorKind {
  firstByteTimeout,
  stalled,
  attemptTimeout,
  badResponse,
  lengthMismatch,
  totalMismatch,
  noNodes,
  invalidURL,
  closed,
}

final class RipperError implements Exception {
  const RipperError(this.kind, {this.status, this.got, this.expected});

  const RipperError.badResponse(int this.status)
      : kind = RipperErrorKind.badResponse,
        got = null,
        expected = null;

  const RipperError.lengthMismatch({required int this.got, required int this.expected})
      : kind = RipperErrorKind.lengthMismatch,
        status = null;

  final RipperErrorKind kind;
  final int? status;
  final int? got;
  final int? expected;

  bool get isTimeout =>
      kind == RipperErrorKind.firstByteTimeout ||
      kind == RipperErrorKind.stalled ||
      kind == RipperErrorKind.attemptTimeout;

  @override
  bool operator ==(Object other) =>
      other is RipperError &&
      other.kind == kind &&
      other.status == status &&
      other.got == got &&
      other.expected == expected;

  @override
  int get hashCode => Object.hash(kind, status, got, expected);

  @override
  String toString() => switch (kind) {
        RipperErrorKind.badResponse => 'badResponse($status)',
        RipperErrorKind.lengthMismatch => 'lengthMismatch(got $got, expected $expected)',
        _ => kind.name,
      };
}
