import '../shared/byte_range.dart';
import 'cancel.dart';
import 'transport.dart';

/// dart:io (HTTP/1.1): Windows, Android until cronet_http, and the tests.
final class IoRangeTransport implements RangeTransport {
  IoRangeTransport({this.headers = const {}, this.connectionsPerHost = 8});

  /// Sent with every request: the Safari User-Agent and Bilibili's Referer.
  final Map<String, String> headers;

  @override
  final int? connectionsPerHost;

  @override
  String get name => 'dart:io';

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) =>
      throw UnimplementedError('engine agent');

  @override
  void close() => throw UnimplementedError('engine agent');
}
