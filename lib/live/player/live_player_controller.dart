import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../device/orientation.dart';
import '../../player/bili_player.dart';
import '../../player/player_factory.dart' as players;
import '../../player_ui/end_screen_portrait.dart' show ShareLink, shareThroughSystem;
import '../../player_ui/player_notes.dart';
import '../../shared/remote_image.dart' show secureImageUrl;
import '../../video/page_session.dart' show CoverFile, cachedCoverFile;
import '../../video/pip_keeper.dart';
import '../../video/player_prefs.dart';
import '../room/live_room_model.dart';
import 'live_player_prefs.dart';

/// What the player shows over its picture.
enum LivePlayerPhase {
  /// The room's play info isn't in yet, or the player is still being made: the loading TV.
  waiting,

  /// The stream is loading or catching up: the loading TV.
  loading,
  playing,
  paused,

  /// The room isn't live: the cover, dimmed, with 直播已结束.
  ended,

  /// The stream failed after its fresh ask, or after too many of them, or the play info did: 重试.
  failed,
}

/// A room's player: plays [room]'s stream on its own [BiliPlayer], follows its quality and ⟳, and owns full screen,
/// the lock, 弹 (kept between rooms), picture in picture, background sound and the lock screen.
///
/// Live goes straight to the player: no engine, no seek, no duration, no speed. A stall or a failure asks the room
/// for a fresh stream ([LiveRoomModel.refreshStream]); another before [steadyPlay] of playing, or past [freshLimit]
/// asks in [freshWindow], shows 重试, and nothing more is asked until it is pressed. Full screen is the orientation's
/// landscape while the room owns it; iOS turns the screen itself, as the official room's turn is the system's (225).
class LivePlayerController extends ChangeNotifier with WidgetsBindingObserver {
  LivePlayerController({
    required this.room,
    required this.services,
    Future<BiliPlayer> Function()? createPlayer,
    LivePlayerPrefs? prefs,
    this._playerPrefs,
    ShareLink? share,
    CoverFile? coverFile,
    this.stallLimit = const Duration(seconds: 15),
    this.awayGrace = const Duration(seconds: 1),
    Logger? logger,
  }) : _createPlayer = createPlayer ?? players.createPlayer,
       _prefs = prefs ?? LivePlayerPrefs.shared,
       _share = share ?? shareThroughSystem,
       _coverFile = coverFile ?? cachedCoverFile,
       _logger = logger ?? Logger.shared {
    services.device.orientation.addListener(_orientationChanged);
  }

  static const steadyPlay = Duration(seconds: 60);
  static const freshLimit = 3;
  static const freshWindow = Duration(minutes: 5);

  final LiveRoomModel room;
  final AppServices services;

  /// What [PipKeeper] keeps for this player while the small window plays it with no page; its own entry is never
  /// released when it plays.
  KeptPlayback? keptAs;

  /// How long the stream may load or wait for data before it counts as stalled.
  final Duration stallLimit;

  /// With 后台听视频 off, how long after the app leaves the stream is paused (the small window can report its start
  /// after the app is away).
  final Duration awayGrace;

  final Future<BiliPlayer> Function() _createPlayer;
  final LivePlayerPrefs _prefs;
  final PlayerPrefs? _playerPrefs;
  final ShareLink _share;
  final CoverFile _coverFile;
  final Logger _logger;

  /// 208's and 210's notes.
  final notices = PlayerNotes();

  PlayerPrefs get _settings => _playerPrefs ?? PlayerPrefs.shared;
  OrientationController get _orientation => services.device.orientation;

  BiliPlayer? _player;
  StreamSubscription<PlayerEvent>? _events;
  PlayerStatus _status = PlayerStatus.idle;
  bool _started = false;
  bool _disposed = false;

  /// What the user wants: playing unless they paused.
  bool _wantsPlay = true;

  /// The play info loaded on the player; a new one from the room loads again.
  LivePlayInfo? _loaded;

