import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';

import '../player_ui/portrait_controls.dart' show BackGlyph, ChromeTap, MoreDots, PlayPausePainter;
import '../shared/theme.dart';
import 'page_details.dart' show PageTab;
import 'page_tabs.dart';
import 'player_box.dart';
import 'player_session.dart';

/// The room each tab's scroll view leaves above its content for the shrinking player (BiliNative
/// `CollapsingPlayer`'s reserve). Each tab's list starts with a gap this tall and scrolls with the page's primary
/// scroll controller.
class PlayerReserve extends InheritedWidget {
  const PlayerReserve({super.key, required this.height, required super.child});

  final double height;

  /// 0 outside a video page. Read it in a Builder of the gap's own: it changes every frame of a change of shape, and
  /// whatever reads it rebuilds.
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PlayerReserve>()?.height ?? 0;

  @override
  bool updateShouldNotify(PlayerReserve oldWidget) => oldWidget.height != height;
}

/// [PlayerReserve] at [collapse]'s reserve, following it through a change of shape without rebuilding [child]: only
/// the lists' gaps (each tab reads it in a Builder around its gap) rebuild, in the frame the box changes and their
/// offsets are kept.
class CollapseReserve extends StatelessWidget {
  const CollapseReserve({super.key, required this.collapse, required this.child});

  final CollapsingPlayer collapse;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: collapse.reserveListenable,
    builder: (context, reserve, child) => PlayerReserve(height: reserve, child: child!),
    child: child,
  );
}

/// The small player's height as the shown tab scrolls (BiliNative `CollapsingPlayer` and `PlayerArea`, 11, 12, 21).
/// Its full height is 16:9, or an upright video's own shape (17) until the end screen takes 16:9 again (18). Playing,
/// an upright video's box gives up its height above 16:9 one for one with the scroll and then stays 16:9 as the tab
/// scrolls under it; paused, it gives up whatever the tab scrolls after the pause, down to the bar, and once it plays
/// it grows back to its playing height. It notifies only when the height or the progress changes.
class CollapsingPlayer extends ChangeNotifier {
  CollapsingPlayer({required this.tabs, required TickerProvider vsync})
    : _grow = AnimationController(vsync: vsync, duration: CollapseTheme.resume),
      _reshape = AnimationController(vsync: vsync, duration: CollapseTheme.reshape) {
    tabs.motion.addListener(_scrolled);
    _grow.addListener(_update);
    _reshape.addListener(_reshaped);
  }

  final PageTabsController tabs;

  /// How much of the paused height is still in the player as it grows back after the pause: 1 as it starts playing,
  /// 0 once it has its playing height.
  final AnimationController _grow;

  /// [full] on its way from [_shapeFrom] to [shape].
  final AnimationController _reshape;
  double _shapeFrom = 0;
  final _shape = ValueNotifier<double>(0);

  /// What [shape] was last taken from.
  ({int width, int height})? _shapeVideo;
  bool _shapeEnded = false;

  int? _retargetFrame;
  bool _applyQueued = false;
  bool _disposed = false;

  /// Each tab's offset when playback paused: the player shrinks only by what is scrolled after it, so a pause halfway
  /// down a tab doesn't snap it to the bar, and switching to a tab scrolled while playing doesn't either.
  final _from = <PageTab, double>{};

  PlayerSession? _session;
  double _width = 0;

  /// 16:9 for the width, below which only the pause shrinks the box.
  double _floor = 0;
  double _full = 0;
  double _height = 0;
  double _progress = 0;
  bool _paused = false;
  final _reserve = ValueNotifier<double>(0);

  /// With Reduce Motion the player grows back and changes shape at once.
  bool still = false;

  /// How tall the bar it shrinks to is: the iPhone's, or the iPad's pink 立即播放 bar (05). Set as the page lays out,
  /// like [width], it notifies nobody.
  double get barHeight => _bar;
  double _bar = CollapseTheme.barHeight;
  set barHeight(double value) {
    if (value == _bar) return;
    _bar = value;
    _reserve.value = reserve;
    _recompute();
  }

