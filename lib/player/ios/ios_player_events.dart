import 'package:bili_core/shared.dart';
import 'package:flutter/services.dart';

import '../bili_player.dart';
import 'player_api.g.dart';

/// The native players' events, routed to each IosPlayer by id. Positions get the host clock time on arrival,
/// which danmaku extrapolates from.
final class IosPlayerEvents implements PlayerEventApi {
  IosPlayerEvents({MonotonicClock? clock}) : _clock = clock ?? MonotonicClock.system;

  static IosPlayerEvents? _shared;

  /// The hub the native side calls, registered on first use.
  static IosPlayerEvents get shared => _shared ??= IosPlayerEvents()..connect();

  final MonotonicClock _clock;
  final _sinks = <int, void Function(PlayerEvent event)>{};

  void connect({BinaryMessenger? binaryMessenger}) => PlayerEventApi.setUp(this, binaryMessenger: binaryMessenger);

  void attach(int playerId, void Function(PlayerEvent event) sink) => _sinks[playerId] = sink;

  void detach(int playerId) => _sinks.remove(playerId);

  void _emit(int playerId, PlayerEvent event) => _sinks[playerId]?.call(event);

  @override
  Future<void> onPosition(int playerId, double seconds, double rate) async =>
      _emit(playerId, PositionChanged(seconds: seconds, hostMs: _clock.nowMs(), rate: rate));

  @override
  Future<void> onDuration(int playerId, double seconds) async => _emit(playerId, DurationChanged(seconds));

  @override
  Future<void> onBuffered(int playerId, List<NativeTimeRange> ranges) async =>
      _emit(playerId, BufferedChanged([for (final range in ranges) (start: range.start, end: range.end)]));

  @override
  Future<void> onStatus(int playerId, NativePlayerStatus status) async =>
      _emit(playerId, StatusChanged(_status(status)));

  @override
  Future<void> onRate(int playerId, double rate) async => _emit(playerId, RateChanged(rate));

  @override
  Future<void> onSize(int playerId, int width, int height) async =>
      _emit(playerId, SizeChanged(width: width, height: height));

  @override
  Future<void> onFailure(int playerId, String message, String? domain, int? code, bool formatRejected) async =>
      _emit(playerId, PlayerFailed(message, domain: domain, code: code, formatRejected: formatRejected));

  @override
  Future<void> onPictureInPicture(int playerId, bool active) async =>
      _emit(playerId, PictureInPictureChanged(active));

  @override
  Future<void> onPictureInPictureRestore(int playerId) async => _emit(playerId, const PictureInPictureRestore());

  @override
  Future<void> onLog(int playerId, String kind, Map<String, Object?> fields) async =>
      _emit(playerId, PlayerLog(kind, fields));

  static PlayerStatus _status(NativePlayerStatus status) => switch (status) {
        NativePlayerStatus.idle => PlayerStatus.idle,
        NativePlayerStatus.loading => PlayerStatus.loading,
        NativePlayerStatus.buffering => PlayerStatus.buffering,
        NativePlayerStatus.playing => PlayerStatus.playing,
        NativePlayerStatus.paused => PlayerStatus.paused,
        NativePlayerStatus.ended => PlayerStatus.ended,
      };
}