  /// A fresh stream was asked after a stall or failure, and none has played [steadyPlay] since.
  bool _refreshAsked = false;
  Timer? _steady;

  /// One per fresh stream a stall or failure asked in the last [freshWindow].
  final _freshAsks = <Timer>[];
  bool _refreshing = false;
  bool _failed = false;
  Timer? _stall;

  /// A quality asked from 210 whose stream hasn't played yet; '' for 自动.
  String? _pendingQuality;
  bool _autoQuality = false;

  bool _covered = false;
  bool _resumeOnShow = false;
  bool _owning = false;
  bool _pictureInPicture = false;
  bool _kept = false;
  final _restores = StreamController<void>.broadcast();

  /// The pause about to come is the controller's own.
  bool _pauseExpected = false;
  bool _background = false;
  bool _pausedAway = false;
  Timer? _awayCheck;
  bool _resumeAfterInterruption = false;

  NowPlayingInfo? _nowPlaying;
  String? _coverUrl;
  String? _coverPath;

  /// The player, once made: the view builds its picture from it.
  BiliPlayer? get player => _player;

  /// Playing or about to: ⏸ shows.
  bool get playing => _wantsPlay;

  LivePlayerPhase get phase {
    final state = room.state;
    if (state == LiveRoomState.ended) return LivePlayerPhase.ended;
    if (_failed || state == LiveRoomState.failed) return LivePlayerPhase.failed;
    if (state == LiveRoomState.loading || _player == null) return LivePlayerPhase.waiting;
    if (room.play?.url == null) return LivePlayerPhase.failed;
    if (_loaded == null || _refreshing) return LivePlayerPhase.loading;
    return switch (_status) {
      PlayerStatus.playing => LivePlayerPhase.playing,
      PlayerStatus.paused when !_wantsPlay || _covered || _pausedAway => LivePlayerPhase.paused,
      _ => LivePlayerPhase.loading,
    };
  }

  /// The quality playing, for full screen's bottom row and 210's pink row; null before the play info.
  LiveQuality? get quality {
    final play = room.play;
    if (play == null) return null;
    for (final quality in play.qualities) {
      if (quality.qn == play.currentQn) return quality;
    }
    return null;
  }

  /// 210's 自动 was the last asked.
  bool get autoQuality => _autoQuality;

  /// Full screen (209), whether turned by the button or the phone.
  bool get fullScreen => _owning && _orientation.presentation == Presentation.landscape;

  /// The controls are locked (209's 🔓).
  bool get locked => _owning && _orientation.locked;

  /// 弹: danmaku over the video.
  bool get danmakuOn => _prefs.danmakuOn;

  bool get pictureInPicture => _pictureInPicture;

  /// The small window's restore button, while no page shows this player.
  Stream<void> get restoreRequests => _restores.stream;

  /// The room offers no stream the player can play.
  bool get unsupportedStream {
    final play = room.play;
    return play != null && (play.unsupportedStream || (room.state == LiveRoomState.live && play.url == null));
  }

  /// The line over 重试.
  String get failureText => unsupportedStream ? '暂不支持该直播流' : '直播加载失败';

