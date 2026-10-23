import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:bili_core/api.dart' show Chapter;
import 'package:bili_core/logic.dart' show TimeFormat;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

import '../shared/theme.dart';

enum SeekBarStyle {
  /// The small player and landscape, as 15 and 04 show: pink played part, white buffered part and the TV face.
  tv,

  /// 竖屏 full screen, as 09 shows: a white played part and a small dot, no buffered part.
  dot,

  /// 竖屏 paused, as 118 shows: the dot's track and travel, the played part pink and the TV over its end.
  pausedDot;

  /// How much of the bar the thumb keeps from its travel.
  double get thumbWidth => this == tv ? BiliMetrics.thumbWidth : BiliMetrics.verticalDot;

  /// Draws the TV for its thumb.
  bool get face => this != dot;
}

/// The seek bar (port of BiliNative `ProgressBar.swift`): played in pink, buffered in white at 40%, the rest at 20%, a
/// tick where each chapter starts, and the official TV thumb, or the 竖屏 [SeekBarStyle.dot]. It paints from [repaint]
/// without rebuilding. As in the official app, a touch takes hold of the current position rather than jumping to the
/// finger: a drag moves it by the distance dragged, [onCommit] comes when it lifts, and a tap seeks nowhere. While a
/// finger is on it the bar thickens, the TV's eyes look the way it is dragged (the dot grows instead) and the chapter
/// under it shows its title above; when a drag lifts the eyes come back and the TV blinks. VoiceOver reads the time and
/// steps it by [step] through [onCommit].
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.repaint,
    required this.onScrub,
    required this.onCommit,
    required this.onCancel,
    this.onRest,
    this.onHold,
    this.chapters = const [],
    this.style = SeekBarStyle.tv,
  });

  /// How long the finger must stay put for [onRest].
  static const restDelay = Duration(milliseconds: 150);

  /// A finger never stays exactly still; moving less than this many logical pixels is still resting.
  static const restSlop = 3.0;

  static const _grow = Duration(milliseconds: 160);

  /// How far one VoiceOver swipe seeks, in seconds.
  static const step = 10.0;

  /// The official TV, the APK's two Lotties: its eyes sliding from the left at 0 to the right at 1, and its blink.
  static const lookingAsset = 'assets/lottie/player_seek_bar_tv_1.json';
  static const blinkingAsset = 'assets/lottie/player_seek_bar_tv_2.json';

  /// Parses both Lotties once for every bar. Until they are in, or if they failed, the TV style draws a plain round
  /// handle.
  static Future<void> precache() => _TvFaces.load();

  /// Drops the parsed Lotties, or their failure, so the next [precache] loads them again from [bundle].
  @visibleForTesting
  static void debugForgetFaces({AssetBundle? bundle}) {
    _TvFaces.loaded = null;
    _TvFaces._loading = null;
    _TvFaces._bundle = bundle;
  }

  /// The official player (`PlayerSeekWidget`) moves the eyes one [eyesStep] toward each change of the dragged position,
  /// and one back toward [eyesAtRest] for a change of none.
  static const eyesAtRest = 0.5;
  static const eyesStep = 0.05;
  static const _lookSteps = 10;

  /// The eyes' way back to the centre from an end, when a drag lifts, before the blink. 102 shows them back from 0.85
  /// in 0.2 s, and from nearer sooner.
  static const eyesReturn = Duration(milliseconds: 285);

  /// A way back that ends this much later than planned was held up (the app left, a frame stalled): no blink then.
  static const _eyesLate = Duration(milliseconds: 500);

  /// The eyes' place in steps from the centre ([-10, 10]) after the dragged position changed by [change] seconds.
  @visibleForTesting
  static int lookAfter(int look, double change) {
    if (change > 0) return math.min(look + 1, _lookSteps);
    if (change < 0) return math.max(look - 1, -_lookSteps);
    return look - look.sign;
  }

  /// The looking Lottie's progress for [look] steps from the centre.
  @visibleForTesting
  static double eyesOf(int look) => eyesAtRest + look * eyesStep;

  /// Seconds, read when painting.
  final double Function() position;
  final double Function() duration;
  final double Function() buffered;
  final Listenable repaint;
  final ValueChanged<double> onScrub;
  final ValueChanged<double> onCommit;

  /// The touch turned out to be something else, such as a vertical swipe.
  final VoidCallback onCancel;

  /// The finger has stayed at one spot for [restDelay] while on the bar, where the user is likely to let go.
  final ValueChanged<double>? onRest;

  /// True once a drag starts moving the position, false when it lifts or gives way.
  final ValueChanged<bool>? onHold;

  /// 看点: a tick at each start, and the title of the one under the thumb while dragging.
  final List<Chapter> chapters;
  final SeekBarStyle style;

  @override
  State<SeekBar> createState() => SeekBarState();

  /// The chapter holding [position], when it has a title.
  @visibleForTesting
  static String? chapterTitle(List<Chapter> chapters, double position) {
    final title = chapters.lastWhere((chapter) => chapter.from <= position, orElse: _none).title;
    return title.isEmpty ? null : title;
  }

  static Chapter _none() => const Chapter(from: 0, to: 0, title: '');
}

