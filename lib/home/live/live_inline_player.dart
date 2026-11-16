import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../live/live_api.dart';
import '../../live/live_entry.dart';
import '../../live/room/live_room_model.dart';
import '../../player/bili_player.dart';
import '../../player/player_factory.dart' as players;
import '../../shared/theme.dart';
import '../feed_inline_player.dart' show FeedInlineChoices;

/// The carousel card's stream, played muted on a player of its own while [FeedInlineHost] picks the card: a
/// [LiveRoomModel] asks the stream and feeds the danmaku over it, its socket open only while the card plays with 弹 on.
/// Paused (or the app away) it keeps both for [FeedBigCardTheme.releaseAfter]; back within
/// [LiveTabTheme.resumeReloadAfter] it plays on, later it asks the stream again from the live edge. A player failure or
/// a [stallLimit] without a picture asks a fresh stream once; after that the card shows its cover until released.
class LiveInlinePlayback extends ChangeNotifier with WidgetsBindingObserver {
  LiveInlinePlayback({
    required this._services,
    required this._api,
    required this.entry,
    required this._loggedIn,
    DateTime Function()? now,
    Logger? logger,
  }) : _now = now ?? DateTime.now,
       _logger = logger ?? Logger.shared {
    FeedInlineChoices.sound.addListener(_applySound);
    FeedInlineChoices.danmaku.addListener(_syncRoom);
    WidgetsBinding.instance.addObserver(this);
    _away = _isAway(WidgetsBinding.instance.lifecycleState);
  }

  /// Makes the card's player; tests hand out fakes.
  @visibleForTesting
  static Future<BiliPlayer> Function() createPlayer = players.createPlayer;

  static const stallLimit = Duration(seconds: 15);

  final AppServices _services;
  final LiveApi _api;
  final LiveRoomEntry entry;
  final bool Function() _loggedIn;
  final DateTime Function() _now;
  final Logger _logger;

  LiveRoomModel? _room;
  BiliPlayer? _player;
  Future<void>? _creating;
  StreamSubscription<PlayerEvent>? _events;
  Uri? _loaded;
  Timer? _release;
  DateTime? _pausedAt;
  bool _wanted = false;
  bool _playing = false;
  bool _failed = false;
  bool _disposed = false;
  bool _away = false;
  PlayerStatus? _status;
  Timer? _stall;

  /// The one fresh stream a failure or a stall may ask for until released.
  bool _recovered = false;

  /// Asked to play, whether it does yet or is loading.
  bool get wanted => _wanted;

  /// The room the card plays, for the danmaku over it; null while it holds none.
  LiveRoomModel? get room => _room;
  BiliPlayer? get player => _player;

  /// The picture has played since its stream was loaded, so it shows over the cover.
  bool get shown => _playing && _player != null;

  /// The loading TV: asked to play and not yet showing a picture.
  bool get loading => _wanted && !_failed && !shown;

  /// The room isn't live, its stream didn't come or the player refused it: the cover again.
  bool get failed => _failed;

  void play() {
    if (_disposed) return;
    if (_wanted) {
      if (!_away) _cancelRelease();
      return;
    }
    _wanted = true;
    _room ??= _makeRoom();
    if (!_away) _resume();
    _syncRoom();
    _changed();
  }

  void pause() {
    if (!_wanted || _disposed) return;
    _wanted = false;
    if (!_away) _hold();
    _syncRoom();
    _changed();
  }

  /// Stops and frees the player and the room; a later play starts afresh.
  void release() {
    _cancelRelease();
    _stall?.cancel();
    _stall = null;
    _wanted = false;
    _pausedAt = null;
    _recovered = false;
    final hadAny = _player != null || _room != null;
    _dropPlayer();
    final room = _room;
    _room = null;
    if (room != null) {
      room
        ..removeListener(_roomChanged)
        ..setShown(false)
        ..dispose();
    }
    _failed = false;
    if (hadAny) _logger.info(LogCategory.player, 'live inline released', {'room': entry.roomId});
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = _isAway(state);
    if (away == _away || _disposed) return;
    _away = away;
    if (_wanted) away ? _hold() : _resume();
    _syncRoom();
    _changed();
  }

  static bool _isAway(AppLifecycleState? state) =>
      state == AppLifecycleState.hidden || state == AppLifecycleState.paused;

  /// Plays on where it was held, or from the live edge after [LiveTabTheme.resumeReloadAfter].
  void _resume() {
    _cancelRelease();
    final player = _player;
    if (player == null) {
      _creating ??= _create();
    } else {
      final pausedAt = _pausedAt;
      final stale = pausedAt != null && _now().difference(pausedAt) >= LiveTabTheme.resumeReloadAfter;
      if (stale) {
        _loaded = null;
        _load();
      } else if (_loaded != null) {
        _quietly(player.play, 'play');
      }
    }
    _pausedAt = null;
    _watchStall();
  }

