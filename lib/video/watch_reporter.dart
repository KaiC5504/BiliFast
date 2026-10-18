import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/logic.dart';

import '../playback/playback_controller.dart';
import '../player/bili_player.dart';

/// Tells Bilibili how far the video page got, so it shows in the official app's 历史记录 and the next open resumes
/// there (VideoPageModel.swift's heartbeats): once playback starts, every 15 s of playing, on pause, after a seek, at
/// the end (-1) and when the page goes. Logged in only. The speed test plays without one, so it reports nothing.
class WatchReporter {
  WatchReporter({
    required PlaybackController controller,
    required this._client,
    required this._loggedIn,
    Logger? logger,
  }) : _controller = controller,
       _logger = logger ?? Logger.shared {
    // After the controller's own subscription, so its phase already reflects each event.
    _events = controller.player.events.listen(_onEvent);
  }

  final PlaybackController _controller;
  final BiliClient _client;
  final bool Function() _loggedIn;
  final Logger _logger;
  late final StreamSubscription<PlayerEvent> _events;

  ({String bvid, int cid})? _item;
  HeartbeatSchedule _schedule = HeartbeatSchedule();
  bool _started = false;

  /// The finished heartbeat went out; a later mark at the end position would overwrite it.
  bool _finishedSent = false;
  PlayerStatus _status = PlayerStatus.idle;
  Future<void> _sending = Future.value();
  bool _left = false;

  void _onEvent(PlayerEvent event) {
    final item = _current();
    if (item == null) return;
    if (item != _item) {
      _item = item;
      _schedule = HeartbeatSchedule();
      _started = false;
      _finishedSent = false;
    }
    switch (event) {
      case StatusChanged(:final status):
        _status = status;
        if (_controller.phase != PlaybackPhase.playing) return;
        switch (status) {
          case PlayerStatus.playing when !_started:
            _started = true;
            _mark(item);
          case PlayerStatus.paused when _started && !_finishedSent:
            _mark(item);
          case PlayerStatus.ended when _started:
            _finishedSent = true;
            _send(item, HeartbeatSchedule.finished);
          default:
            break;
        }
      case PositionChanged(:final seconds):
        if (!_started || _finishedSent) return;
        final played = _schedule.tick(position: seconds, playing: _status == PlayerStatus.playing);
        if (played != null) _send(item, played);
      default:
        break;
    }
  }

  /// A seek the user made on the page; reported at where it lands.
  void seeked(double seconds) {
    final item = _current();
    if (item == null || item != _item || !_started) return;
    _finishedSent = false;
    _send(item, _schedule.mark(position: seconds));
  }

  /// The page is going: the last position goes out, and the reports sent so far are awaited.
  Future<void> leave() {
    if (_left) return _sending;
    _left = true;
    final item = _current();
    if (item != null && item == _item && _started && !_finishedSent) _mark(item);
    unawaited(_events.cancel());
    return _sending;
  }

  ({String bvid, int cid})? _current() {
    final video = _controller.video;
    final page = _controller.page;
    return video == null || page == null ? null : (bvid: video.bvid, cid: page.cid);
  }

  void _mark(({String bvid, int cid}) item) => _send(item, _schedule.mark(position: _controller.currentSeconds));

  /// One after another, so a late answer never reorders the history Bilibili keeps.
  void _send(({String bvid, int cid}) item, int played) {
    if (!_loggedIn()) return;
    _sending = _sending.then((_) async {
      try {
        await _client.heartbeat(bvid: item.bvid, cid: item.cid, playedTime: played);
      } catch (error) {
        _logger.warn(LogCategory.api, 'heartbeat failed', {'played': played, 'error': '$error'});
      }
    });
  }
}