class SeekBarState extends State<SeekBar> with TickerProviderStateMixin {
  late final _drag = AnimationController(vsync: this, duration: SeekBar._grow);
  late final _dragCurve = CurvedAnimation(parent: _drag, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
  late final _eyes = AnimationController(vsync: this, value: SeekBar.eyesAtRest);
  late final _blink = AnimationController(vsync: this);
  Timer? _restTimer;

  /// Where the finger last came to rest.
  double? _anchor;

  /// The position and the finger's x when it touched down; null while no finger is on the bar.
  double? _from;
  double _fromX = 0;

  /// The latest scrubbed position, committed when the finger lifts.
  double _scrubbed = 0;

  /// The eyes in steps from the centre, and the position they last moved for.
  int _look = 0;
  double _lookedFrom = 0;

  bool _holding = false;

  /// Reduce Motion and TickerMode, read where the dependencies change: the drag recognizer can let go of a finger as
  /// the bar unmounts, when the tree above can no longer be asked.
  bool _still = false;
  bool _ticking = true;

  /// Deactivated: out of the tree, perhaps for good.
  bool _gone = false;

  /// The frame the eyes' way back first ticked in.
  Duration? _glideFrom;

  /// The looking Lottie's progress.
  @visibleForTesting
  double get eyes => _eyes.value;

  /// The blink Lottie's progress while it plays, else null.
  @visibleForTesting
  double? get blink => _blink.status == AnimationStatus.forward ? _blink.value : null;

  @override
  void initState() {
    super.initState();
    _eyes.addListener(_eyesMoved);
    _awaitFaces();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _ticking = TickerMode.valuesOf(context).enabled;
    // Frozen while covered, the way back would finish and blink only when shown again.
    if (!_ticking && (_eyes.isAnimating || _blink.isAnimating)) _rest();
  }

  @override
  void deactivate() {
    _gone = true;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _gone = false;
  }

  @override
  void didUpdateWidget(SeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.style != oldWidget.style) _awaitFaces();
  }

  void _awaitFaces() {
    if (!widget.style.face || _TvFaces.loaded != null) return;
    _TvFaces.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // The tree is locked while it unmounts, so the hold is let go just after.
    if (_holding) {
      final onHold = widget.onHold;
      scheduleMicrotask(() => onHold?.call(false));
    }
    _restTimer?.cancel();
    _dragCurve.dispose();
    _drag.dispose();
    _eyes.dispose();
    _blink.dispose();
    super.dispose();
  }

  double get _thumbWidth => widget.style.thumbWidth;

  void _follow(double x, double seconds) {
    if (widget.onRest == null) return;
    final anchor = _anchor;
    if (anchor != null && (x - anchor).abs() <= SeekBar.restSlop) return;
    _anchor = x;
    _restTimer?.cancel();
    _restTimer = Timer(SeekBar.restDelay, () {
      _restTimer = null;
      if (mounted) widget.onRest?.call(seconds);
    });
  }

  void _lifted({bool blink = false}) {
    _restTimer?.cancel();
    _restTimer = null;
    _anchor = null;
    _from = null;
    _drag.reverse();
    _settle(blink: blink);
    if (_holding) {
      _holding = false;
      widget.onHold?.call(false);
    }
  }

  void _touched(double position) {
    _look = 0;
    _lookedFrom = position;
    _blink.reset();
    _eyes.value = SeekBar.eyesAtRest;
  }

