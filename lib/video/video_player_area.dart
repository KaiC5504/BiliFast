import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    this.shrunk = false,
    this.barred = false,
    this.danmakuHeight,
    this.pin,
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

  /// The paused small player is shrinking to the 继续播放 bar: its controls take no touches, and once it is the bar
  /// ([barred]) nothing of them shows, not even the thin line (12).
  final bool shrunk;
  final bool barred;

  /// The small player's full height, at which the danmaku keep laying out while it shrinks, clipped, so they stay
  /// where they were rather than re-laying out every frame. Null in full screen.
  final double? danmakuHeight;

  /// While the page grows the player into full screen or shrinks it back, the size the danmaku, the chrome and the
  /// end screen lay out at (the box's at rest in [presentation]), scaled to the box meanwhile. Laid out at every
  /// frame's size the danmaku would start over each frame, and the chrome wouldn't fit the small box. The video
  /// follows the box.
  final ValueListenable<Size?>? pin;

  @override
  Widget build(BuildContext context) {
    final session = ui?.session;
    return ColoredBox(
      color: BiliColors.videoBackground,
      child: ListenableBuilder(
        listenable: Listenable.merge([?session, ?danmaku, ?pin]),
        builder: (context, _) => Stack(fit: StackFit.expand, children: _layers()),
      ),
    );
  }

  List<Widget> _layers() {
    final ui = this.ui;
    final session = ui?.session;
    final ended = session?.ended ?? false;
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
                    child: ClipRect(
                      clipBehavior: shrunk ? Clip.hardEdge : Clip.none,
                      child: _Pinned(
                        size: pin?.value,
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: danmakuHeight,
                          maxHeight: danmakuHeight,
                          child: DanmakuLayer(
                            key: const ValueKey('video-danmaku'),
                            clock: session.clock,
                            timeline: danmaku?.timeline,
                            // The end screens show no danmaku over the last frame.
                            enabled: session.danmakuOn && !ended,
                            wake: session.readout.any,
                            settings: ui?.danmaku?.settings,
                            fullScreen: presentation.fullScreen,
                          ),
                        ),
                      ),
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
      _Pinned(
        key: const ValueKey('video-pinned'),
        size: pin?.value,
        child: Stack(fit: StackFit.expand, children: _controls()),
      ),
    ];
  }

  List<Widget> _controls() {
    final ui = this.ui;
    final ended = ui?.session.ended ?? false;
    final failed = failure != null;
    return [
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
          IgnorePointer(
            key: const ValueKey('video-chrome'),
            ignoring: shrunk,
            child: Offstage(offstage: barred, child: _chrome(ui)),
          ),
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

/// Lays its child out at [size] and scales it to its own size; with no [size] it is just its child.
class _Pinned extends SingleChildRenderObjectWidget {
  const _Pinned({super.key, required this.size, required super.child});

  final Size? size;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPinned(size);

  @override
  void updateRenderObject(BuildContext context, _RenderPinned renderObject) => renderObject.pinned = size;
}

class _RenderPinned extends RenderProxyBox {
  _RenderPinned(this._pinned);

  Size? _pinned;

  set pinned(Size? value) {
    if (value == _pinned) return;
    _pinned = value;
    markNeedsLayout();
  }

  Size? get _active {
    final pinned = _pinned;
    return pinned == null || pinned.isEmpty || child == null ? null : pinned;
  }

  Matrix4 _scale(Size pinned) => Matrix4.diagonal3Values(size.width / pinned.width, size.height / pinned.height, 1);

  Size _sizeFor(BoxConstraints constraints, Size pinned) =>
      constraints.biggest.isFinite ? constraints.biggest : constraints.constrain(pinned);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final pinned = _active;
    return pinned == null ? super.computeDryLayout(constraints) : _sizeFor(constraints, pinned);
  }

  @override
  void performLayout() {
    final pinned = _active;
    if (pinned == null) return super.performLayout();
    child!.layout(BoxConstraints.tight(pinned));
    size = _sizeFor(constraints, pinned);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final pinned = _active;
    if (pinned == null) {
      layer = null;
      return super.paint(context, offset);
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _scale(pinned),
      super.paint,
      oldLayer: layer is TransformLayer ? layer! as TransformLayer : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_active case final pinned?) transform.multiply(_scale(pinned));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final pinned = _active;
    if (pinned == null) return super.hitTestChildren(result, position: position);
    return result.addWithPaintTransform(
      transform: _scale(pinned),
      position: position,
      hitTest: (result, position) => child!.hitTest(result, position: position),
    );
  }
}
