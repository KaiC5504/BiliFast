import 'dart:async';

import 'package:bili_core/danmaku.dart';
import 'package:bili_core/logic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../danmaku/danmaku_layer.dart';
import '../playback/overlay_stats.dart';
import '../player/bili_player.dart';
import '../player/playback_clock.dart';
import '../shared/theme.dart';
import 'player_readout.dart';
import 'seek_bar.dart';
import 'stats_overlay.dart';

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
    this.onHint,
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

  /// A seek the user made on the bar, after the player was told; the controller times it. Bar seeks are not
  /// [precise]: the player starts at the keyframe nearest the spot, without decoding its way up to it.
  final void Function(double seconds, {required bool precise})? onSeek;

  /// The finger rests on the bar while dragging, so the engine can start loading there; null once the drag
  /// ended without a seek.
  final void Function(double? seconds)? onHint;

  @override
  State<PlayerStage> createState() => _PlayerStageState();
}

class _PlayerStageState extends State<PlayerStage> {
  static const _hideDelay = Duration(seconds: 3);
  static const _fade = Duration(milliseconds: 200);
  static const _timeStyle = TextStyle(
    color: BiliColors.onVideo,
    fontSize: BiliMetrics.chromeTimeFont,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  late PlayerReadout _readout;
  late Widget _video;
  late Listenable _bar;
  final _scrubbing = ValueNotifier<double?>(null);
  bool _controlsVisible = true;
  Timer? _hideTimer;
  int _seekCount = 0;

  /// A hint went out during this drag.
  bool _hinted = false;

  /// Where the bar aims while it is dragged, otherwise the playhead.
  double get _position => _scrubbing.value ?? _readout.seconds.value;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(PlayerStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player || oldWidget.clock != widget.clock) {
      _detach();
      _attach();
    } else if (oldWidget.duration != widget.duration) {
      _bar = _barListenable();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _detach();
    _scrubbing.dispose();
    super.dispose();
  }

  void _attach() {
    _readout = PlayerReadout(clock: widget.clock, events: widget.player.events);
    _readout.status.addListener(_statusChanged);
    // Built once: the platform view must not be recreated when the controls change.
    _video = widget.player.buildView();
    _bar = _barListenable();
  }

  void _detach() {
    _readout.status.removeListener(_statusChanged);
    _readout.dispose();
  }

  Listenable _barListenable() =>
      Listenable.merge([_readout.seconds, _readout.buffered, _scrubbing, widget.duration]);

  void _statusChanged() {
    if (!_readout.wantsPlay) {
      _hideTimer?.cancel();
    } else if (_controlsVisible) {
      _scheduleHide();
    }
  }

  void _touch() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _hide() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = false);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_readout.wantsPlay) return;
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted || _scrubbing.value != null || !_readout.wantsPlay) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _togglePlay() {
    final player = widget.player;
    if (_readout.wantsPlay) {
      unawaited(player.pause());
      return;
    }
    if (_readout.status.value == PlayerStatus.ended) {
      unawaited(player.seek(0, precise: true));
      widget.clock.jump(0);
      _readout.refresh();
    }
    unawaited(player.play());
  }

  void _scrub(double seconds) {
    if (widget.duration.value <= 0) return;
    _hideTimer?.cancel();
    _seekCount += 1;
    _scrubbing.value = seconds;
  }

  void _hint(double seconds) {
    if (widget.duration.value <= 0 || widget.onHint == null) return;
    _hinted = true;
    widget.onHint?.call(seconds);
  }

  void _cancelScrub() {
    _scrubbing.value = null;
    if (_hinted) widget.onHint?.call(null);
    _hinted = false;
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _commit(double seconds) async {
    _hinted = false;
    if (widget.duration.value <= 0) return;
    final count = ++_seekCount;
    _scrubbing.value = seconds;
    final seeked = widget.player.seek(seconds, precise: false);
    widget.onSeek?.call(seconds, precise: false);
    widget.clock.jump(seconds, precise: false);
    _readout.refresh();
    try {
      await seeked;
    } finally {
      // The bar holds the target until the seek lands, so it doesn't jump back to the old position first.
      if (mounted && _seekCount == count) {
        _scrubbing.value = null;
        if (_controlsVisible) _scheduleHide();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BiliColors.videoBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _video,
          DanmakuLayer(
            clock: widget.clock,
            timeline: widget.danmaku,
            enabled: widget.danmakuEnabled,
            wake: _readout.any,
          ),
          if (widget.showStats)
            Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder(
                valueListenable: widget.stats,
                builder: (context, stats, _) => StatsOverlay(stats: stats),
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _controlsVisible ? _hide() : _touch(),
            onDoubleTap: () {
              _togglePlay();
              _touch();
            },
          ),
          _controls(),
        ],
      ),
    );
  }

  Widget _controls() {
    double duration() => widget.duration.value;
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedOpacity(
            opacity: _controlsVisible ? 0 : 1,
            duration: _fade,
            child: HiddenProgressLine(position: () => _position, duration: duration, repaint: _bar),
          ),
        ),
        AnimatedOpacity(
          key: const ValueKey('player-controls'),
          opacity: _controlsVisible ? 1 : 0,
          duration: _fade,
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: Stack(
              children: [
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: BiliMetrics.chromeShadeHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [BiliColors.chromeShadeClear, BiliColors.chromeShade],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Row(
                    children: [
                      _PlayButton(
                        readout: _readout,
                        onPressed: () {
                          _togglePlay();
                          _touch();
                        },
                      ),
                      Expanded(
                        child: SeekBar(
                          key: const ValueKey('player-bar'),
                          position: () => _position,
                          duration: duration,
                          buffered: () => _readout.bufferedEnd(_position),
                          repaint: _bar,
                          onScrub: _scrub,
                          onCommit: _commit,
                          onCancel: _cancelScrub,
                          onRest: _hint,
                        ),
                      ),
                      IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: BiliMetrics.chromeTimeLeading,
                            right: BiliMetrics.chromeTimeTrailing,
                          ),
                          child: ListenableBuilder(
                            listenable: _bar,
                            builder: (context, _) => Text(
                              TimeFormat.pair(_position, widget.duration.value),
                              key: const ValueKey('player-time'),
                              style: _timeStyle,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.readout, required this.onPressed});

  final PlayerReadout readout;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: readout.status,
      builder: (context, _, _) {
        final playing = readout.wantsPlay;
        return Semantics(
          button: true,
          label: playing ? '暂停' : '播放',
          child: GestureDetector(
            key: const ValueKey('player-play'),
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox.square(
              dimension: BiliMetrics.chromeButton,
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: BiliMetrics.chromeIcon,
                color: BiliColors.onVideo,
              ),
            ),
          ),
        );
      },
    );
  }
}