  /// Starts playing once [room]'s play info is in, and again whenever it changes.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    room.addListener(_roomChanged);
    WidgetsBinding.instance.addObserver(this);
    if (!_covered) _claimOrientation();
    final BiliPlayer player;
    try {
      player = await _createPlayer();
    } catch (error) {
      _logger.warn(LogCategory.player, 'live player not made', {'error': '${error.runtimeType}'});
      _failed = true;
      if (!_disposed) notifyListeners();
      return;
    }
    if (_disposed) {
      unawaited(player.dispose());
      return;
    }
    // Under --mute a player that can't be muted isn't used: it would play out loud.
    if (services.playback.muted) {
      try {
        await player.setMuted(true);
      } catch (error) {
        _logger.error(LogCategory.player, 'mute failed', {'error': '${error.runtimeType}'});
        unawaited(player.dispose());
        _failed = true;
        if (!_disposed) notifyListeners();
        return;
      }
      if (_disposed) {
        unawaited(player.dispose());
        return;
      }
    }
    _player = player;
    _events = player.events.listen(_event);
    _quietly(() => player.setBackgroundPlayback(_settings.backgroundListen), 'background playback');
    _logger.info(LogCategory.player, 'live player made', {'room': room.roomId});
    _roomChanged();
    notifyListeners();
  }

  Future<void> togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (_wantsPlay) {
      _wantsPlay = false;
      _resumeAfterInterruption = false;
      _pause(player);
    } else {
      _wantsPlay = true;
      _pausedAway = false;
      if (_loaded != null) {
        _willPlay();
        _quietly(player.play, 'play');
      }
    }
    _updateNowPlaying();
    notifyListeners();
  }

  /// ⟳: the room's stream asked again at the current quality.
  Future<void> refreshStream() async {
    _failed = false;
    _userAsked();
    await _askFresh('refresh');
  }

  /// 重试 after a failure: the play info again if that failed, else a fresh stream.
  Future<void> retry() async {
    _failed = false;
    _userAsked();
    notifyListeners();
    if (room.state == LiveRoomState.failed) {
      await room.retry();
    } else {
      await _askFresh('retry');
    }
  }

  /// 210's row: [quality], or 自动 (null), which asks the room's own default (qn 0).
  Future<void> pickQuality(LiveQuality? quality) async {
    final current = this.quality;
    if (quality != null && current?.qn == quality.qn) {
      if (!_autoQuality) return;
      // 自动 already landed on it: the room loads nothing, so there is no switch to wait for.
      if (!room.askingStream) {
        _autoQuality = false;
        notifyListeners();
        return;
      }
    }
    if (quality == null && _autoQuality) return;
    notices.add('切换中，请稍候');
    _pendingQuality = quality?.name ?? '';
    _autoQuality = quality == null;
    _failed = false;
    _userAsked();
    notifyListeners();
    try {
      await room.setQuality(quality?.qn ?? 0);
    } catch (error) {
      _logger.warn(LogCategory.player, 'live quality not switched', {'error': '${error.runtimeType}'});
      _pendingQuality = null;
      notices.add('切换失败，请稍后重试');
    }
  }

  Future<void> setFullScreen(bool on) async {
    if (_disposed) return;
    if (!_owning) _claimOrientation();
    if (on) {
      _orientation.enterLandscape();
    } else {
      _orientation.exitToInline();
    }
  }

  /// Back from full screen goes upright; true when it did, so the page stays.
  bool back() {
    if (!fullScreen) return false;
    unawaited(setFullScreen(false));
    return true;
  }

  /// While the login page is up over the room, turning the phone doesn't take the room to full screen behind it.
  void holdTurns(bool held) {
    if (_disposed) return;
    if (held) {
      _releaseOrientation();
    } else if (!_covered) {
      _claimOrientation();
    }
  }

  void setLocked(bool on) {
    if (!_owning || _orientation.locked == on) return;
    _orientation.toggleLock();
  }

  void setDanmakuOn(bool on) {
    if (on == _prefs.danmakuOn) return;
    _prefs.danmakuOn = on;
    notices.add(on ? '已开启弹幕' : '已关闭弹幕');
    notifyListeners();
  }

  /// The room's link through iOS's share sheet (221's and 222's 分享). Windows' share window freezes the app, so
  /// there it does nothing.
  Future<void> share(BuildContext context) async {
    if (Platform.isWindows && identical(_share, shareThroughSystem)) {
      _logger.info(LogCategory.ui, 'live share skipped', {'platform': Platform.operatingSystem});
      return;
    }
    try {
      await _share(Uri.parse('https://live.bilibili.com/${room.roomId}'));
    } catch (error) {
      _logger.warn(LogCategory.ui, 'live share failed', {'error': '${error.runtimeType}'});
      notices.add('分享失败');
    }
  }

  /// 小窗播放.
  Future<void> startPictureInPicture() async {
    final player = _player;
    if (player == null || _loaded == null) return;
    if (!player.capabilities.pictureInPicture) {
      notices.add('当前设备不支持小窗播放');
      return;
    }
    _quietly(player.startPictureInPicture, 'pip start');
  }

  /// Its page left while the small window plays it (true): the orientation goes and the restore button may bring a
  /// page back; false when a page took it back.
  void setKept(bool kept) {
    if (_disposed || kept == _kept) return;
    _kept = kept;
    if (kept) {
      _releaseOrientation();
    } else if (!_covered) {
      _claimOrientation();
    }
    final player = _player;
    if (player != null) _quietly(() => player.setRestorable(kept), 'restorable');
    _applyAutoPip();
  }

  /// No page will come back for the restore button: the small window ends at once.
  void refuseRestore() {
    final player = _player;
    if (player != null && !_disposed) _quietly(() => player.setRestorable(false), 'restorable');
  }

  /// The page is covered or shown (pauses and resumes as a video page does).
  void setCovered(bool covered) {
    if (covered == _covered || _disposed) return;
    _covered = covered;
    final player = _player;
    if (covered) {
      _resumeOnShow = _wantsPlay;
      _releaseOrientation();
      if (player != null) {
        _quietly(player.stopPictureInPicture, 'pip stop');
        _pause(player);
      }
      _applyAutoPip();
    } else {
      _claimOrientation();
      _applyAutoPip();
      if (_resumeOnShow && player != null && _loaded != null) {
        _willPlay();
        _quietly(player.play, 'play');
      }
      _resumeOnShow = false;
    }
    _updateNowPlaying();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final player = _player;
    // iOS reads the policy as the app leaves, and 设置 may have changed it.
    if (state == AppLifecycleState.inactive && player != null) {
      _quietly(() => player.setBackgroundPlayback(_settings.backgroundListen), 'background playback');
    }
    final background = state == AppLifecycleState.hidden || state == AppLifecycleState.paused;
    if (background == _background) return;
    _background = background;
    _awayCheck?.cancel();
    _awayCheck = null;
    if (background) {
      if (!_settings.backgroundListen) {
        _awayCheck = Timer(awayGrace, () {
          _awayCheck = null;
          if (!_background || _pictureInPicture || _disposed) return;
          // A stream still loading would start playing away from the screen once it is in.
          final player = _player;
          if (player != null && _loaded != null) {
            if (_wantsPlay) _pausedAway = true;
            _pause(player);
          }
          _updateNowPlaying();
        });
      }
    } else if (_pausedAway) {
      _pausedAway = false;
      if (_wantsPlay && !_covered && player != null && _loaded != null) {
        _willPlay();
        _quietly(player.play, 'play');
      }
    }
    _updateNowPlaying();
  }

  /// 后台听视频 off, the app away without the small window: nothing may play.
  bool get _heldAway => !_settings.backgroundListen && _background && !_pictureInPicture;

  void _roomChanged() {
    if (_disposed) return;
    final player = _player;
    switch (room.state) {
      case LiveRoomState.live:
        final play = room.play;
        if (player != null && play != null && play.url != null && !identical(play, _loaded)) _load(player, play);
      case LiveRoomState.ended:
        if (player != null && _loaded != null) {
          _loaded = null;
          _stall?.cancel();
          _quietly(player.unload, 'unload');
          _updateNowPlaying();
        }
      case LiveRoomState.loading || LiveRoomState.failed:
        break;
    }
    _updateNowPlaying();
    // The room has already changed when it notifies, so the phase before it is the one last told, not one read here.
    if (phase != _toldPhase) notifyListeners();
  }

  LivePlayerPhase? _toldPhase;

  @override
  void notifyListeners() {
    _toldPhase = phase;
    super.notifyListeners();
  }

  void _load(BiliPlayer player, LivePlayInfo play) {
    _loaded = play;
    _failed = false;
    _refreshing = false;
    _stall?.cancel();
    final autoplay = _wantsPlay && !_covered && !_heldAway;
    if (autoplay) _willPlay();
    if (_wantsPlay && _heldAway) _pausedAway = true;
    _logger.info(LogCategory.player, 'live load', {
      'room': play.roomId,
      'qn': play.currentQn,
      'autoplay': autoplay,
      'portrait': play.portrait,
    });
    _applyAutoPip();
    final source = PlayerSource(master: play.url!, headers: room.api.streamHeaders, autoplay: autoplay);
    // The error's text can carry the signed address: only its type is logged.
    unawaited(
      Future.sync(() => player.load(source)).catchError((Object error) {
        _logger.warn(LogCategory.player, 'live load failed', {'error': '${error.runtimeType}'});
        _streamFailed('load');
      }),
    );
    notifyListeners();
  }

  void _event(PlayerEvent event) {
    if (_disposed) return;
    switch (event) {
      case StatusChanged(:final status):
        _statusChanged(status);
      case PlayerFailed(:final code, :final formatRejected):
        _logger.warn(LogCategory.player, 'live stream failed', {'code': code ?? 0, 'format': formatRejected});
        _streamFailed('failed');
      case PictureInPictureChanged(:final active):
        _pictureInPicture = active;
        _updateNowPlaying();
        notifyListeners();
      case PictureInPictureRestore():
        _restores.add(null);
      case RemoteCommand(:final kind):
        _remoteCommand(kind);
      case AudioInterruption(:final began, :final shouldResume):
        _interrupted(began: began, shouldResume: shouldResume);
      case PlayerLog(:final kind, :final fields):
        _logger.info(LogCategory.player, 'live $kind', fields.map((key, value) => MapEntry(key, value ?? '')));
      default:
        break;
    }
  }

  void _statusChanged(PlayerStatus status) {
    final was = _status;
    _status = status;
    if (status != PlayerStatus.playing) {
      _steady?.cancel();
      _steady = null;
    }
    switch (status) {
      case PlayerStatus.playing:
        _stall?.cancel();
        _refreshing = false;
        // Past the away check (its grace lets the small window start), nothing may play.
        if (_heldAway && _awayCheck == null) {
          if (_wantsPlay) _pausedAway = true;
          final player = _player;
          if (player != null) _pause(player);
          break;
        }
        // A fresh stream that plays and fails again at once gets no second one.
        if (_refreshAsked) {
          _steady ??= Timer(steadyPlay, () {
            _steady = null;
            _refreshAsked = false;
          });
        }
        _pausedAway = false;
        if (!_wantsPlay && !_covered) _wantsPlay = true;
        if (_pendingQuality != null) {
          _pendingQuality = null;
          if (quality case final current?) notices.add('已成功切换至${_shortName(current.name)}');
        }
        _applyAutoPip();
      case PlayerStatus.loading || PlayerStatus.buffering:
        if (_loaded != null && _wantsPlay && !_covered && !_heldAway) _watchStall();
      case PlayerStatus.paused:
        _stall?.cancel();
        if (_pauseExpected) {
          _pauseExpected = false;
        } else if (was == PlayerStatus.playing && !_background && !_covered) {
          // Paused by something other than the page (the small window's own button, AVKit): the page follows.
          _wantsPlay = false;
        } else if (was == PlayerStatus.playing && _pictureInPicture) {
          _wantsPlay = false;
        }
      case PlayerStatus.ended:
        // A live playlist that ends is a stream gone stale, or the room ending; the room's next play info says which.
        _streamFailed('ended');
      case PlayerStatus.idle:
        _stall?.cancel();
    }
    _updateNowPlaying(again: status == PlayerStatus.playing && was != PlayerStatus.playing);
    notifyListeners();
  }

  void _watchStall() {
    if (_stall?.isActive ?? false) return;
    _stall = Timer(stallLimit, () => _streamFailed('stall'));
  }

  /// A stall or failure asks a fresh stream, unless the last fresh one hasn't played [steadyPlay] or [freshLimit] were
  /// asked in [freshWindow]: then 重试.
  void _streamFailed(String reason) {
    _stall?.cancel();
    _steady?.cancel();
    _steady = null;
    if (_disposed || _loaded == null) return;
    final capped = _freshAsks.length >= freshLimit;
    _logger.warn(LogCategory.player, 'live stream stopped', {
      'reason': reason,
      'refreshed': _refreshAsked,
      'recent': _freshAsks.length,
    });
    if (_refreshAsked || capped) {
      _failed = true;
      _refreshing = false;
      _pendingQuality = null;
      final player = _player;
      if (player != null) _quietly(player.unload, 'unload');
      _loaded = null;
      _updateNowPlaying();
      notifyListeners();
      return;
    }
    _refreshAsked = true;
    late final Timer ask;
    ask = Timer(freshWindow, () => _freshAsks.remove(ask));
    _freshAsks.add(ask);
    _refreshing = true;
    notifyListeners();
    // Out of the player's event, which the new load's own events would otherwise land inside.
    scheduleMicrotask(() {
      if (!_disposed) unawaited(_askFresh(reason));
    });
  }

  Future<void> _askFresh(String reason) async {
    _refreshing = true;
    final before = _loaded;
    notifyListeners();
    try {
      await room.refreshStream();
    } catch (error) {
      _logger.warn(LogCategory.player, 'live refresh failed', {'reason': reason, 'error': '${error.runtimeType}'});
      if (_disposed) return;
      _refreshing = false;
      _failed = true;
      notifyListeners();
      return;
    }
    if (_disposed) return;
    // The same play info back loaded nothing new: it plays again.
    final play = room.play;
    final player = _player;
    if (identical(_loaded, before) &&
        player != null &&
        play != null &&
        play.url != null &&
        room.state == LiveRoomState.live) {
      _load(player, play);
    }
    _refreshing = false;
    notifyListeners();
  }

  void _remoteCommand(RemoteCommandKind kind) {
    if (_nowPlaying == null) return;
    final plays = switch (kind) {
      RemoteCommandKind.play => true,
      RemoteCommandKind.toggle => !_wantsPlay,
      _ => false,
    };
    if (_covered || (plays && _heldAway)) {
      _logger.info(LogCategory.ui, 'remote command ignored', {'kind': kind.name, 'covered': _covered});
      return;
    }
    switch (kind) {
      case RemoteCommandKind.play:
        if (!_wantsPlay) unawaited(togglePlay());
      case RemoteCommandKind.pause:
        if (_wantsPlay) unawaited(togglePlay());
      case RemoteCommandKind.toggle:
        unawaited(togglePlay());
      // Live has no timeline and nothing before or after.
      case RemoteCommandKind.seek || RemoteCommandKind.next || RemoteCommandKind.previous:
        break;
    }
  }

  void _interrupted({required bool began, required bool shouldResume}) {
    if (began) {
      _resumeAfterInterruption = _wantsPlay;
      if (_wantsPlay) _pauseExpected = true;
      return;
    }
    final resume = _resumeAfterInterruption && shouldResume && !_covered && !_heldAway;
    _resumeAfterInterruption = false;
    final player = _player;
    if (resume && player != null) {
      _logger.info(LogCategory.player, 'live resumed after the interruption');
      _quietly(player.play, 'play');
    }
  }

  void _pause(BiliPlayer player) {
    _stall?.cancel();
    if (_status == PlayerStatus.playing || _status == PlayerStatus.buffering) _pauseExpected = true;
    _quietly(player.pause, 'pause');
  }

  /// ⟳, 重试 or a quality: the fresh asks start over.
  void _userAsked() {
    _refreshAsked = false;
    _steady?.cancel();
    _steady = null;
    for (final ask in _freshAsks) {
      ask.cancel();
    }
    _freshAsks.clear();
  }

  /// One video at a time: another closed page kept for the small window lets go first.
  void _willPlay() {
    final keeper = services.pipKeeper;
    final kept = keeper.kept;
    if (kept != null && !identical(kept, keptAs)) keeper.release();
  }

  void _applyAutoPip() {
    final player = _player;
    if (player == null || !player.capabilities.pictureInPicture) return;
    final on = !_covered && !_kept && _settings.autoPip && _loaded != null;
    _quietly(() => player.setAutoPictureInPicture(on), 'auto pip');
  }

  void _claimOrientation() {
    if (_owning) return;
    _owning = true;
    final orientation = _orientation;
    // The official room's turn is iOS's own (225), so the drawn turn (开发者 → 旋转动画) stays off while it owns the
    // orientation; nothing here would draw it.
    unawaited(orientation.setTurnTakeover(false));
    orientation.begin(this, videoIsVertical: false);
  }

  void _releaseOrientation() {
    if (!_owning) return;
    _owning = false;
    final orientation = _orientation;
    orientation.end(this);
    unawaited(orientation.setTurnTakeover(_settings.turnTakeover));
  }

  void _orientationChanged() {
    if (_owning && !_disposed) notifyListeners();
  }

  /// The lock screen is the room's while it plays on the page shown, off while covered or held away.
  void _updateNowPlaying({bool again = false}) {
    final player = _player;
    if (player == null || _disposed) return;
    final holds = _loaded != null && !_covered && (_wantsPlay || _nowPlaying != null) && !_heldAway;
    final info = holds ? _nowPlayingInfo() : null;
    if (info == _nowPlaying && !(again && info != null)) return;
    if (info == null && _nowPlaying == null) return;
    _nowPlaying = info;
    _quietly(() => player.setNowPlaying(info), 'now playing');
  }

  NowPlayingInfo _nowPlayingInfo() {
    final info = room.info;
    final title = info?.title ?? '';
    final anchor = info?.anchorName ?? '';
    return NowPlayingInfo(
      title: title.isEmpty ? room.entry.title : title,
      artist: anchor.isEmpty ? room.entry.anchorName : anchor,
      artworkPath: _cover(info?.cover ?? '', room.entry.cover),
    );
  }

  String? _cover(String cover, String fallback) {
    final picked = cover.isEmpty ? fallback : cover;
    if (picked.isEmpty) return null;
    final url = secureImageUrl(picked);
    if (url == _coverUrl) return _coverPath;
    _coverUrl = url;
    _coverPath = null;
    unawaited(_fetchCover(url));
    return null;
  }

  Future<void> _fetchCover(String url) async {
    String? path;
    try {
      path = await _coverFile(url);
    } catch (error) {
      _logger.info(LogCategory.ui, 'live now playing cover missing', {'error': '${error.runtimeType}'});
    }
    if (_disposed || _coverUrl != url || path == null) return;
    _coverPath = path;
    _updateNowPlaying();
  }

  /// 210 picks 1080P 原画 (高帧率) and says 已成功切换至1080P 原画.
  static String _shortName(String name) => name.replaceFirst(RegExp(r'\s*[(（][^)）]*[)）]\s*$'), '');

  void _quietly(Future<void> Function() action, String what) {
    unawaited(
      Future.sync(action).catchError((Object error) {
        _logger.warn(LogCategory.player, 'live $what failed', {'error': '${error.runtimeType}'});
      }),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stall?.cancel();
    _steady?.cancel();
    for (final ask in _freshAsks) {
      ask.cancel();
    }
    _freshAsks.clear();
    _awayCheck?.cancel();
    unawaited(_restores.close());
    services.device.orientation.removeListener(_orientationChanged);
    if (_started) {
      room.removeListener(_roomChanged);
      WidgetsBinding.instance.removeObserver(this);
    }
    _releaseOrientation();
    unawaited(_events?.cancel());
    final player = _player;
    _player = null;
    if (player != null) {
      if (_nowPlaying != null) _quietly(() => player.setNowPlaying(null), 'now playing');
      _quietly(player.dispose, 'dispose');
    }
    notices.dispose();
    super.dispose();
  }
}