  void _looked(double position) {
    _look = SeekBar.lookAfter(_look, position - _lookedFrom);
    _lookedFrom = position;
    _eyes.value = SeekBar.eyesOf(_look);
  }

  /// The eyes back to the centre, then the blink, as 102 shows; Reduce Motion puts them back at once and skips the
  /// blink.
  void _settle({required bool blink}) {
    if (!mounted) return;
    if (_still || !_ticking) {
      _rest();
      return;
    }
    _look = 0;
    final away = (_eyes.value - SeekBar.eyesAtRest).abs() / SeekBar.eyesAtRest;
    final planned = SeekBar.eyesReturn * away;
    _glideFrom = null;
    // A touch before the eyes are back stops them, and the blink with them: the future never completes.
    _eyes.animateTo(SeekBar.eyesAtRest, duration: planned).then((_) {
      final faces = _TvFaces.loaded;
      if (!blink || !mounted || faces == null || !widget.style.face) return;
      final from = _glideFrom;
      if (from != null && WidgetsBinding.instance.currentFrameTimeStamp - from > planned + SeekBar._eyesLate) return;
      _blink.duration = faces.blinkDuration;
      _blink.forward(from: 0).then((_) {
        if (mounted) _blink.reset();
      });
    });
  }

  void _eyesMoved() {
    if (_eyes.isAnimating) _glideFrom ??= WidgetsBinding.instance.currentFrameTimeStamp;
  }

  void _rest() {
    _look = 0;
    _eyes.value = SeekBar.eyesAtRest;
    _blink.reset();
  }

  static String _readout(double seconds, double duration) =>
      '${TimeFormat.clock(seconds)} / ${TimeFormat.clock(duration)}';