  /// The one tab whose scrolling the height follows, whatever the pager shows: the iPad's sideways column scrolls
  /// 简介's controller with no pager around it. Null follows the pager. Set as the page lays out; it notifies nobody.
  PageTab? get only => _only;
  PageTab? _only;
  set only(PageTab? value) {
    if (value == _only) return;
    _only = value;
    _recompute();
  }

  void _recompute() {
    final (height, progress) = _compute();
    _height = height;
    _progress = progress;
  }

  /// The player's full height under the status bar, on its way to a new shape while it changes.
  double get full => _full;

  /// The page's width as it lays out: the box takes its shape for it at once. It notifies nobody.
  set width(double value) {
    if (value == _width) return;
    _width = value;
    _floor = inlinePlayerHeight(value);
    _reshape.stop();
    _shape.value = _shapeFor();
    _shapeFrom = _shape.value;
    _setFull(_shape.value);
    final (height, progress) = _compute();
    _height = height;
    _progress = progress;
  }

  /// The session whose video shape and end the box follows, changing shape over [CollapseTheme.reshape] once laid
  /// out; null while the page has none. An in-page open keeps the shape the box has until the next video's is known.
  set session(PlayerSession? value) {
    if (identical(value, _session)) return;
    _session?.removeListener(_sessionChanged);
    _session = value;
    value?.addListener(_sessionChanged);
    _sessionChanged();
  }

  /// Loaded, paused and not at the end: only then does scrolling shrink the player past 16:9.
  bool get paused => _paused;
  set paused(bool value) {
    if (value == _paused) return;
    // Every change to the grow notifies, so the pause points and the flag are in place before it.
    if (value) {
      for (final tab in PageTab.values) {
        _from[tab] = tabs.offsetOf(tab);
      }
      _paused = true;
      _grow.value = 0;
    } else {
      _paused = false;
      _grow.value = still ? 0 : 1;
      if (!still) unawaited(_grow.animateTo(0, duration: CollapseTheme.resume, curve: Curves.easeOutCubic));
    }
    _update();
  }

  double get height => _height;

  /// 0 at the height the shrink started from, 1 once it is the bar. Only the pause shrinks it: a playing upright
  /// video's box going down to 16:9 stays at 0.
  double get progress => _progress;

  /// What each tab's scroll view leaves free above its content, so it starts under the full-height player.
  double get reserve => math.max(0, _full - _bar);

  /// [reserve] as it changes.
  ValueListenable<double> get reserveListenable => _reserve;

  /// The full height the box is taking: [full] once a change of shape is over, its end while it runs. What lays out
  /// once at the box's full height (the danmaku) can follow this rather than every frame of the change.
  ValueListenable<double> get shape => _shape;

  /// Playing: what the tab has scrolled comes off [full] down to [floor], and the tab scrolls on under it (21).
  static double playingHeight({required double full, required double floor, required double offset}) =>
      (full - math.max(0.0, offset)).clamp(math.min(floor, full), full);

  /// Paused: what the tab scrolls after the pause point [from] comes off [start], the height it had there ([full]
  /// unless given), down to the bar.
  static double heightFor({
    required double full,
    required double offset,
    required double from,
    double? start,
    double bar = CollapseTheme.barHeight,
  }) {
    if (full <= bar) return full;
    return ((start ?? full) - (offset - from)).clamp(bar, full);
  }

  /// How far [height] has gone from [full], the height the shrink started at, to the bar.
  static double progressOf({required double full, required double height, double bar = CollapseTheme.barHeight}) {
    final reserve = full - bar;
    if (reserve <= 0) return 0;
    return ((full - height) / reserve).clamp(0.0, 1.0);
  }

