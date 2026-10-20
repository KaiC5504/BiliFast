import 'dart:ui' show Rect, Size;

import 'package:bili_core/devlog.dart';

import '../device/orientation.dart';
import '../device/orientation_host.dart';
import '../device/turn_style.dart';

/// The video page's side of a drawn turn for the phone's log (docs/reference/turn-log.md): its events as they
/// happen, and every frame of the turn as one line once it has settled, to set against the native side's
/// `turn native …` lines. One per page.
class TurnRecorder {
  TurnRecorder({Logger? logger}) : _logger = logger ?? Logger.shared;

  // ignore: unused_field
  final Logger _logger;

  /// The presentation changed: a turn may follow.
  void presentation(
    Presentation from,
    Presentation to, {
    required bool wide,
    required bool waiting,
    required TurnStyle style,
  }) {}

  /// The host started [start]; [outcome] is `pending` (the turn the page waits for), `stale` (the other way, or
  /// overtaken) or `unasked` (none was waited for).
  void started(TurnStart start, {required String outcome}) {}

  /// The first build at a new screen shape.
  void sized(Size size, {required Presentation layout}) {}

  /// The page started drawing [turn]: from [spinFrom] radians back to 0 over [duration], the player box from [grow];
  /// [held] while it waits for the still picture to go (等截图).
  void began(
    int turn, {
    required double spinFrom,
    required Duration duration,
    required double grow,
    required bool held,
  }) {}

  /// A held turn starts moving; [why] is `picture` or `timeout`.
  void released(int turn, {required String why}) {}

  void drawnSent(int turn) {}

  void pictureGone(int turn) {}

  /// The wait for a turn ran out; [missed] when none came at all.
  void late({required bool missed}) {}

  /// One frame of a turn as drawn: the page's angle in radians, the grow, the player box (null at rest), the size laid
  /// out at.
  void frame({required double angle, required double grow, required Rect? box, required Size size}) {}

  void dispose() {}
}
