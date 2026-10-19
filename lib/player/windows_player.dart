import 'dart:async';

import 'package:bili_core/shared.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../shared/theme.dart';
import 'bili_player.dart';
import 'windows/mpv.dart';

/// What mpv is handed for a [PlayerSource].
enum MpvSource {
  /// The EDL when the source has both files, otherwise the master; if one doesn't open, the other.
  auto,

  /// The HLS master, in AVPlayer's request shape. mpv plays it, but its HLS demuxer can't seek outside what it
  /// has cached: such a seek, or a start position, runs straight to the end.
  hls,

  /// The spike's EDL of [PlayerSource.video] and [PlayerSource.audio]; seeks land where asked.
  edl,
}

/// media_kit (mpv) for development on Windows.
final class WindowsPlayer implements BiliPlayer {
  WindowsPlayer._(this._player, this._controller, this._mode, this._defaultUserAgent, this._muted) {
    final stream = _player.stream;
    _subscriptions.addAll([
      stream.playing.listen((playing) {
        _playing = playing;
        _updateStatus();
      }),
      stream.buffering.listen((buffering) {
        _buffering = buffering;
        _updateStatus();
      }),
      stream.completed.listen((completed) {
        _completed = completed;
        _updateStatus();
      }),
      stream.duration.listen(_onDuration),
      stream.rate.listen(_onRate),
      stream.width.listen((_) => _onSize()),
      stream.height.listen((_) => _onSize()),
      stream.error.listen(_onError),
    ]);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  /// [muted] starts at volume 0, before anything can play: tests must make no sound.
  static Future<WindowsPlayer> create({MpvSource source = MpvSource.auto, bool muted = false}) async {
    mk.MediaKit.ensureInitialized();
    final player = mk.Player(configuration: mk.PlayerConfiguration(logLevel: mk.MPVLogLevel.warn, muted: muted));
    final controller = VideoController(player);
    // The controller sets itself up after the next frame, and every player command waits for it; an idle app
    // draws none.
    WidgetsBinding.instance.scheduleForcedFrame();
    final native = player.platform as mk.NativePlayer;
    // media_kit turns the disk cache on but gives it no directory, so mpv logs an error and keeps it in memory.
    await native.setProperty('cache-on-disk', 'no');
    final userAgent = await native.getProperty('user-agent');
    return WindowsPlayer._(player, controller, source, userAgent, muted);
  }

  static const _bufferedEvery = 5;

  final mk.Player _player;
  final VideoController _controller;
  final MpvSource _mode;
  final String _defaultUserAgent;
  final _events = StreamController<PlayerEvent>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _view = ValueNotifier<({FitMode fit, bool mirrored})>((fit: FitMode.fit, mirrored: false));
  late final Timer _ticker;

  PlayerSource? _source;
  int _generation = 0;
  bool _opening = false;
  bool _edl = false;
  bool _fellBack = false;
  bool _ready = false;
  bool _failed = false;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  PlayerStatus _status = PlayerStatus.idle;
  double _duration = 0;
  double? _position;
  double? _rate;
  (int, int)? _size;
  List<({double start, double end})> _buffered = const [];
  String? _lastError;
  double? _volumeBeforeMute;
  bool _muted;
  int _ticks = 0;
  bool _ticking = false;
  bool _disposed = false;

  mk.NativePlayer get _native => _player.platform as mk.NativePlayer;

  @override
  PlayerCapabilities get capabilities => PlayerCapabilities.none;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Widget buildView() => IgnorePointer(
        child: ValueListenableBuilder(
          valueListenable: _view,
          builder: (context, view, _) {
            final (:fit, :aspectRatio) = videoFit(view.fit);
            return Transform.flip(
              flipX: view.mirrored,
              child: Video(
                controller: _controller,
                controls: null,
                fit: fit,
                aspectRatio: aspectRatio,
                fill: BiliColors.videoBackground,
                pauseUponEnteringBackgroundMode: false,
              ),
            );
          },
        ),
      );

  @override
  Future<void> load(PlayerSource source) async {
    _check();
    _generation++;
    _source = source;
    _ready = false;
    _fellBack = false;
    _failed = false;
    _completed = false;
    _duration = 0;
    _position = null;
    _size = null;
    _lastError = null;
    _status = PlayerStatus.loading;
    _emit(const StatusChanged(PlayerStatus.loading));
    if (_buffered.isNotEmpty) {
      _buffered = const [];
      _emit(const BufferedChanged([]));
    }
    await _open(source, edl: _mode != MpvSource.hls && _hasFiles(source));
  }

  @override
  Future<void> unload() async {
    _check();
    _generation++;
    _source = null;
    _opening = false;
    _ready = false;
    _duration = 0;
    _position = null;
    _size = null;
    _lastError = null;
    _updateStatus();
    if (_buffered.isNotEmpty) {
      _buffered = const [];
      _emit(const BufferedChanged([]));
    }
    await _player.stop();
  }

  @override
  Future<void> play() async {
    _check();
    await _player.play();
  }

  @override
  Future<void> pause() async {
    _check();
    await _player.pause();
  }

  @override
  Future<void> seek(double seconds, {bool precise = false}) async {
    _check();
    // media_kit sets hr-seek=yes for every seek; a loose seek lands on a keyframe, as AVPlayer's does.
    await _native.setProperty('hr-seek', precise ? 'yes' : 'no');
    await _player.seek(_toDuration(seconds));
  }

  @override
  Future<void> setRate(double rate) async {
    _check();
    await _player.setRate(rate);
  }

  @override
  Future<void> setMuted(bool muted) async {
    _check();
    _muted = muted;
    if (muted) {
      _volumeBeforeMute ??= _player.state.volume;
      await _player.setVolume(0);
      return;
    }
    final volume = _volumeBeforeMute;
    if (volume == null) return;
    _volumeBeforeMute = null;
    await _player.setVolume(volume);
  }

  @override
  bool get muted => _muted;

  /// The PC's screen saver is the user's business.
  @override
  Future<void> setKeepAwake(bool on) async => _check();

  @override
  Future<void> setFit(FitMode fit) async {
    _check();
    _view.value = (fit: fit, mirrored: _view.value.mirrored);
  }

  @override
  Future<void> setMirrored(bool mirrored) async {
    _check();
    _view.value = (fit: _view.value.fit, mirrored: mirrored);
  }

  @override
  Future<void> startPictureInPicture() async => _check();

  @override
  Future<void> stopPictureInPicture() async => _check();

  @override
  Future<void> setAutoPictureInPicture(bool enabled) async => _check();

  @override
  Future<void> setRestorable(bool restorable) async => _check();

  @override
  Future<bool> captureFrame() async {
    _check();
    return false;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ticker.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _events.close();
    await _player.dispose();
  }

  Future<void> _open(PlayerSource source, {required bool edl}) async {
    final generation = _generation;
    _edl = edl;
    final headers = splitHeaders(source.headers);
    final start = source.startSeconds > 0 ? _toDuration(source.startSeconds) : null;
    _opening = true;
    try {
      await _native.setProperty('user-agent', headers.userAgent ?? _defaultUserAgent);
      // mpv has no unset for a string option: a load without one sends an empty Referer, which servers ignore.
      await _native.setProperty('referrer', headers.referer ?? '');
      if (generation != _generation || _disposed) return;
      _emit(PlayerLog('open', {'mode': edl ? 'edl' : 'hls'}));
      final uri = edl ? edlUrl(source.video!, source.audio!) : source.master.toString();
      await _player.open(mk.Media(uri, httpHeaders: headers.others, start: start), play: source.autoplay);
    } finally {
      if (generation == _generation) _opening = false;
    }
  }

  Future<void> _tick() async {
    if (_ticking || _disposed || _source == null) return;
    _ticking = true;
    final generation = _generation;
    try {
      _ticks++;
      await _readPosition(generation);
      if (_ticks % _bufferedEvery == 0) await _readBuffered(generation);
      if (!_ready || _ticks % _bufferedEvery == 0) await _checkStopped(generation);
    } catch (_) {
      if (!_disposed) rethrow;
    } finally {
      _ticking = false;
    }
  }

  Future<void> _readPosition(int generation) async {
    if (_opening || !_ready) return;
    var seconds = parseSeconds(await _native.getProperty('time-pos'));
    final hostMs = MonotonicClock.system.nowMs();
    if (seconds == null || generation != _generation || _disposed) return;
    if (_duration > 0 && seconds > _duration) seconds = _duration;
    final last = _position;
    if (last != null && (seconds - last).abs() < 0.0005) return;
    _position = seconds;
    _emit(PositionChanged(seconds: seconds, hostMs: hostMs, rate: _player.state.rate));
  }

  Future<void> _readBuffered(int generation) async {
    final ranges = parseSeekableRanges(await _native.getProperty('demuxer-cache-state'));
    if (generation != _generation || _disposed || sameRanges(ranges, _buffered)) return;
    _buffered = ranges;
    _emit(BufferedChanged(ranges));
  }

  /// mpv leaves the playlist (`playlist-pos` -1) when a file ends in an error; a normal end keeps it open at the
  /// last frame (`keep-open`), so -1 means the load or the playback failed.
  Future<void> _checkStopped(int generation) async {
    if (_opening || _failed || _completed || _source == null) return;
    final position = await _native.getProperty('playlist-pos');
    if (position != '-1' || generation != _generation || _opening || _disposed) return;
    final source = _source!;
    if (!_ready && !_fellBack && _mode == MpvSource.auto && _hasFiles(source)) {
      _fellBack = true;
      _emit(PlayerLog('fallback', {'from': _edl ? 'edl' : 'hls', 'to': _edl ? 'hls' : 'edl', 'reason': _lastError}));
      await _open(source, edl: !_edl);
      return;
    }
    _failed = true;
    final message = _lastError ?? (_ready ? '播放中断' : '播放失败');
    _emit(PlayerFailed(message, domain: 'mpv', formatRejected: looksLikeFormatError(message)));
  }

  void _onDuration(Duration duration) {
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0 || _source == null) return;
    if (!_ready) {
      _ready = true;
      _updateStatus();
    }
    if ((seconds - _duration).abs() < 0.0005) return;
    _duration = seconds;
    _emit(DurationChanged(seconds));
  }

  void _onRate(double rate) {
    if (rate == _rate) return;
    _rate = rate;
    _emit(RateChanged(rate));
  }

  void _onSize() {
    final width = _player.state.width, height = _player.state.height;
    if (width == null || height == null || width <= 0 || height <= 0) return;
    if (_size == (width, height)) return;
    _size = (width, height);
    _emit(SizeChanged(width: width, height: height));
  }

  void _onError(String text) {
    final message = withoutQueries(text);
    _lastError = message;
    if (_ready) _emit(PlayerLog('error', {'message': message}));
  }

  void _updateStatus() {
    final status = deriveStatus(
      loaded: _source != null,
      ready: _ready,
      completed: _completed,
      playing: _playing,
      buffering: _buffering,
    );
    if (status == _status) return;
    _status = status;
    _emit(StatusChanged(status));
  }

  void _emit(PlayerEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  static Duration _toDuration(double seconds) =>
      Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

  bool _hasFiles(PlayerSource source) => source.video != null && source.audio != null;

  void _check() {
    if (_disposed) throw StateError('player disposed');
  }
}