  double _shapeFor() {
    final session = _session;
    // An in-page open (合集's next, 选集, a related video) clears the last video's shape before the next one's is in;
    // following that would take the box to 16:9 and back.
    if (session == null || !session.opening || session.videoShape != null) {
      _shapeVideo = session?.videoShape;
      _shapeEnded = session?.ended ?? false;
    }
    return inlinePlayerHeight(_width, video: _shapeVideo, ended: _shapeEnded);
  }

  /// Retargets once per frame, at its start: a related video from the end screen lifts the end before its open
  /// clears the shape, and taking each change as it came would grow the box for the old video meanwhile.
  void _sessionChanged() {
    _retargetFrame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _retargetFrame = null;
      _retarget();
    });
  }

  void _retarget() {
    final target = _shapeFor();
    if (target == _shape.value) return;
    _shape.value = target;
    if (still) {
      _reshape.stop();
      _shapeFrom = target;
      _reshaped();
    } else {
      _shapeFrom = _full;
      unawaited(_reshape.forward(from: 0));
    }
  }

  /// The reshape's ticks and the retarget come at the frame's start, among the scroll positions' own ticks; [_apply]
  /// waits for the microtasks after them all, since a fling sets its position outright on each tick and would undo a
  /// correction made before it.
  void _reshaped() {
    if (_applyQueued) return;
    _applyQueued = true;
    scheduleMicrotask(_apply);
  }

  void _apply() {
    _applyQueued = false;
    if (_disposed) return;
    _setFull(lerpDouble(_shapeFrom, _shape.value, CollapseTheme.reshapeCurve.transform(_reshape.value))!);
    _update();
  }

  void _setFull(double value) {
    if (value == _full) return;
    _keepScrolled(value - _full);
    _full = value;
    _reserve.value = reserve;
  }

  /// A tab scrolled down keeps its content where it is on screen as the reserve above it changes, as far as its top
  /// allows; a tab at its top rides the box's bottom edge.
  void _keepScrolled(double change) {
    for (final tab in PageTab.values) {
      final offset = tabs.offsetOf(tab);
      if (offset <= 0) continue;
      final moved = math.max(0.0, offset + change) - offset;
      for (final position in tabs.scrollOf(tab).positions) {
        // A layout-time correction, which the new gap's layout in this frame takes up; a fling restarts from it.
        if (position.hasPixels) position.correctBy(moved);
      }
      _from[tab] = math.max(0, (_from[tab] ?? 0) + moved);
    }
  }

  void _scrolled() {
    for (final tab in PageTab.values) {
      final offset = tabs.offsetOf(tab);
      if (offset < (_from[tab] ?? 0)) _from[tab] = math.max(0, offset);
    }
    _update();
  }

  (double, double) _compute() {
    if (_only case final tab?) return _following(tab);
    final intro = _following(PageTab.intro);
    final comments = _following(PageTab.comments);
    // Through a sideways swipe the height passes from one tab's to the other's with the finger.
    final swipe = tabs.position.clamp(0.0, 1.0);
    return (lerpDouble(intro.$1, comments.$1, swipe)!, lerpDouble(intro.$2, comments.$2, swipe)!);
  }

  /// [tab]'s height and progress.
  (double, double) _following(PageTab tab) {
    final offset = tabs.offsetOf(tab);
    final from = _from[tab] ?? 0;
    final start = playingHeight(full: _full, floor: _floor, offset: from);
    final paused = heightFor(full: _full, offset: offset, from: from, start: start, bar: _bar);
    final shrink = progressOf(full: start, height: paused, bar: _bar);
    if (_paused) return (paused, shrink);
    // Growing back from the paused height, never below it: a scroll back to the top raises it, and falling behind
    // would open a gap under the tab row.
    final left = _grow.value;
    return (lerpDouble(playingHeight(full: _full, floor: _floor, offset: offset), paused, left)!, shrink * left);
  }

  void _update() {
    final (height, progress) = _compute();
    if (height == _height && progress == _progress) return;
    _height = height;
    _progress = progress;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_retargetFrame case final id?) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    _session?.removeListener(_sessionChanged);
    tabs.motion.removeListener(_scrolled);
    _grow.dispose();
    _reshape.dispose();
    _reserve.dispose();
    _shape.dispose();
    super.dispose();
  }
}