  void _hold() {
    _pausedAt = _now();
    _stall?.cancel();
    _stall = null;
    if (_player case final player?) _quietly(player.pause, 'pause');
    _release ??= Timer(FeedBigCardTheme.releaseAfter, release);
  }

  void _cancelRelease() {
    _release?.cancel();
    _release = null;
  }

  /// The room's socket follows the card playing with 弹 on; the model closes it after its grace.
  void _syncRoom() => _room?.setShown(_wanted && !_away && FeedInlineChoices.danmaku.value);

  LiveRoomModel _makeRoom() {
    _logger.info(LogCategory.player, 'live inline start', {'room': entry.roomId});
    final room = LiveRoomModel(api: _api, entry: entry, loggedIn: _loggedIn, inline: true)..addListener(_roomChanged);
    unawaited(
      room.start().catchError((Object error) {
        _logger.warn(LogCategory.player, 'live inline room failed', {'error': '${error.runtimeType}'});
      }),
    );
    return room;
  }

  Future<void> _create() async {
    try {
      final player = await createPlayer();
      if (_disposed || _room == null) {
        unawaited(player.dispose());
        return;
      }
      _player = player;
      _events = player.events.listen(_event);
      _applySound();
      _load();
      _changed();
    } catch (error) {
      _logger.warn(LogCategory.player, 'live inline player failed', {'error': '${error.runtimeType}'});
      _failed = true;
      _changed();
    } finally {
      _creating = null;
    }
  }

  void _roomChanged() {
    final room = _room;
    if (room == null) return;
    if (room.state == LiveRoomState.ended || room.state == LiveRoomState.failed) {
      if (!_failed) _fail();
      return;
    }
    _load();
  }

  /// The room's stream once both it and the player are in, and again when it changes. The address is signed: it is
  /// never logged.
  void _load() {
    final player = _player;
    final url = _room?.play?.url;
    if (player == null || url == null || url == _loaded) return;
    _loaded = url;
    _playing = false;
    _failed = false;
    _status = null;
    _quietly(
      () => player.load(PlayerSource(master: url, headers: _api.streamHeaders, autoplay: _wanted && !_away)),
      'load',
    );
    _watchStall();
    _changed();
  }

  void _event(PlayerEvent event) {
    switch (event) {
      case StatusChanged(:final status):
        _status = status;
        if (status == PlayerStatus.playing && !_playing) {
          _playing = true;
          _changed();
        }
        _watchStall();
      case PlayerFailed(:final message):
        _logger.warn(LogCategory.player, 'live inline failed', {'error': message});
        _recover('failed');
      default:
    }
  }

  /// Times a stream that is loaded and wanted but not playing.
  void _watchStall() {
    final stalled = _wanted && !_away && !_failed && _loaded != null && _status != PlayerStatus.playing;
    if (!stalled) {
      _stall?.cancel();
      _stall = null;
      return;
    }
    _stall ??= Timer(stallLimit, () {
      _stall = null;
      _recover('stall');
    });
  }

  /// A fresh play info once, the stream loaded again from it; a second failure leaves the cover.
  void _recover(String reason) {
    _stall?.cancel();
    _stall = null;
    final room = _room;
    if (_disposed || room == null || _failed) return;
    if (_recovered) {
      _fail();
      return;
    }
    _recovered = true;
    _logger.info(LogCategory.player, 'live inline fresh stream', {'room': entry.roomId, 'reason': reason});
    _loaded = null;
    _playing = false;
    unawaited(
      room.refreshStream().then(
        (_) {
          if (identical(room, _room)) _load();
        },
        onError: (Object error) {
          if (identical(room, _room)) _fail();
        },
      ),
    );
    _changed();
  }

  void _fail() {
    _stall?.cancel();
    _stall = null;
    _failed = true;
    _changed();
  }

  void _applySound() {
    final player = _player;
    if (player == null) return;
    final muted = !FeedInlineChoices.sound.value || _services.playback.muted;
    _quietly(() => player.setMuted(muted), 'mute');
  }

  void _dropPlayer() {
    unawaited(_events?.cancel());
    _events = null;
    final player = _player;
    _player = null;
    _loaded = null;
    _playing = false;
    _status = null;
    if (player != null) _quietly(player.dispose, 'dispose');
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    release();
    _disposed = true;
    FeedInlineChoices.sound.removeListener(_applySound);
    FeedInlineChoices.danmaku.removeListener(_syncRoom);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _quietly(Future<void> Function() action, String what) {
    unawaited(
      Future.sync(action).catchError((Object error) {
        _logger.warn(LogCategory.player, 'live inline $what failed', {'error': '${error.runtimeType}'});
      }),
    );
  }
}
