import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../player_ui/portrait_controls.dart' show BackGlyph, ChromeTap, MoreDots, PlayPausePainter;
import '../shared/theme.dart';
import 'page_details.dart' show PageTab;
import 'page_tabs.dart';

/// The room each tab's scroll view leaves above its content for the shrinking player (BiliNative
/// `CollapsingPlayer`'s reserve). Each tab's list starts with a gap this tall and scrolls with the page's primary
/// scroll controller.
class PlayerReserve extends InheritedWidget {
  const PlayerReserve({super.key, required this.height, required super.child});

  final double height;

  /// 0 outside a video page.
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PlayerReserve>()?.height ?? 0;

  @override
  bool updateShouldNotify(PlayerReserve oldWidget) => oldWidget.height != height;
}

/// The small player's height as the shown tab scrolls (BiliNative `CollapsingPlayer` and `PlayerArea`, 11, 12).
/// Paused, it gives up whatever the tab scrolls after the pause, down to the bar; playing or at the end it keeps its
/// full height, growing back to it if it had shrunk. It notifies only when the height changes.
class CollapsingPlayer extends ChangeNotifier {
  CollapsingPlayer({required this.tabs, required TickerProvider vsync})
    : _grow = AnimationController(vsync: vsync, duration: CollapseTheme.resume) {
    tabs.motion.addListener(_scrolled);
    _grow.addListener(_update);
  }

  final PageTabsController tabs;

  /// What is left of the shrink while the player grows back after the pause; 0 once it is full.
  final AnimationController _grow;

  /// Each tab's offset when playback paused: the player shrinks only by what is scrolled after it, so a pause halfway
  /// down a tab doesn't snap it to the bar, and switching to a tab scrolled while playing doesn't either.
  final _from = <PageTab, double>{};

  double _full = 0;
  double _height = 0;
  bool _paused = false;

  /// With Reduce Motion the player grows back at once.
  bool still = false;

  /// The player's 16:9 height under the status bar. The page sets it as it lays out, so it notifies nobody.
  double get full => _full;
  set full(double value) {
    if (value == _full) return;
    _full = value;
    _height = _compute();
  }

  /// Loaded, paused and not at the end: only then does scrolling shrink the player.
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
      final left = progress;
      _paused = false;
      _grow.value = still ? 0 : left;
      if (!still) unawaited(_grow.animateTo(0, duration: CollapseTheme.resume, curve: Curves.easeOutCubic));
    }
    _update();
  }

  double get height => _height;

  /// 0 at full height, 1 once it is the bar.
  double get progress => progressOf(full: _full, height: _height);

  /// What each tab's scroll view leaves free above its content, so it starts under the full-height player.
  double get reserve => math.max(0, _full - CollapseTheme.barHeight);

  static double heightFor({required double full, required double offset, required double from}) {
    if (full <= CollapseTheme.barHeight) return full;
    return (full - (offset - from)).clamp(CollapseTheme.barHeight, full);
  }

  static double progressOf({required double full, required double height}) {
    final reserve = full - CollapseTheme.barHeight;
    if (reserve <= 0) return 0;
    return ((full - height) / reserve).clamp(0.0, 1.0);
  }

  void _scrolled() {
    for (final tab in PageTab.values) {
      final offset = tabs.offsetOf(tab);
      if (offset < (_from[tab] ?? 0)) _from[tab] = math.max(0, offset);
    }
    _update();
  }

  double _compute() {
    double following(PageTab tab) => heightFor(full: _full, offset: tabs.offsetOf(tab), from: _from[tab] ?? 0);
    // Through a sideways swipe the height passes from one tab's to the other's with the finger.
    final shown = lerpDouble(following(PageTab.intro), following(PageTab.comments), tabs.position.clamp(0.0, 1.0))!;
    if (_paused) return shown;
    // Growing back, it never falls behind a scroll back to the top, which would open a gap under the tab row.
    return math.max(shown, _full - _grow.value * reserve);
  }

  void _update() {
    final height = _compute();
    if (height == _height) return;
    _height = height;
    notifyListeners();
  }

  @override
  void dispose() {
    tabs.motion.removeListener(_scrolled);
    _grow.dispose();
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

  /// 0 at full height, 1 once it is the bar.
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
    child: Row(
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
    ),
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
