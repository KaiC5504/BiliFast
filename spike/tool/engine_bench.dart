// Engine-only speed test, the Dart counterpart of BiliNative's ripper-bench:
//   dart run tool/engine_bench.dart [--bv BV…] [--qn 120] [--mb 24] [--playurl local/x.json] [--cookies local/cookie.txt]
// Reads the first N MB of the video track once over one connection (what direct mode does) and once through
// the BTR session behind the local server (what the player reads in BTR mode).

import 'dart:convert';
import 'dart:io';

import 'package:bili_flutter_spike/api/bili_client.dart';
import 'package:bili_flutter_spike/api/models.dart';
import 'package:bili_flutter_spike/ripper/local_server.dart';
import 'package:bili_flutter_spike/ripper/session.dart';

Future<void> main(List<String> args) async {
  String? arg(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final qn = int.parse(arg('--qn') ?? '120');
  final mb = int.parse(arg('--mb') ?? '24');
  final cookieFile = arg('--cookies');
  final client = BiliClient(
      cookies: cookieFile == null ? null : BiliClient.parseCookieHeader(File(cookieFile).readAsStringSync().trim()));
  await client.ensureRiskCookies();

  PlayInfo info;
  final saved = arg('--playurl');
  if (saved != null) {
    final json = jsonDecode(File(saved).readAsStringSync()) as Map<String, dynamic>;
    info = PlayInfo.parse((json['data'] ?? json) as Map<String, dynamic>);
  } else {
    var bv = arg('--bv');
    if (bv == null) {
      final feed = await client.recommendFeed(0);
      bv = feed.first.bvid;
      stdout.writeln('feed: ${feed.length} cards, using $bv "${feed.first.title}"');
    }
    final view = await client.view(bv);
    info = await client.playUrl(bv, view.cid, qn);
  }
  final (video, audio) = info.choose(qn)!;
  stdout.writeln('quality ${video.id} ${video.codecLabel} ${video.width}x${video.height} '
      '${(video.bandwidth / 1e6).toStringAsFixed(1)} Mbps; offered ${info.qualities.keys.toList()}');
  final bytes = mb << 20;

  final http = HttpClient();
  final direct = await _read(http, video.baseUrl, bytes, BiliClient.mediaHeaders);
  stdout.writeln('direct (one connection to ${Uri.parse(video.baseUrl).host}): $direct');

  final server = LocalServer();
  await server.start();
  final media = HttpClient()
    ..maxConnectionsPerHost = 8
    ..idleTimeout = const Duration(seconds: 30);
  final session = RipperSession({
    Track.video: TrackSource(video.baseUrl, video.backupUrls, video.indexRange.end),
    Track.audio: TrackSource(audio.baseUrl, audio.backupUrls, audio.indexRange.end),
  }, media);
  final id = server.add(session);
  final btr = await _read(http, server.url(id, Track.video), bytes, const {});
  stdout.writeln('btr: $btr');
  final s = session.stats;
  stdout.writeln('  pieces ${s.pieces}, hedges ${s.hedges}, failures ${s.failures}, '
      'wasted ${(s.wastedBytes / 1048576).toStringAsFixed(1)} MB');
  for (final e in s.nodes.entries) {
    stdout.writeln('  ${e.key}: ${(e.value.bytes / 1048576).toStringAsFixed(1)} MB in ${e.value.pieces} pieces, '
        'ttfb ${e.value.ttfbMs.round()} ms, ${e.value.failures} failed, ${e.value.cancelled} cancelled');
  }
  s.errors.forEach((k, v) => stdout.writeln('  error $k x$v'));
  await server.stop();
  http.close(force: true);
  media.close(force: true);
  exit(0);
}

Future<String> _read(HttpClient http, String url, int bytes, Map<String, String> headers) async {
  final started = DateTime.now();
  final req = await http.getUrl(Uri.parse(url));
  headers.forEach(req.headers.set);
  req.headers.set('Range', 'bytes=0-${bytes - 1}');
  final res = await req.close();
  int? firstByteMs;
  var got = 0;
  await for (final chunk in res) {
    firstByteMs ??= DateTime.now().difference(started).inMilliseconds;
    got += chunk.length;
  }
  final ms = DateTime.now().difference(started).inMilliseconds;
  return 'status ${res.statusCode}, ${(got / 1048576).toStringAsFixed(1)} MB in $ms ms, '
      'first byte $firstByteMs ms, ${(got / 1048576 / (ms / 1000)).toStringAsFixed(2)} MB/s';
}
