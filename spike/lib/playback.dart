import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:media_kit_video/media_kit_video.dart';

import 'api/bili_client.dart';
import 'api/models.dart';
import 'ripper/resolver.dart';
import 'ripper/session.dart';
import 'services.dart';

enum PlayMode { btr, direct }

/// What the spike measures for one playback. Times are milliseconds from `open`.
class Metrics {
  double? firstFrameMs;
  double? playingMs;
  int stalls = 0;
  double stallMs = 0;
  int seeks = 0;
  final seekMs = <double>[];
  String hwdec = '';
  String codec = '';
  String pixelFormat = '';
  String gamma = '';
  String size = '';
  double bufferAheadS = 0;
  double downloadBps = 0;

  Map<String, Object?> toJson() => {
        'firstFrameMs': firstFrameMs?.round(),
        'playingMs': playingMs?.round(),
        'stalls': stalls,
        'stallMs': stallMs.round(),
        'seekMs': seekMs.map((e) => e.round()).toList(),
        'hwdec': hwdec,
        'codec': codec,
        'pixelFormat': pixelFormat,
        'gamma': gamma,
        'size': size,
      };
}

/// One media_kit player plus, in BTR mode, a ripper session behind the local server.
class Playback extends ChangeNotifier {
  Playback() {
    player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
    controller = VideoController(player);
    _subs.addAll([
      player.stream.buffering.listen(_onBuffering),
      player.stream.position.listen(_onPosition),
      player.stream.playing.listen((_) => notifyListeners()),
      player.stream.error.listen((e) => debugPrint('mpv error: $e')),
    ]);
  }

  late final Player player;
  late final VideoController controller;
  final _subs = <StreamSubscription<Object?>>[];
  RipperSession? session;
  String? _sessionId;
  PlayMode? mode;
  DashStream? video;
  Metrics metrics = Metrics();
  double _openedAt = 0;
  double? _stallStart;
  double? _seekStart;
  double _seekTarget = 0;
  Timer? _poll;
  bool _disposed = false;

  NativePlayer get _native => player.platform as NativePlayer;
  double get _t => nowMs() - _openedAt;

  Future<void> open(PlayInfo info, PlayMode mode, {int maxQuality = 120}) async {
    final chosen = info.choose(maxQuality);
    if (chosen == null) throw StateError('no playable DASH tracks');
    final (v, a) = chosen;
    await _closeSession();
    this.mode = mode;
    video = v;
    metrics = Metrics()..codec = '${v.codecLabel} ${v.width}x${v.height} ${(v.bandwidth / 1e6).toStringAsFixed(1)} Mbps';
    _stallStart = null;
    _seekStart = null;
    String videoUrl, audioUrl;
    if (mode == PlayMode.btr) {
      final s = RipperSession({
        Track.video: TrackSource(v.baseUrl, v.backupUrls, v.indexRange.end),
        Track.audio: TrackSource(a.baseUrl, a.backupUrls, a.indexRange.end),
      }, Services.media);
      session = s;
      _sessionId = Services.server.add(s);
      videoUrl = Services.server.url(_sessionId!, Track.video);
      audioUrl = Services.server.url(_sessionId!, Track.audio);
    } else {
      videoUrl = v.baseUrl;
      audioUrl = a.baseUrl;
    }
    await _native.setProperty('user-agent', BiliClient.userAgent);
    await _native.setProperty('referrer', BiliClient.referer);
    // mpv's EDL joins the two DASH tracks into one source, so both start loading at once.
    final edl = 'edl://!no_chapters;%${videoUrl.length}%$videoUrl;!new_stream;!no_chapters;%${audioUrl.length}%$audioUrl';
    _openedAt = nowMs();
    final opened = player.open(Media(edl));
    unawaited(controller.waitUntilFirstFrameRendered.then((_) {
      metrics.firstFrameMs ??= _t;
      notifyListeners();
    }));
    await opened;
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) => _sample());
    notifyListeners();
  }

  void _onBuffering(bool buffering) {
    if (_openedAt == 0) return;
    final now = _t;
    if (buffering) {
      if (metrics.playingMs != null && _seekStart == null && _stallStart == null) _stallStart = now;
    } else if (_stallStart != null) {
      metrics.stalls++;
      metrics.stallMs += now - _stallStart!;
      _stallStart = null;
    }
    notifyListeners();
  }

  void _onPosition(Duration position) {
    final s = position.inMilliseconds / 1000;
    session?.playhead = s;
    if (metrics.playingMs == null && s > 0.2 && player.state.playing && !player.state.buffering) {
      metrics.playingMs = _t;
      notifyListeners();
    }
    if (_seekStart != null && s > _seekTarget + 0.3 && !player.state.buffering) {
      metrics.seekMs.add(_t - _seekStart!);
      _seekStart = null;
      notifyListeners();
    }
  }

  Future<void> seek(Duration to) async {
    // A stall that began before the seek is cut off there.
    if (_stallStart != null) {
      metrics.stalls++;
      metrics.stallMs += _t - _stallStart!;
      _stallStart = null;
    }
    metrics.seeks++;
    _seekStart = _t;
    _seekTarget = to.inMilliseconds / 1000;
    await player.seek(to);
  }

  Future<void> _sample() async {
    if (_disposed) return;
    try {
      final values = await Future.wait([
        _native.getProperty('hwdec-current'),
        _native.getProperty('demuxer-cache-duration'),
        _native.getProperty('cache-speed'),
        _native.getProperty('video-params/pixelformat'),
        _native.getProperty('video-params/gamma'),
        _native.getProperty('video-params/w'),
        _native.getProperty('video-params/h'),
      ]);
      if (_disposed) return;
      metrics
        ..hwdec = values[0]
        ..bufferAheadS = double.tryParse(values[1]) ?? 0
        ..downloadBps = mode == PlayMode.btr ? (session?.stats.recentBps ?? 0) : (double.tryParse(values[2]) ?? 0)
        ..pixelFormat = values[3]
        ..gamma = values[4]
        ..size = values[5].isEmpty ? '' : '${values[5]}x${values[6]}';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _closeSession() async {
    _poll?.cancel();
    final id = _sessionId;
    _sessionId = null;
    session = null;
    if (id != null) Services.server.remove(id);
  }

  Future<void> stop() async {
    await player.stop();
    await _closeSession();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _closeSession();
    player.dispose();
    super.dispose();
  }
}
