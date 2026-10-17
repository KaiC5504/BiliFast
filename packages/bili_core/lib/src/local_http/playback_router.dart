import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../shared/byte_range.dart';
import 'http_request_parser.dart';
import 'range_request.dart';

final class MediaResource {
  const MediaResource({required this.totalSize, required this.prefix, required this.read});

  final int totalSize;

  /// Served from memory: the (patched) init segment and index.
  final Uint8List prefix;

  /// Cancelling the subscription must cancel the read underneath.
  final Stream<List<int>> Function(ByteRange range) read;
}

final class PlaybackAssets {
  const PlaybackAssets({required this.playlists, required this.media});

  final Map<String, String> playlists;
  final Map<String, MediaResource> media;
}

final class PlaybackBodyError implements Exception {
  const PlaybackBodyError.shorter({required this.expected, required int this.received});

  const PlaybackBodyError.longer({required this.expected}) : received = null;

  final int expected;

  /// Null for a body that ran longer than [expected].
  final int? received;

  bool get isShorter => received != null;

  @override
  bool operator ==(Object other) =>
      other is PlaybackBodyError && other.expected == expected && other.received == received;

  @override
  int get hashCode => Object.hash(expected, received);

  @override
  String toString() =>
      isShorter ? 'shorter(expected: $expected, received: $received)' : 'longer(expected: $expected)';
}

sealed class RouteResult {
  const RouteResult();
}

final class RouteText extends RouteResult {
  const RouteText({required this.status, required this.contentType, required this.body});

  final int status;
  final String contentType;
  final Uint8List body;
}

final class RouteMedia extends RouteResult {
  const RouteMedia({required this.status, required this.headers, required this.body});

  final int status;
  final List<(String, String)> headers;

  /// Single subscription. The read behind it starts only when it is listened to.
  final Stream<List<int>> body;
}

final class RouteFailure extends RouteResult {
  const RouteFailure({required this.status, this.headers = const []});

  final int status;
  final List<(String, String)> headers;
}

final class PlaybackRouter {
  final _entries = <String, PlaybackAssets>{};

  static final Random _random = Random.secure();

  /// 128 random bits as hex: the server listens on localhost only, and the token keeps other
  /// processes from guessing a playback's paths.
  static String makeToken() =>
      [for (var index = 0; index < 4; index++) _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')].join();

  String register(PlaybackAssets assets, {String? token}) {
    final key = token ?? makeToken();
    _entries[key] = assets;
    return key;
  }

  void unregister(String token) => _entries.remove(token);

  RouteResult route(HTTPRequestHead head) {
    if (head.method != 'GET' && head.method != 'HEAD') return const RouteFailure(status: 405);
    final parts = head.path.split('/');
    final assets = parts.length == 3 && parts[0].isEmpty ? _entries[parts[1]] : null;
    if (assets == null) return const RouteFailure(status: 404);
    final playlist = assets.playlists[parts[2]];
    if (playlist != null) {
      return RouteText(status: 200, contentType: 'application/vnd.apple.mpegurl', body: utf8.encode(playlist));
    }
    final media = assets.media[parts[2]];
    if (media == null) return const RouteFailure(status: 404);
    final int status;
    final ByteRange range;
    switch (RangeRequest.parse(head.headers['range'], totalSize: media.totalSize)) {
      case RangeUnsatisfiable():
        return RouteFailure(status: 416, headers: [('Content-Range', 'bytes */${media.totalSize}')]);
      case RangeFull():
        final whole = ByteRange.of(0, media.totalSize - 1);
        if (whole == null) return const RouteFailure(status: 416);
        status = 200;
        range = whole;
      case RangePartial(range: final requested):
        status = 206;
        range = requested;
    }
    final headers = [('Content-Type', 'video/mp4'), ('Accept-Ranges', 'bytes'), ('Content-Length', '${range.length}')];
    if (status == 206) headers.add(('Content-Range', 'bytes ${range.start}-${range.end}/${media.totalSize}'));
    if (head.method == 'HEAD') return RouteMedia(status: status, headers: headers, body: const Stream.empty());
    return RouteMedia(status: status, headers: headers, body: body(media, range));
  }

  /// Fails the stream unless it delivers exactly [expected] bytes, so a short or long upstream
  /// cannot leave a client waiting on an advertised Content-Length.
  static Stream<List<int>> lengthChecked(Stream<List<int>> stream, {required int expected}) =>
      _checked(() => stream, expected: expected);

  static Stream<List<int>> body(MediaResource media, ByteRange range) {
    final prefixEnd = media.prefix.length - 1;
    if (range.end <= prefixEnd) return Stream.value(media.prefix.sublist(range.start, range.end + 1));
    if (range.start > prefixEnd) return _checked(() => media.read(range), expected: range.length);
    final rest = ByteRange(prefixEnd + 1, range.end);
    return _checked(() => media.read(rest), expected: rest.length, head: media.prefix.sublist(range.start));
  }

  /// [head] goes out first and is not counted against [expected]. The read is opened only once the stream is
  /// listened to, so a body nobody listens to never starts one; pause, resume and cancel reach it.
  static Stream<List<int>> _checked(Stream<List<int>> Function() open, {required int expected, List<int>? head}) {
    final controller = StreamController<List<int>>();
    StreamSubscription<List<int>>? upstream;
    var received = 0;
    void fail(Object error, [StackTrace? stack]) {
      controller.addError(error, stack);
      controller.close();
    }

    controller
      ..onListen = () {
        if (head != null) controller.add(head);
        final Stream<List<int>> source;
        try {
          source = open();
        } catch (error, stack) {
          fail(error, stack);
          return;
        }
        final subscription = source.listen(
          (chunk) {
            if (controller.isClosed) return;
            final remaining = expected - received;
            if (chunk.length > remaining) {
              if (remaining > 0) controller.add(chunk.sublist(0, remaining));
              fail(PlaybackBodyError.longer(expected: expected));
              upstream?.cancel().ignore();
              return;
            }
            received += chunk.length;
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            if (!controller.isClosed) fail(error, stack);
          },
          onDone: () {
            if (controller.isClosed) return;
            if (received == expected) {
              controller.close();
            } else {
              fail(PlaybackBodyError.shorter(expected: expected, received: received));
            }
          },
          cancelOnError: true,
        );
        upstream = subscription;
        // A synchronous source can overrun before listen even returns.
        if (controller.isClosed) subscription.cancel().ignore();
      }
      ..onPause = (() => upstream?.pause())
      ..onResume = (() => upstream?.resume())
      ..onCancel = (() => upstream?.cancel());
    return controller.stream;
  }
}
