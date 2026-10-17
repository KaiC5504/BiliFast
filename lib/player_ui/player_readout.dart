import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../player/bili_player.dart';
import '../player/playback_clock.dart';

/// The player as the controls show it. The playhead is read back from the clock in the frame after each event,
/// so whoever feeds the clock those events has done so by then. Position events come about 10 times a second
/// while playing, as often as the bar and the time need.
final class PlayerReadout {
  PlayerReadout({required this.clock, required Stream<PlayerEvent> events}) {
    _subscription = events.listen(_handle);
    refresh();
  }

  final PlaybackClock clock;
  final status = ValueNotifier(PlayerStatus.idle);
  final seconds = ValueNotifier<double>(0);
  final buffered = ValueNotifier<List<({double start, double end})>>(const []);

  /// Fires on any change: what the danmaku layer wakes up on.
  late final Listenable any = Listenable.merge([status, seconds, buffered]);

  late final StreamSubscription<PlayerEvent> _subscription;
  int? _frame;

  /// Playing, or meant to be and waiting for data.
  bool get wantsPlay => status.value == PlayerStatus.playing || status.value == PlayerStatus.buffering;

  /// Where the buffered range holding [at] ends; 0 when [at] is in none.
  double bufferedEnd(double at) {
    for (final range in buffered.value) {
      // Just after a seek the playhead can sit a little before the range the player is filling.
      if (range.start - 1 <= at && at <= range.end) return range.end;
    }
    return 0;
  }

  /// Reads the clock again in the next frame.
  void refresh() {
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      seconds.value = clock.seconds;
    });
  }

  void _handle(PlayerEvent event) {
    switch (event) {
      case StatusChanged(:final status):
        this.status.value = status;
      case BufferedChanged(:final ranges):
        buffered.value = ranges;
      default:
        break;
    }
    refresh();
  }

  void dispose() {
    unawaited(_subscription.cancel());
    final frame = _frame;
    if (frame != null) SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    status.dispose();
    seconds.dispose();
    buffered.dispose();
  }
}
