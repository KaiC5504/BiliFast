import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app/form_factor.dart';
import '../danmaku/danmaku_layer.dart';
import '../device/orientation.dart';
import '../playback/danmaku_feed.dart';
import '../player/bili_player.dart' show FitMode;
import '../player_ui/end_screen_landscape.dart';
import '../player_ui/end_screen_portrait.dart';
import '../player_ui/landscape_chrome.dart';
import '../player_ui/pad/pad_end_fullscreen.dart';
import '../player_ui/pad/pad_end_inline.dart';
import '../player_ui/pad/pad_fullscreen_chrome.dart';
import '../player_ui/pad/pad_inline_controls.dart';
import '../player_ui/player_gestures.dart';
import '../player_ui/player_hud.dart';
import '../player_ui/player_loading.dart';
import '../player_ui/player_ui.dart';
import '../player_ui/portrait_controls.dart';
import '../player_ui/stats_overlay.dart';
import '../player_ui/vertical_chrome.dart';
import '../shared/theme.dart';
import 'player_session.dart';
import 'story/story_drag.dart';
import 'story/story_pager.dart';

/// The player as the video page shows it, in every presentation (BiliNative `PlayerBox` and `ChromeLayer.swift`): the
/// video with danmaku over it, the stats overlay, the gesture layer, the chrome for [presentation] or the end screen,
/// the HUD, and the cover, the loading TV and failure around them. It fills the space the page gives it.
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
    this.played = true,
    this.loading = false,
    this.waiting,
    this.failure,
    this.onRetry,
    this.endScreenAside = false,
    this.shrunk = false,
    this.barred = false,
    this.danmakuHeight,
    this.pin,
    this.turning,
    this.verticalTurn,
    this.slide,
    this.storyPager,
    this.moveTargets,
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

  /// The video has played on this page. Until then no danmaku draw: one loaded paused would hold its first ones at the
  /// right edge, frozen over the cover.
  final bool played;

  /// The first load, or a change of quality: [PlayerLoading] shows at once.
  final bool loading;

  /// The player has waited for data past [PlayerLoadingTheme.grace] mid-play: [PlayerLoading] shows too.
  final ValueListenable<bool>? waiting;
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

  /// While true the page is turning the player, or growing or shrinking it: the chrome, the end screen and the HUD
  /// are out of sight and take no touches, kept as they were for when it ends. Scaled to the box they would stretch
  /// up to 1.6×.
  final ValueListenable<bool>? turning;

  /// While the page turns the player between 竖屏 and landscape full screen, how far it has got toward landscape (0 to
  /// 1): the video's band goes from 竖屏's to the whole box, and the danmaku are put away, since pinned at one end's size
  /// they would stretch to the other's shape.
  final ValueListenable<double?>? verticalTurn;

  /// While the page slides the picture between the small player's box and 竖屏's band (187), or into the room above the
  /// uploader sheet (181), where the video is in this area's box; the danmaku are put away meanwhile, as through a
  /// turn, and 竖屏's held still goes with the video.
  final ValueListenable<Rect?>? slide;

  /// The page's swipe between 竖屏's videos; it takes part only in 竖屏 on the iPhone, while its feed is up.
  final StoryPager? storyPager;

  /// 下一个视频 and 上一个视频 as buttons as well as custom actions, for Windows' accessibility bridge, which leaves
  /// custom actions out; null puts them in on Windows only.
  final bool? moveTargets;

  @override
  Widget build(BuildContext context) {
    final session = ui?.session;
    final pad = FormFactor.of(context).isPad;
    return ColoredBox(
      color: BiliColors.videoBackground,
      child: ListenableBuilder(
        listenable: Listenable.merge([?session, ?danmaku, ?pin, ?turning, ?verticalTurn, ?slide, ?storyPager]),
        builder: (context, _) {
          final story = _story(pad: pad);
          final feed = story?.feed;
          // The swipe for VoiceOver and the Windows test tool, which can't drag.
          return Semantics(
            container: story != null,
            customSemanticsActions: story == null || feed == null
                ? null
                : {
                    // With none known yet it asks the feed again, as a swipe past the end does.
                    const CustomSemanticsAction(label: '下一个视频'): story.moveNext,
                    if (feed.previous != null) const CustomSemanticsAction(label: '上一个视频'): story.movePrevious,
                  },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ..._layers(pad: pad, story: story),
                if (story != null && (moveTargets ?? Platform.isWindows))
                  _MoveTargets(key: const ValueKey('story-move-targets'), pager: story),
              ],
            ),
          );
        },
      ),
    );
  }

  StoryPager? _story({required bool pad}) {
    final pager = storyPager;
    return !pad && ui != null && presentation == Presentation.vertical && pager?.feed != null ? pager : null;
  }

  List<Widget> _layers({required bool pad, required StoryPager? story}) {
    final ui = this.ui;
    final session = ui?.session;
    final ended = session?.ended ?? false;
    final band = _verticalBand(session);
    final turn = verticalTurn?.value;
    final heightFactor = switch (turn) {
      final t? => band + (1 - band) * t,
      null => presentation == Presentation.vertical ? band : 1.0,
    };
    final slid = slide?.value;
    return [
      if (video case final video?)
        Align(
          key: const ValueKey('video-surface'),
          alignment: Alignment.topCenter,
          child: StoryShift(
            drag: story?.drag,
            child: CustomSingleChildLayout(
              delegate: VideoSurfaceLayout(heightFactor: heightFactor, slid: slid),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  KeyedSubtree(key: const ValueKey('video-view'), child: video),
                  if (session != null)
                    _unseen(
                      turn != null || slid != null,
                      _MovingDim(
                        drag: story?.drag,
                        child: _DanmakuArea(
                          key: const ValueKey('video-danmaku-area'),
                          pad: pad,
                          vertical: presentation == Presentation.vertical,
                          videoIsVertical: VerticalChrome.uprightShape(session),
                          fit: session.fit,
                          video: switch (session.videoShape) {
                            (:final width, :final height) => Size(width.toDouble(), height.toDouble()),
                            null => null,
                          },
                          builder: (picture, area) => ClipRect(
                            // A playing upright box held at 16:9 by the scroll isn't shrunk, but its danmaku still run
                            // the full height.
                            clipBehavior: shrunk || danmakuHeight != null ? Clip.hardEdge : Clip.none,
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
                                  enabled: session.danmakuOn && !ended && played,
                                  wake: session.readout.any,
                                  settings: ui?.danmaku?.settings,
                                  presentation: presentation,
                                  formFactor: pad ? FormFactor.pad : FormFactor.phone,
                                  mask: ui?.danmaku?.mask,
                                  picture: _Pinned.unscale(picture, area: area, pinned: pin?.value),
                                  mirrored: session.mirrored,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      if (story != null)
        StoryNeighbours(
          key: const ValueKey('story-neighbours'),
          pager: story,
          danmakuOn: session?.danmakuOn ?? true,
          slide: slid,
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
        child: Stack(fit: StackFit.expand, children: _controls(pad: pad, story: story)),
      ),
    ];
  }

  /// A video swiped to that fails to open has no gesture layer, only 重试: in 竖屏 the swipe still goes past it.
  static Widget _swipeable(StoryDrag? drag, Widget failure) =>
      drag == null ? failure : _FailureSwipe(key: const ValueKey('video-failure-swipe'), drag: drag, child: failure);

  List<Widget> _controls({required bool pad, required StoryPager? story}) {
    final ui = this.ui;
    final ended = ui?.session.ended ?? false;
    final failed = failure != null;
    final aside = turning?.value ?? false;
    return [
      if (ui != null && !failed) ...[
        if (!ended) PlayerGestureLayer(key: const ValueKey('video-gestures'), ui: ui),
        if (ended)
          IgnorePointer(
            key: const ValueKey('video-end'),
            ignoring: endScreenAside,
            child: ExcludeSemantics(
              excluding: endScreenAside,
              child: _unseen(
                aside,
                ChromeSlide(shown: !endScreenAside, from: Offset.zero, child: pad ? _padEndScreen(ui) : _endScreen(ui)),
              ),
            ),
          )
        else
          IgnorePointer(
            key: const ValueKey('video-chrome'),
            ignoring: shrunk,
            child: Offstage(offstage: barred, child: _unseen(aside, pad ? _padChrome(ui) : _chrome(ui))),
          ),
        if (!ended) _unseen(aside, PlayerHud(ui: ui), key: const ValueKey('video-hud')),
      ],
      if (failure case final failure?)
        _swipeable(story?.drag, _Failure(key: const ValueKey('video-failure'), message: failure, onRetry: onRetry))
      else
        _QuietWhileHeld(
          key: const ValueKey('video-loading-layer'),
          held: story?.arrived,
          child: ValueListenableBuilder(
            valueListenable: waiting ?? const AlwaysStoppedAnimation(false),
            builder: (context, waiting, _) => loading || waiting
                ? Align(
                    alignment: Alignment.topCenter,
                    // In 竖屏 it centres on the video's band.
                    child: FractionallySizedBox(
                      heightFactor: _loadingBand(ui),
                      // Hidden through a turn like the chrome: the pinned layer would stretch it unevenly.
                      child: _unseen(
                        aside,
                        PlayerLoading(key: const ValueKey('video-loading'), stats: ui?.session.stats),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
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

  double _loadingBand(PlayerUi? ui) => presentation == Presentation.vertical ? _verticalBand(ui?.session) : 1;

  /// Square videos take the upright band, as the chrome's last button takes them as upright.
  static double _verticalBand(PlayerSession? session) =>
      verticalBand(upright: session != null && VerticalChrome.uprightShape(session));

  /// Not painted while [unseen], and deaf to touches, but laid out and animating, so it comes back as it was.
  static Widget _unseen(bool unseen, Widget child, {Key? key}) => Visibility(
    key: key,
    visible: !unseen,
    maintainState: true,
    maintainAnimation: true,
    maintainSize: true,
    child: child,
  );

  Widget _chrome(PlayerUi ui) => switch (presentation) {
    Presentation.inline => PortraitControls(key: const ValueKey('chrome-inline'), ui: ui),
    Presentation.landscape => LandscapeChrome(key: const ValueKey('chrome-landscape'), ui: ui),
    Presentation.vertical => VerticalChrome(key: const ValueKey('chrome-vertical'), ui: ui),
  };

  // The iPad has no 竖屏 (its full screen takes upright videos too), so only a stray one falls to full screen's.
  Widget _padChrome(PlayerUi ui) => switch (presentation) {
    Presentation.inline => PadInlineControls(key: const ValueKey('chrome-pad-inline'), ui: ui),
    Presentation.landscape || Presentation.vertical => PadFullScreenChrome(
      key: const ValueKey('chrome-pad-fullscreen'),
      ui: ui,
    ),
  };

  Widget _padEndScreen(PlayerUi ui) => switch (presentation) {
    Presentation.inline => PadEndInline(key: const ValueKey('end-pad-inline'), ui: ui),
    Presentation.landscape || Presentation.vertical => PadEndFullScreen(
      key: const ValueKey('end-pad-fullscreen'),
      ui: ui,
    ),
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

/// 竖屏's video band from the screen's top, as a share of its height: the video letterboxes into it, centred on 09's
/// line when wide and 16's when upright.
double verticalBand({required bool upright}) =>
    (upright ? BiliMetrics.verticalUprightCentre : BiliMetrics.verticalVideoCentre) * 2;

/// Where the danmaku fly: below the status bar, and in 竖屏 from under the top row to the video's bottom, over the
/// black above a landscape video as 118 shows, clear of the uploader and the title below it. On the iPad they fly over
/// the whole box: the page's player sits below the status bar, and full screen runs them from the screen's top edge
/// (ipad/09, 25), where the status bar shows only with the controls. [padDanmakuInsets] is the iPad's.
///
/// The video fills the box this area is in, so [builder] is also told where its picture sits, in the area's own
/// coordinates, for 人像防挡.
class _DanmakuArea extends StatelessWidget {
  const _DanmakuArea({
    super.key,
    required this.pad,
    required this.vertical,
    required this.videoIsVertical,
    required this.fit,
    required this.video,
    required this.builder,
  });

  final bool pad;
  final bool vertical;
  final bool videoIsVertical;
  final FitMode fit;

  /// The video's shape, null until known.
  final Size? video;
  final Widget Function(Rect? picture, Size area) builder;

  @override
  Widget build(BuildContext context) {
    final inset = pad ? 0.0 : MediaQuery.paddingOf(context).top;
    // One shape in every presentation, so the danmaku keep their state through a turn.
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        final padding = _padding(box, inset);
        final area = Size(math.max(box.width - padding.horizontal, 0), math.max(box.height - padding.vertical, 0));
        final picture = videoPicture(box, fit: fit, video: video)?.shift(-padding.topLeft);
        return Padding(padding: padding, child: builder(picture, area));
      },
    );
  }

  EdgeInsets _padding(Size box, double inset) {
    if (pad) return padDanmakuInsets;
    if (!vertical) return EdgeInsets.only(top: inset);
    final top =
        math.max(inset - BiliMetrics.verticalTopLift, 0.0) + BiliMetrics.chromeButton + BiliMetrics.verticalDanmakuDrop;
    final band = box.height;
    // The band centres the video; an upright one's danmaku keep to the whole band.
    final videoBottom = videoIsVertical ? band : band / 2 + box.width / BiliMetrics.videoAspect / 2;
    return EdgeInsets.only(top: math.min(top, band), bottom: math.max(band - math.max(videoBottom, top), 0));
  }
}

/// The video's place in the area: its top [heightFactor], or [slid] while the page slides it. 竖屏's held still takes
/// the same place.
class VideoSurfaceLayout extends SingleChildLayoutDelegate {
  const VideoSurfaceLayout({required this.heightFactor, required this.slid});

  final double heightFactor;
  final Rect? slid;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(slid?.size ?? Size(constraints.maxWidth, constraints.maxHeight * heightFactor));

  @override
  Offset getPositionForChild(Size size, Size childSize) => slid?.topLeft ?? Offset.zero;

  @override
  bool shouldRelayout(VideoSurfaceLayout oldDelegate) =>
      oldDelegate.heightFactor != heightFactor || oldDelegate.slid != slid;
}

/// The room the iPad's danmaku keep from the player's edges, in every presentation.
const padDanmakuInsets = EdgeInsets.zero;

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
              strutStyle: BiliFonts.strutOf(context, const TextStyle(fontSize: BiliMetrics.bodyText)),
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

/// The failure over a video swiped to in 竖屏: up and down drive [drag], the failure moving with the page; a tap stays
/// 重试's.
class _FailureSwipe extends StatefulWidget {
  const _FailureSwipe({super.key, required this.drag, required this.child});

  final StoryDrag drag;
  final Widget child;

  @override
  State<_FailureSwipe> createState() => _FailureSwipeState();
}

class _FailureSwipeState extends State<_FailureSwipe> {
  /// Flutter's drag ends a touch the system took back as it ends a lift; the page must go back instead. The Listener
  /// hears the cancel before the recogniser does.
  bool _taken = false;

  @override
  Widget build(BuildContext context) {
    final drag = widget.drag;
    return Listener(
      onPointerDown: (_) => _taken = false,
      onPointerCancel: (_) => _taken = true,
      child: GestureDetector(
        onVerticalDragStart: (_) => drag.start(),
        onVerticalDragUpdate: (details) => drag.update(details.delta.dy),
        onVerticalDragEnd: (details) => _taken ? drag.cancel() : drag.end(details.velocity.pixelsPerSecond.dy),
        onVerticalDragCancel: drag.cancel,
        child: StoryShift(drag: drag, child: widget.child),
      ),
    );
  }
}

/// The danmaku while 竖屏's page moves under the finger, faint as the controls are (185); with no [drag], as they are.
/// Always the same widgets, so the danmaku keep their state as 竖屏 comes and goes.
class _MovingDim extends StatelessWidget {
  const _MovingDim({required this.drag, required this.child});

  final StoryDrag? drag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final drag = this.drag;
    return ListenableBuilder(
      listenable: drag ?? const AlwaysStoppedAnimation<double>(0),
      builder: (context, child) => Opacity(
        opacity: drag?.moving ?? false ? VerticalCleanTheme.movingOpacity : 1,
        child: child,
      ),
      child: child,
    );
  }
}

/// The loading TV, kept away while 竖屏 holds the still of the video swiped to ([held]) for up to
/// [StoryPagerTheme.quietLoading]: the official app shows the picture alone until the video starts.
class _QuietWhileHeld extends StatefulWidget {
  const _QuietWhileHeld({super.key, required this.held, required this.child});

  final Object? held;
  final Widget child;

  @override
  State<_QuietWhileHeld> createState() => _QuietWhileHeldState();
}

class _QuietWhileHeldState extends State<_QuietWhileHeld> {
  Timer? _timer;
  bool _quiet = false;

  @override
  void initState() {
    super.initState();
    _hold();
  }

  @override
  void didUpdateWidget(_QuietWhileHeld oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another landing before the first one's frame waits from its own start.
    if (!identical(oldWidget.held, widget.held)) _hold();
  }

  void _hold() {
    _timer?.cancel();
    _timer = null;
    _quiet = widget.held != null;
    if (_quiet) _timer = Timer(StoryPagerTheme.quietLoading, () => setState(() => _quiet = false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _quiet ? const SizedBox.shrink() : widget.child;
}

/// The Windows build's 下一个视频 and 上一个视频: two small invisible buttons at the left edge's middle for its test
/// tool. They take no touches, so the chrome and the edge swipe under them work as ever.
class _MoveTargets extends StatelessWidget {
  const _MoveTargets({super.key, required this.pager});

  final StoryPager pager;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _target('上一个视频', pager.movePrevious),
        _target('下一个视频', pager.moveNext),
      ],
    ),
  );

  static Widget _target(String label, bool Function() move) => Semantics(
    container: true,
    button: true,
    label: label,
    onTap: () => move(),
    child: const SizedBox.square(dimension: StoryPagerTheme.moveTarget),
  );
}

/// Lays its child out at [size] and scales it to its own size; with no [size] it is just its child.
class _Pinned extends SingleChildRenderObjectWidget {
  const _Pinned({super.key, required this.size, required super.child});

  final Size? size;

  /// [rect] in a box of [area] as the child sees it, laid out at [pinned] and scaled onto the box.
  static Rect? unscale(Rect? rect, {required Size area, required Size? pinned}) {
    if (rect == null || pinned == null || pinned.isEmpty || area.isEmpty) return rect;
    final x = pinned.width / area.width;
    final y = pinned.height / area.height;
    return Rect.fromLTRB(rect.left * x, rect.top * y, rect.right * x, rect.bottom * y);
  }

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
