import 'dart:ui' show Size;

import 'package:bili_core/devlog.dart';

import '../device/orientation.dart';
import '../device/orientation_host.dart';

/// The video page's side of a drawn turn for the phone's log (docs/reference/turn-log.md), to set against the native
/// side's `turn native …` lines. One per page.
class TurnRecorder {
  TurnRecorder({Logger? logger, DateTime Function()? now})
      : _logger = logger ?? Logger.shared,
        _now = now ?? DateTime.now;

  final Logger _logger;
  final DateTime Function() _now;

  /// The presentation changed: a turn may follow. [drawn] is the 开发者 choice, 自绘 or 系统.
  void presentation(
    Presentation from,
    Presentation to, {
    required bool wide,
    required bool waiting,
    required bool drawn,
  }) =>
      _event('presentation', {
        'from': from.name,
        'to': to.name,
        'wide': wide,
        'waiting': waiting,
        'style': drawn ? '自绘' : '系统',
      });

  /// The host started [start]; [outcome] is `pending` (the turn the page waits for), `stale` (the other way, or
  /// overtaken) or `unasked` (none was waited for).
  void started(TurnStart start, {required String outcome}) => _event('started', {
        'turn': start.id,
        'angle': start.angle,
        'ms': start.duration.inMicroseconds / 1000,
        'outcome': outcome,
      });

  /// The first build at a new screen shape.
  void sized(Size size, {required Presentation layout}) =>
      _event('sized', {'w': size.width, 'h': size.height, 'layout': layout.name});

  /// The page started drawing [turn]: from [spinFrom] radians back to 0 over [duration], the player box from [grow].
  void began(int turn, {required double spinFrom, required Duration duration, required double grow}) =>
      _event('began', {
        'turn': turn,
        'spinFrom': spinFrom,
        'ms': duration.inMicroseconds / 1000,
        'grow': grow,
      });

  void drawnSent(int turn) => _event('drawn sent', {'turn': turn});

  /// The wait for a turn ran out; [missed] when none came at all.
  void late({required bool missed}) => _event('late', {'missed': missed});

  void _event(String kind, Map<String, Object> fields) =>
      _logger.info(LogCategory.ui, 'turn $kind', {'wUs': _now().microsecondsSinceEpoch, ...fields});
}
