import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../danmaku/danmaku_layer.dart';
import '../device/orientation.dart';
import '../playback/danmaku_feed.dart';
import '../player_ui/end_screen_landscape.dart';
import '../player_ui/end_screen_portrait.dart';
import '../player_ui/landscape_chrome.dart';
import '../player_ui/player_gestures.dart';
import '../player_ui/player_hud.dart';
import '../player_ui/player_ui.dart';
import '../player_ui/portrait_controls.dart';
import '../player_ui/stats_overlay.dart';
import '../player_ui/vertical_chrome.dart';
import '../shared/theme.dart';

/// The player as the video page shows it, in every presentation (BiliNative `PlayerBox` and `ChromeLayer.swift`): the
/// video with danmaku over it, the stats overlay, the gesture layer, the chrome for [presentation] or the end screen,
/// the HUD, and the cover, spinner and failure around them. It fills the space the page gives it.
///
/// Every layer is keyed, so the native view and the cover's Hero keep their elements while the others come and go.
class VideoPlayerArea extends StatelessWidget {
  const VideoPlayerArea({
    super.key,
    required this.presentation,
    required this.onBack,
    this.ui,
    this.video,
    this.danmaku,
    this.cover,
    this.loading = false,
    this.failure,
    this.onRetry,
    this.endScreenAside = false,
  });

  final Presentation presentation;

  /// The page's own back arrow, for while no chrome is up to carry one.
  final VoidCallback onBack;

  /// Null until the page has its session, and once the page has left.
  final PlayerUi? ui;

  /// The native view, built once by the page.
  final Widget? video;

  final DanmakuFeed? danmaku;

  /// The card's cover, over the video until it first plays.
  final Widget? cover;

  final bool loading;
  final String? failure;
  final VoidCallback? onRetry;

  /// An action overlay is up over the full-screen player: the end screen gets out of its way, as the chrome does.
  final bool endScreenAside;

  @override
  Widget build(BuildContext context) {
    final session = ui?.session;
    return ColoredBox(
      color: BiliColors.videoBackground,
      child: ListenableBuilder(
        listenable: Listenable.merge([?session, ?danmaku]),
        builder: (context, _) => Stack(fit: StackFit.expand, children: _layers()),
      ),
    );
  }

  List<Widget> _layers() {
    final ui = this.ui;
    final session = ui?.session;
    final ended = session?.ended ?? false;
    final failed = failure != null;
    // 竖屏 sets a landscape video above the middle of the screen (screen 09); a vertical one fills the height.
    final banded = presentation == Presentation.vertical && session?.isVertical != true;
    return [
      if (video case final video?)
        Align(
          key: const ValueKey('video-surface'),
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            heightFactor: banded ? BiliMetrics.verticalVideoCentre * 2 : 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                KeyedSubtree(key: const ValueKey('video-view'), child: video),
                if (session != null)
                  // 竖屏's video runs under the status bar; its danmaku start below it.
                  SafeArea(
                    key: const ValueKey('video-danmaku-area'),
                    left: false,
                    right: false,
                    bottom: false,
                    child: DanmakuLayer(
                      key: const ValueKey('video-danmaku'),
                      clock: session.clock,
                      timeline: danmaku?.timeline,
                      // The end screens show no danmaku over the last frame.
                      enabled: session.danmakuOn && !ended,
                      wake: session.readout.any,
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (session != null && session.showStats)
        SafeArea(
          key: const ValueKey('video-stats'),
          child: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder(
              valueListenable: session.stats,
              builder: (context, stats, _) => StatsOverlay(stats: stats),
            ),
          ),
        ),
      ?cover,
      if (ui != null && !failed) ...[
        if (!ended) PlayerGestureLayer(key: const ValueKey('video-gestures'), ui: ui),
        if (ended)
          IgnorePointer(
            key: const ValueKey('video-end'),
            ignoring: endScreenAside,
            child: ExcludeSemantics(
              excluding: endScreenAside,
              child: ChromeSlide(shown: !endScreenAside, from: Offset.zero, child: _endScreen(ui)),
            ),
          )
        else
          _chrome(ui),
        if (!ended) PlayerHud(key: const ValueKey('video-hud'), ui: ui),
      ],
      if (failure case final failure?)
        _Failure(key: const ValueKey('video-failure'), message: failure, onRetry: onRetry)
      else if (loading)
        const Center(
          key: ValueKey('video-loading'),
          child: CupertinoActivityIndicator(color: BiliColors.onVideo, radius: BiliMetrics.videoSpinnerRadius),
        ),
      if (ui == null || failed)
        SafeArea(
          key: const ValueKey('video-back-layer'),
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              key: const ValueKey('video-back'),
              onPressed: onBack,
              // Sits on the picture itself, over danmaku and white frames.
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: BiliColors.onVideo,
                size: BiliMetrics.videoBackIcon,
                shadows: [Shadow(color: BiliColors.chromeShade, blurRadius: BiliMetrics.videoBackShadow)],
              ),
              tooltip: '返回',
            ),
          ),
        ),
    ];
  }

  Widget _chrome(PlayerUi ui) => switch (presentation) {
    Presentation.inline => PortraitControls(key: const ValueKey('chrome-inline'), ui: ui),
    Presentation.landscape => LandscapeChrome(key: const ValueKey('chrome-landscape'), ui: ui),
    Presentation.vertical => VerticalChrome(key: const ValueKey('chrome-vertical'), ui: ui),
  };

  Widget _endScreen(PlayerUi ui) => switch (presentation) {
    Presentation.inline => EndScreenPortrait(key: const ValueKey('end-inline'), ui: ui),
    Presentation.landscape => EndScreenLandscape(key: const ValueKey('end-landscape'), ui: ui),
    // 竖屏 keeps the small player's end screen, over the band where the video sits.
    Presentation.vertical => LayoutBuilder(
      key: const ValueKey('end-vertical'),
      builder: (context, constraints) {
        final height = constraints.maxWidth / BiliMetrics.videoAspect;
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: constraints.maxHeight * BiliMetrics.verticalVideoCentre - height / 2,
              height: height,
              child: EndScreenPortrait(ui: ui),
            ),
          ],
        );
      },
    ),
  };
}

class _Failure extends StatelessWidget {
  const _Failure({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: BiliColors.videoBackground,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(BiliMetrics.sectionGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              key: const ValueKey('video-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.onVideo),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: BiliMetrics.rowGap),
              OutlinedButton(
                key: const ValueKey('video-retry'),
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BiliColors.onVideo,
                  side: const BorderSide(color: BiliColors.onVideo),
                ),
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
