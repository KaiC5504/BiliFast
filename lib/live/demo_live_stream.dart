import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// The repo's 3 s HLS test clip (integration_test/fixtures/hls, its video only) as an endless live stream: a sliding
/// playlist whose segments repeat the clip with their decode times moved on by a whole clip each loop, so the player
/// sees one unbroken stream that never ends.
final class DemoLiveClip {
  DemoLiveClip({required String playlist, required Uint8List media}) {
    double? duration;
    for (final line in playlist.split('\n').map((line) => line.trim())) {
      if (line.startsWith('#EXT-X-MAP:')) {
        final range = RegExp(r'BYTERANGE="(\d+)@(\d+)"').firstMatch(line);
        if (range == null) throw const FormatException('map without a byte range');
        init = _slice(media, int.parse(range.group(2)!), int.parse(range.group(1)!));
      } else if (line.startsWith('#EXTINF:')) {
        duration = double.parse(line.substring(8).split(',').first);
      } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
        final [length, offset] = line.substring(17).split('@').map(int.parse).toList();
        _segments.add((bytes: _slice(media, offset, length), seconds: duration ?? 0));
        duration = null;
      }
    }
    if (_segments.isEmpty) throw const FormatException('no segments');
    _loopSeconds = _segments.fold(0.0, (sum, segment) => sum + segment.seconds);
    _loopTicks = (_timescale(init) * _loopSeconds).round();
  }

  late final Uint8List init;
  final _segments = <({Uint8List bytes, double seconds})>[];
  late final double _loopSeconds;
  late final int _loopTicks;

  /// Segments a new listener can start on at once.
  static const _head = 3;
  static const _window = 4;

  /// The live playlist [elapsed] after the stream started.
  String playlist(Duration elapsed) {
    final perSegment = _loopSeconds / _segments.length;
    final available = _head + (elapsed.inMicroseconds / 1e6 / perSegment).floor();
    final first = available > _window ? available - _window : 0;
    final longest = _segments.map((segment) => segment.seconds).reduce((a, b) => a > b ? a : b);
    return [
      '#EXTM3U',
      '#EXT-X-VERSION:7',
      '#EXT-X-TARGETDURATION:${longest.ceil()}',
      '#EXT-X-MEDIA-SEQUENCE:$first',
      '#EXT-X-INDEPENDENT-SEGMENTS',
      '#EXT-X-MAP:URI="init.mp4"',
      for (var sequence = first; sequence < available; sequence++) ...[
        '#EXTINF:${_segments[sequence % _segments.length].seconds.toStringAsFixed(3)},',
        'seg/$sequence.m4s',
      ],
      '',
    ].join('\n');
  }

  /// Segment [sequence]: the clip's own, its fragment number and decode time carried on past the loops before it.
  Uint8List segment(int sequence) {
    final bytes = Uint8List.fromList(_segments[sequence % _segments.length].bytes);
    final shift = sequence ~/ _segments.length * _loopTicks;
    final data = ByteData.sublistView(bytes);
    _walk(data, 0, bytes.length, (type, at) {
      switch (type) {
        case 'mfhd':
          data.setUint32(at + 12, sequence + 1);
        case 'tfdt':
          if (data.getUint8(at + 8) == 1) {
            data.setUint64(at + 12, data.getUint64(at + 12) + shift);
          } else {
            data.setUint32(at + 12, data.getUint32(at + 12) + shift);
          }
      }
    });
    return bytes;
  }

  static int _timescale(Uint8List init) {
    final data = ByteData.sublistView(init);
    int? timescale;
    _walk(data, 0, init.length, (type, at) {
      if (type == 'mdhd' && timescale == null) {
        timescale = data.getUint32(at + (data.getUint8(at + 8) == 1 ? 28 : 20));
      }
    });
    return timescale ?? (throw const FormatException('no mdhd'));
  }

  static const _containers = {'moov', 'trak', 'mdia', 'moof', 'traf'};

  static void _walk(ByteData data, int start, int end, void Function(String type, int at) visit) {
    var at = start;
    while (at + 8 <= end) {
      final size = data.getUint32(at);
      if (size < 8 || at + size > end) return;
      final type = String.fromCharCodes(Uint8List.sublistView(data, at + 4, at + 8));
      visit(type, at);
      if (_containers.contains(type)) _walk(data, at + 8, at + size, visit);
      at += size;
    }
  }

  static Uint8List _slice(Uint8List media, int offset, int length) =>
      Uint8List.fromList(Uint8List.sublistView(media, offset, offset + length));
}

/// [DemoLiveClip] over loopback HTTP for `--fake-account` on Windows: mpv's HLS reader wouldn't play the clip from
/// disk. One server per run, started on the first ask; it goes with the process.
abstract final class DemoLiveServer {
  static Future<Uri?>? _started;

  /// The stream's playlist address, or null where the clip isn't found or the server can't start.
  static Future<Uri?> address() => _started ??= _start();

  static Future<Uri?> _start() async {
    final directory = _fixtureDirectory();
    if (directory == null) return null;
    try {
      final clip = DemoLiveClip(
        playlist: await File('${directory.path}/v.m3u8').readAsString(),
        media: await File('${directory.path}/v.mp4').readAsBytes(),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final started = Stopwatch()..start();
      server.listen((request) => unawaited(_answer(request, clip, started.elapsed)));
      return Uri.parse('http://127.0.0.1:${server.port}/live.m3u8');
    } on Object {
      return null;
    }
  }

  static Future<void> _answer(HttpRequest request, DemoLiveClip clip, Duration elapsed) async {
    final response = request.response..persistentConnection = false;
    final path = request.uri.path;
    final segment = RegExp(r'^/seg/(\d+)\.m4s$').firstMatch(path);
    final (List<int>? body, ContentType? type) = switch (path) {
      '/live.m3u8' => (clip.playlist(elapsed).codeUnits, ContentType('application', 'vnd.apple.mpegurl')),
      '/init.mp4' => (clip.init, ContentType('video', 'mp4')),
      _ when segment != null => (clip.segment(int.parse(segment.group(1)!)), ContentType('video', 'mp4')),
      _ => (null, null),
    };
    if (body == null || (request.method != 'GET' && request.method != 'HEAD')) {
      response.statusCode = HttpStatus.notFound;
    } else {
      response.headers
        ..contentType = type
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      response.contentLength = body.length;
      if (request.method == 'GET') response.add(body);
    }
    try {
      await response.close();
    } on SocketException {
      // mpv drops connections it no longer needs.
    }
  }

  /// integration_test/fixtures/hls, looked for above the working folder and the app.
  static Directory? _fixtureDirectory() {
    const relative = 'integration_test/fixtures/hls';
    for (final start in [Directory.current, File(Platform.resolvedExecutable).parent]) {
      Directory? directory = start.absolute;
      while (directory != null) {
        final found = Directory('${directory.path}/$relative');
        if (File('${found.path}/v.m3u8').existsSync()) return found;
        final parent = directory.parent;
        directory = parent.path == directory.path ? null : parent;
      }
    }
    return null;
  }
}
