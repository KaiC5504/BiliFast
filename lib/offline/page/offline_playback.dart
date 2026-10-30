import 'dart:async';

import 'package:bili_core/api.dart' show VideoPage, VideoView;
import 'package:bili_core/logic.dart' show ResumePoint;
import 'package:flutter/foundation.dart';

import '../../app/app_scope.dart';
import '../../playback/playback_controller.dart';
import '../../player/bili_player.dart';
import '../../video/page_session.dart' show SessionOpen, SessionPlaylist, createPageSession;
import '../../video/player_session.dart' show Episode, PlayerSession;
import '../offline_library.dart';
import '../offline_models.dart';

/// The session of an offline page: the page's own, over the library's finished parts.
PlayerSession offlinePageSession({
  required PlaybackController controller,
  required AppServices services,
  required SessionOpen open,
  required void Function(double seconds) onSeeked,
  required VoidCallback requestLogin,
  required VoidCallback willPlay,
}) => createPageSession(
  controller: controller,
  services: services,
  open: open,
  onSeeked: onSeeked,
  requestLogin: requestLogin,
  willPlay: willPlay,
  playlist: OfflinePlaylist(services.offline),
);

/// What the controller plays of a finished part: the page shows the title, uploader and part it was cached with.
LocalVideo localVideoOf(OfflinePlayback playback) {
  final request = playback.item.request;
  final page = VideoPage(
    cid: request.cid,
    page: request.page,
    part: request.partTitle ?? '',
    duration: request.duration,
  );
  return LocalVideo(
    view: VideoView(
      bvid: request.bvid,
      aid: request.aid,
      title: request.title,
      owner: request.ownerName,
      pages: [page],
    ),
    page: page,
    files: playback.files,
    qualityName: playback.item.qualityName,
    danmakuFolder: playback.danmakuFolder,
    danmakuSegments: playback.danmakuSegments,
  );
}

/// Where a cached part starts: where the library saw it stop, or from 0 within 5 s of the end, as the online page
/// resumes (ResumePoint).
double offlineStart(OfflineItem? item) {
  if (item == null) return 0;
  return ResumePoint.start(
    lastPlayTimeMs: (item.position * 1000).round(),
    lastPlayCid: item.cid,
    cid: item.cid,
    duration: item.request.duration.toDouble(),
  );
}

/// The finished parts, newest first as 离线缓存 lists them: an offline page's 选集, ⏭ and 自动连播. It notifies only
/// when the list itself changes, not for every download's progress.
class OfflinePlaylist extends ChangeNotifier implements SessionPlaylist {
  OfflinePlaylist(this._library) : _episodes = _of(_library) {
    _library.addListener(_changed);
  }

  final OfflineLibrary _library;
  List<Episode> _episodes;

  @override
  List<Episode> get episodes => _episodes;

  static List<Episode> _of(OfflineLibrary library) => [
    for (final item in library.items)
      if (item.isDone)
        Episode(
          bvid: item.request.bvid,
          cid: item.cid,
          title: item.request.title,
          current: false,
          duration: item.request.duration > 0 ? item.request.duration : null,
        ),
  ];

  void _changed() {
    final next = _of(_library);
    if (listEquals(next, _episodes)) return;
    _episodes = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _library.removeListener(_changed);
    super.dispose();
  }
}

/// Keeps where a cached part stopped in the library, for its next open and 离线缓存's progress (145): every [step]
/// seconds played, on a pause, after a seek, at the end (its whole length) and when the page leaves. It belongs to the
/// open made just before it, as WatchReporter does, and tells nobody else: an offline page reports no history.
class OfflineProgress {
  OfflineProgress({required PlaybackController controller, required this._library})
    : _controller = controller,
      _open = controller.opens {
    // After the controller's own subscription, so its phase already reflects each event.
    _events = controller.player.events.listen(_onEvent);
  }

  static const step = 10.0;

  final PlaybackController _controller;
  final OfflineLibrary _library;
  final int _open;
  late final StreamSubscription<PlayerEvent> _events;

  int? _cid;
  bool _started = false;
  bool _finished = false;
  bool _left = false;
  double _saved = 0;

  /// The position at this open's last event, for a leave after a newer open has moved the controller on.
  double _position = 0;
  PlayerStatus _status = PlayerStatus.idle;

  bool get _isCurrent => _controller.opens == _open;

  void _onEvent(PlayerEvent event) {
    if (!_isCurrent || !_controller.isLocal) return;
    final cid = _controller.page?.cid;
    if (cid == null) return;
    _cid = cid;
    _position = _controller.currentSeconds;
    switch (event) {
      case StatusChanged(:final status):
        _status = status;
        // Statuses while a load starts are the player's, not the viewer's.
        if (_controller.phase != PlaybackPhase.playing) return;
        switch (status) {
          case PlayerStatus.playing when !_started:
            _started = true;
            _saved = _position;
          case PlayerStatus.playing:
            _finished = false;
          case PlayerStatus.paused when _started && !_finished:
            _save(_position);
          case PlayerStatus.ended when _started:
            _finished = true;
            _save(_length());
          default:
            break;
        }
      case PositionChanged(:final seconds):
        if (!_started || _finished || _status != PlayerStatus.playing) return;
        if ((seconds - _saved).abs() >= step) _save(seconds);
      default:
        break;
    }
  }

  /// A seek the user made on the page, kept at the position asked for.
  void seeked(double seconds) {
    if (!_isCurrent || !_started || _left) return;
    _finished = false;
    _save(seconds);
  }

  /// The page is going, or another part opens: the last position is kept.
  void leave() {
    if (_left) return;
    _left = true;
    if (_started && !_finished) _save(_isCurrent ? _controller.currentSeconds : _position);
    unawaited(_events.cancel());
  }

  double _length() {
    final player = _controller.duration.value;
    return player > 0 ? player : (_controller.page?.duration ?? 0).toDouble();
  }

  void _save(double seconds) {
    final cid = _cid;
    if (cid == null) return;
    _saved = seconds;
    _library.savePosition(cid, seconds);
  }
}