/// Over the shrinking player (11, 12): the video darkens and ▶ 继续播放 fades in where the bar will be; once it is the
/// bar, ‹ and ⋮ join it. Any other tap on it resumes, as the official bar does.
class CollapsedPlayerBar extends StatelessWidget {
  const CollapsedPlayerBar({
    super.key,
    required this.progress,
    required this.onResume,
    required this.onBack,
    required this.onMore,
  });

  /// 0 where the pause's shrink started, 1 once it is the bar.
  final double progress;
  final VoidCallback onResume;
  final VoidCallback onBack;
  final VoidCallback onMore;

  static const _rowHeight = CollapseTheme.barHeight - CollapseTheme.rowLift * 2;

  @override
  Widget build(BuildContext context) {
    final barred = progress >= 1;
    final fade = MediaQuery.disableAnimationsOf(context) ? Duration.zero : CollapseTheme.controlsFade;
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          key: const ValueKey('collapse-resume'),
          button: true,
          label: '继续播放',
          onTap: onResume,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onResume,
            child: ColoredBox(color: CollapseTheme.shade.withValues(alpha: CollapseTheme.shade.a * progress)),
          ),
        ),
        Positioned(
          key: const ValueKey('collapse-label'),
          left: 0,
          right: 0,
          top: 0,
          height: _rowHeight,
          // The tap under it carries 继续播放 for VoiceOver.
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(opacity: math.min(1, progress * CollapseTheme.labelFade), child: const _Label()),
            ),
          ),
        ),
        Positioned(
          left: CollapseTheme.backLeft + CollapseTheme.backGlyphWidth / 2 - BiliMetrics.chromeButton / 2,
          top: 0,
          height: _rowHeight,
          child: _Corner(
            shown: barred,
            fade: fade,
            child: ChromeTap(
              key: const ValueKey('collapse-back'),
              label: '返回',
              onTap: onBack,
              child: const BackGlyph(width: CollapseTheme.backGlyphWidth, height: CollapseTheme.backGlyphHeight),
            ),
          ),
        ),
        Positioned(
          right: CollapseTheme.moreRight + BiliMetrics.moreDot / 2 - BiliMetrics.chromeButton / 2,
          top: 0,
          height: _rowHeight,
          child: _Corner(
            shown: barred,
            fade: fade,
            child: ChromeTap(key: const ValueKey('collapse-more'), label: '更多', onTap: onMore, child: const MoreDots()),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label();

  @override
  Widget build(BuildContext context) => Center(
    child: Transform.translate(offset: const Offset(CollapseTheme.labelShift, 0), child: _row()),
  );

  Widget _row() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CustomPaint(
        size: const Size(CollapseTheme.playGlyphWidth, CollapseTheme.playGlyphHeight),
        painter: PlayPausePainter(kAlwaysDismissedAnimation, color: CollapseTheme.label),
      ),
      const SizedBox(width: CollapseTheme.labelGap),
      Text(
        '继续播放',
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontFamily: BiliFonts.family,
          fontSize: CollapseTheme.labelText,
          color: CollapseTheme.label,
          height: 1.2,
          letterSpacing: 0,
        ),
      ),
    ],
  );
}

class _Corner extends StatelessWidget {
  const _Corner({required this.shown, required this.fade, required this.child});

  final bool shown;
  final Duration fade;
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: fade,
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !shown,
        child: ExcludeSemantics(excluding: !shown, child: child),
      ),
    ),
  );
}
