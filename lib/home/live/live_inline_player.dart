import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../app/app_scope.dart';
import '../../live/live_api.dart';
import '../../live/live_entry.dart';
import '../../live/room/live_room_model.dart';
import '../../player/bili_player.dart';
import '../../player/player_factory.dart' as players;
import '../../shared/theme.dart';
import '../feed_inline_player.dart' show FeedInlineChoices;

/// The carousel card's stream, played muted on a player of its own while [FeedInlineHost] picks the card: a
/// [LiveRoomModel] asks the stream and feeds the danmaku over it, and is shown only while the card plays. Paused it keeps
/// both for [FeedBigCardTheme.releaseAfter]; back within [LiveTabTheme.resumeReloadAfter] it plays on, later it asks the
/// stream again from the live edge.
class LiveInlinePlayback extends ChangeNotifier {
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
  }

  /// Makes the card's player; tests hand out fakes.
  @visibleForTesting
  static Future<BiliPlayer> Function() createPlayer = players.createPlayer;

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
    _release?.cancel();
    _release = null;
    if (_wanted || _disposed) return;
    _wanted = true;
    final room = _room ??= _makeRoom();
    room.setShown(true);
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
    _changed();
  }

  void pause() {
    if (!_wanted || _disposed) return;
    _wanted = false;
    _pausedAt = _now();
    if (_player case final player?) _quietly(player.pause, 'pause');
    _room?.setShown(false);
    _release = Timer(FeedBigCardTheme.releaseAfter, release);
    _changed();
  }

  /// Stops and frees the player and the room; a later play starts afresh.
  void release() {
    _release?.cancel();
    _release = null;
    _wanted = false;
    _pausedAt = null;
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

  LiveRoomModel _makeRoom() {
    _logger.info(LogCategory.player, 'live inline start', {'room': entry.roomId});
    final room = LiveRoomModel(api: _api, entry: entry, loggedIn: _loggedIn, reportsEntry: false)..addListener(_roomChanged);
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
      if (!_failed) {
        _failed = true;
        _changed();
      }
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
    _quietly(() => player.load(PlayerSource(master: url, headers: _api.streamHeaders, autoplay: _wanted)), 'load');
    _changed();
  }

  void _event(PlayerEvent event) {
    switch (event) {
      case StatusChanged(:final status):
        final playing = status == PlayerStatus.playing;
        if (playing && !_playing) {
          _playing = true;
          _changed();
        }
      case PlayerFailed(:final message):
        _logger.warn(LogCategory.player, 'live inline failed', {'error': message});
        _failed = true;
        _changed();
      default:
    }
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
