import 'package:bili_core/danmaku.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../playback/overlay_stats.dart';
import '../player/bili_player.dart';
import '../player/playback_clock.dart';

/// The player as the page shows it: the video, danmaku over it, the stats overlay and the controls.
/// The video takes no touches; this widget's gesture layer handles them.
class PlayerStage extends StatefulWidget {
  const PlayerStage({
    super.key,
    required this.player,
    required this.clock,
    required this.stats,
    required this.showStats,
    required this.duration,
    this.danmaku,
    this.danmakuEnabled = true,
    this.onSeek,
  });

  final BiliPlayer player;
  final PlaybackClock clock;
  final ValueListenable<OverlayStats> stats;
  final bool showStats;

  /// Seconds; 0 until the player reports it.
  final ValueListenable<double> duration;

  /// Danmaku handed out as the playhead passes them; null while none are loaded.
  final DanmakuTimeline? danmaku;
  final bool danmakuEnabled;

  /// A seek the user made (drag on the bar), after the player was told; the controller times it.
  final void Function(double seconds)? onSeek;

  @override
  State<PlayerStage> createState() => _PlayerStageState();
}

class _PlayerStageState extends State<PlayerStage> {
  @override
  Widget build(BuildContext context) => throw UnimplementedError('player UI agent');
}