  void _step(double by) {
    final duration = widget.duration();
    if (duration <= 0) return;
    widget.onCommit((widget.position() + by).clamp(0.0, duration));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repaint,
      builder: (context, child) {
        final duration = widget.duration();
        final position = widget.position();
        final known = duration > 0;
        return Semantics(
          label: '进度',
          slider: true,
          value: known ? _readout(position, duration) : null,
          increasedValue: known ? _readout(math.min(position + SeekBar.step, duration), duration) : null,
          decreasedValue: known ? _readout(math.max(position - SeekBar.step, 0), duration) : null,
          onIncrease: known ? () => _step(SeekBar.step) : null,
          onDecrease: known ? () => _step(-SeekBar.step) : null,
          child: child,
        );
      },
      child: SizedBox(
        height: BiliMetrics.barTouchHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final travel = math.max(width - _thumbWidth, 1.0);
            void scrub(Offset local) {
              final duration = math.max(widget.duration(), 0.0);
              final from = _from ?? widget.position();
              _scrubbed = (from + (local.dx - _fromX) / travel * duration).clamp(0.0, duration);
              _looked(_scrubbed);
              widget.onScrub(_scrubbed);
              _follow(local.dx, _scrubbed);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Anchored where the finger lands, so the slop the drag waits for still moves the thumb.
              onHorizontalDragDown: (details) {
                final from = widget.position();
                _from = from;
                _fromX = details.localPosition.dx;
                _touched(from);
                _drag.forward();
              },
              onHorizontalDragStart: (details) {
                _holding = true;
                widget.onHold?.call(true);
                scrub(details.localPosition);
              },
              onHorizontalDragUpdate: (details) => scrub(details.localPosition),
              onHorizontalDragEnd: (_) {
                _lifted(blink: true);
                widget.onCommit(_scrubbed);
              },
              onHorizontalDragCancel: () {
                _lifted();
                // A finger resting on the bar as it goes is let go while the tree is locked, so the owner hears of
                // it just after, as with the hold in dispose.
                if (_gone) {
                  scheduleMicrotask(widget.onCancel);
                } else {
                  widget.onCancel();
                }
              },
              // Held by the bar, so a tap on it neither seeks nor reaches the player under it.
              onTapUp: (_) => _lifted(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    size: Size(width, BiliMetrics.barTouchHeight),
                    painter: _SeekBarPainter(
                      position: widget.position,
                      duration: widget.duration,
                      buffered: widget.buffered,
                      chapters: widget.chapters,
                      style: widget.style,
                      drag: _dragCurve,
                      faces: _TvFaces.loaded,
                      eyes: _eyes,
                      blink: _blink,
                      repaint: Listenable.merge([widget.repaint, _drag, _eyes, _blink]),
                    ),
                  ),
                  if (widget.chapters.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: BiliMetrics.barTouchHeight + BiliMetrics.chapterTitleGap,
                      height: BiliMetrics.chapterTitleHeight,
                      child: IgnorePointer(child: _chapterLabel(width)),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chapterLabel(double width) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.repaint, _drag]),
      builder: (context, _) {
        if (_drag.isDismissed) return const SizedBox.shrink();
        final position = widget.position();
        final title = SeekBar.chapterTitle(widget.chapters, position);
        if (title == null) return const SizedBox.shrink();
        final travel = math.max(width - _thumbWidth, 1.0);
        final centre = travel * _fraction(position, widget.duration()) + _thumbWidth / 2;
        final shown = _drag.value;
        return CustomSingleChildLayout(
          delegate: _AboveThumb(centre),
          child: Opacity(
            opacity: shown,
            child: Transform.translate(
              offset: Offset(0, (1 - shown) * BiliMetrics.chapterTitleGap),
              child: AnimatedSwitcher(
                duration: SeekBar._grow,
                layoutBuilder: (current, previous) =>
                    Stack(alignment: Alignment.center, children: [...previous, ?current]),
                child: _ChapterTitle(key: ValueKey(title), title: title),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChapterTitle extends StatelessWidget {
  const _ChapterTitle({super.key, required this.title});

  final String title;

  static const _style = TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.chapterTitleFont, height: 1);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: BiliMetrics.chapterTitleHeight,
      padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.chapterTitlePadding),
      decoration: BoxDecoration(
        color: BiliColors.chapterFill,
        borderRadius: BorderRadius.circular(BiliMetrics.chapterTitleRadius),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          title,
          maxLines: 1,
          softWrap: false,
          style: _style,
          strutStyle: BiliFonts.strutOf(context, _style),
        ),
      ),
    );
  }
}

/// Centres the title over the thumb, kept inside the bar's ends.
class _AboveThumb extends SingleChildLayoutDelegate {
  const _AboveThumb(this.centre);

  final double centre;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: constraints.maxWidth, minHeight: constraints.maxHeight, maxHeight: constraints.maxHeight);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (centre - childSize.width / 2).clamp(0.0, math.max(size.width - childSize.width, 0.0)).toDouble();
    return Offset(left, 0);
  }

  @override
  bool shouldRelayout(_AboveThumb oldDelegate) => oldDelegate.centre != centre;
}

double _fraction(double seconds, double duration) {
  if (duration <= 0 || !seconds.isFinite) return 0;
  return (seconds / duration).clamp(0.0, 1.0);
}

class _SeekBarPainter extends CustomPainter {
  _SeekBarPainter({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.chapters,
    required this.style,
    required this.drag,
    required this.faces,
    required this.eyes,
    required this.blink,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final double Function() position;
  final double Function() duration;
  final double Function() buffered;
  final List<Chapter> chapters;
  final SeekBarStyle style;
  final Animation<double> drag;
  final _TvFaces? faces;
  final Animation<double> eyes;
  final Animation<double> blink;

  @override
  void paint(Canvas canvas, Size size) {
    final tv = style == SeekBarStyle.tv;
    final dot = style == SeekBarStyle.dot;
    final thumbWidth = style.thumbWidth;
    final width = size.width;
    final travel = math.max(width - thumbWidth, 1.0);
    final duration = this.duration();
    final playedTo = travel * _fraction(position(), duration) + thumbWidth / 2;
    final bufferedTo = math.min(math.max(travel * _fraction(buffered(), duration) + thumbWidth / 2, playedTo), width);

    final grown = drag.value;
    final held = style.face ? BiliMetrics.tvBarDragHeight : BiliMetrics.barDragHeight;
    final barHeight = lerpDouble(BiliMetrics.barHeight, held, grown.clamp(0.0, 1.0))!;
    final top = (size.height - barHeight) / 2;
    final radius = Radius.circular(barHeight / 2);
    RRect capsule(double to) => RRect.fromLTRBR(0, top, to, top + barHeight, radius);
    canvas.drawRRect(capsule(width), Paint()..color = tv ? BiliColors.chromeTrack : BiliColors.verticalTrack);
    if (tv) canvas.drawRRect(capsule(bufferedTo), Paint()..color = BiliColors.chromeBuffered);
    canvas.drawRRect(
      capsule(math.max(playedTo, 0)),
      Paint()..color = dot ? BiliColors.verticalPlayed : BiliColors.pink,
    );

    if (duration > 0) {
      final tick = Paint()..color = BiliColors.chromeTick;
      for (final chapter in chapters) {
        if (chapter.from <= 0 || chapter.from >= duration) continue;
        final x = travel * _fraction(chapter.from, duration) + thumbWidth / 2;
        canvas.drawRect(Rect.fromLTWH(x - barHeight / 2, top, barHeight, barHeight), tick);
      }
    }

    final centre = Offset(playedTo, size.height / 2);
    final faces = this.faces;
    if (dot) {
      final diameter = lerpDouble(BiliMetrics.verticalDot, BiliMetrics.verticalDotDragging, grown)!;
      canvas.drawCircle(centre, diameter / 2, Paint()..color = BiliColors.verticalThumb);
    } else if (faces == null) {
      canvas.drawCircle(centre, BiliMetrics.thumbHandle / 2, Paint()..color = BiliColors.thumbHandle);
    } else {
      final blinking = blink.status == AnimationStatus.forward;
      faces.draw(
        canvas,
        Rect.fromCenter(center: centre, width: BiliMetrics.thumbWidth, height: BiliMetrics.thumbHeight),
        progress: blinking ? blink.value : eyes.value,
        blinking: blinking,
      );
    }
  }

  @override
  bool shouldRepaint(_SeekBarPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.duration != duration ||
      oldDelegate.buffered != buffered ||
      !listEquals(oldDelegate.chapters, chapters) ||
      oldDelegate.style != style ||
      oldDelegate.faces != faces;
}

/// Both Lotties, parsed once for the whole app. Every bar paints through the same two drawables, one at a time.
final class _TvFaces {
  _TvFaces(LottieComposition looking, LottieComposition blinking)
    // Frames in between, as the iPhone draws the eyes sliding, rather than the files' 30 fps steps.
    : _looking = LottieDrawable(looking, frameRate: FrameRate.max),
      _blinking = LottieDrawable(blinking, frameRate: FrameRate.max),
      blinkDuration = blinking.duration;

  final LottieDrawable _looking;
  final LottieDrawable _blinking;
  final Duration blinkDuration;

  static _TvFaces? loaded;
  static Future<void>? _loading;
  static AssetBundle? _bundle;

  // A failure is kept: the assets ship with the app, so a retry per bar would only report it again.
  static Future<void> load() => _loading ??= () async {
    try {
      final faces = await Future.wait([
        AssetLottie(SeekBar.lookingAsset, bundle: _bundle).load(),
        AssetLottie(SeekBar.blinkingAsset, bundle: _bundle).load(),
      ]);
      loaded = _TvFaces(faces[0], faces[1]);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'seek bar'));
    }
  }();

  void draw(Canvas canvas, Rect rect, {required double progress, required bool blinking}) {
    final face = blinking ? _blinking : _looking;
    face.setProgress(progress);
    face.draw(canvas, rect);
  }
}

/// The thin line along the bottom edge while the controls are hidden: only the played part and no track, as 03 shows.
class HiddenProgressLine extends StatelessWidget {
  const HiddenProgressLine({super.key, required this.position, required this.duration, required this.repaint});

  final double Function() position;
  final double Function() duration;
  final Listenable repaint;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: BiliMetrics.hiddenLine,
        width: double.infinity,
        child: CustomPaint(painter: _LinePainter(position: position, duration: duration, repaint: repaint)),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.position, required this.duration, required Listenable repaint}) : super(repaint: repaint);

  final double Function() position;
  final double Function() duration;

  @override
  void paint(Canvas canvas, Size size) {
    final played = size.width * _fraction(position(), duration());
    if (played <= 0) return;
    canvas.drawRRect(
      RRect.fromLTRBR(0, 0, played, size.height, Radius.circular(size.height / 2)),
      Paint()..color = BiliColors.pink,
    );
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) => oldDelegate.position != position || oldDelegate.duration != duration;
}
