import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:bili_core/api.dart' show Chapter;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';

enum SeekBarStyle {
  /// The small player and landscape (15, 04): pink played part, white buffered part and the TV face.
  tv,

  /// 竖屏 full screen (09): a white played part and a small dot, no buffered part.
  dot;

  double get thumbWidth => this == tv ? BiliMetrics.thumbWidth : BiliMetrics.verticalDot;
}

/// The seek bar (port of ProgressBar.swift): played in pink, buffered in white at 40%, the rest at 20%, a tick where
/// each chapter starts, and the TV-face thumb, or the 竖屏 [SeekBarStyle.dot]. It paints from [repaint] without
/// rebuilding. A touch scrubs at once and the finger is followed; [onCommit] comes when it lifts. While a finger is
/// on it the thumb grows and the chapter under it shows its title above.
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
    this.chapters = const [],
    this.style = SeekBarStyle.tv,
  });

  /// How long the finger must stay put for [onRest].
  static const restDelay = Duration(milliseconds: 150);

  /// A finger never stays exactly still; moving less than this many logical pixels is still resting.
  static const restSlop = 3.0;

  static const _grow = Duration(milliseconds: 160);

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

  /// 看点: a tick at each start, and the title of the one under the thumb while dragging.
  final List<Chapter> chapters;
  final SeekBarStyle style;

  @override
  State<SeekBar> createState() => _SeekBarState();

  static double _seconds(double x, {required double width, required double duration, required double thumbWidth}) {
    final travel = math.max(width - thumbWidth, 1.0);
    final ratio = ((x - thumbWidth / 2) / travel).clamp(0.0, 1.0);
    return ratio * math.max(duration, 0);
  }

  /// The chapter holding [position], when it has a title.
  @visibleForTesting
  static String? chapterTitle(List<Chapter> chapters, double position) {
    final title = chapters.lastWhere((chapter) => chapter.from <= position, orElse: _none).title;
    return title.isEmpty ? null : title;
  }

  static Chapter _none() => const Chapter(from: 0, to: 0, title: '');
}

class _SeekBarState extends State<SeekBar> with SingleTickerProviderStateMixin {
  late final _drag = AnimationController(vsync: this, duration: SeekBar._grow);
  late final _dragCurve = CurvedAnimation(parent: _drag, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
  Timer? _restTimer;

  /// Where the finger last came to rest.
  double? _anchor;

  @override
  void dispose() {
    _restTimer?.cancel();
    _dragCurve.dispose();
    _drag.dispose();
    super.dispose();
  }

  double get _thumbWidth => widget.style.thumbWidth;

  void _follow(double x, double width) {
    if (widget.onRest == null) return;
    final anchor = _anchor;
    if (anchor != null && (x - anchor).abs() <= SeekBar.restSlop) return;
    _anchor = x;
    _restTimer?.cancel();
    _restTimer = Timer(SeekBar.restDelay, () {
      _restTimer = null;
      if (mounted) {
        widget.onRest?.call(
          SeekBar._seconds(x, width: width, duration: widget.duration(), thumbWidth: _thumbWidth),
        );
      }
    });
  }

  void _lifted() {
    _restTimer?.cancel();
    _restTimer = null;
    _anchor = null;
    _drag.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '进度',
      child: SizedBox(
        height: BiliMetrics.barTouchHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            double at(Offset local) =>
                SeekBar._seconds(local.dx, width: width, duration: widget.duration(), thumbWidth: _thumbWidth);
            void scrub(Offset local) {
              _drag.forward();
              widget.onScrub(at(local));
              _follow(local.dx, width);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragDown: (details) => scrub(details.localPosition),
              onHorizontalDragStart: (details) => scrub(details.localPosition),
              onHorizontalDragUpdate: (details) => scrub(details.localPosition),
              onHorizontalDragEnd: (details) {
                _lifted();
                widget.onCommit(at(details.localPosition));
              },
              onHorizontalDragCancel: () {
                _lifted();
                widget.onCancel();
              },
              onTapUp: (details) {
                _lifted();
                widget.onCommit(at(details.localPosition));
              },
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
                      repaint: Listenable.merge([widget.repaint, _drag]),
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
          style: const TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.chapterTitleFont, height: 1),
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
    required Listenable repaint,
  }) : super(repaint: repaint);

  final double Function() position;
  final double Function() duration;
  final double Function() buffered;
  final List<Chapter> chapters;
  final SeekBarStyle style;
  final Animation<double> drag;

  @override
  void paint(Canvas canvas, Size size) {
    final tv = style == SeekBarStyle.tv;
    final thumbWidth = style.thumbWidth;
    final width = size.width;
    final travel = math.max(width - thumbWidth, 1.0);
    final duration = this.duration();
    final playedTo = travel * _fraction(position(), duration) + thumbWidth / 2;
    final bufferedTo = math.min(math.max(travel * _fraction(buffered(), duration) + thumbWidth / 2, playedTo), width);

    final grown = drag.value;
    final barHeight = lerpDouble(BiliMetrics.barHeight, BiliMetrics.barDragHeight, grown.clamp(0.0, 1.0))!;
    final top = (size.height - barHeight) / 2;
    final radius = Radius.circular(barHeight / 2);
    RRect capsule(double to) => RRect.fromLTRBR(0, top, to, top + barHeight, radius);
    canvas.drawRRect(capsule(width), Paint()..color = tv ? BiliColors.chromeTrack : BiliColors.verticalTrack);
    if (tv) canvas.drawRRect(capsule(bufferedTo), Paint()..color = BiliColors.chromeBuffered);
    canvas.drawRRect(
      capsule(math.max(playedTo, 0)),
      Paint()..color = tv ? BiliColors.pink : BiliColors.verticalPlayed,
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
    if (tv) {
      final scale = 1 + (BiliMetrics.thumbDragScale - 1) * grown;
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(scale);
      canvas.translate(-thumbWidth / 2, -BiliMetrics.thumbHeight / 2);
      paintTVThumb(canvas, Size(thumbWidth, BiliMetrics.thumbHeight));
      canvas.restore();
    } else {
      final diameter = lerpDouble(BiliMetrics.verticalDot, BiliMetrics.verticalDotDragging, grown)!;
      canvas.drawCircle(centre, diameter / 2, Paint()..color = BiliColors.verticalThumb);
    }
  }

  @override
  bool shouldRepaint(_SeekBarPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.duration != duration ||
      oldDelegate.buffered != buffered ||
      !listEquals(oldDelegate.chapters, chapters) ||
      oldDelegate.style != style;
}

/// Our own small TV face (TVThumb.swift): a white screen with two eyes in a dark rounded body with two antennae.
void paintTVThumb(Canvas canvas, Size size) {
  final w = size.width, h = size.height;
  final unit = w / 18;
  final body = Rect.fromLTWH(1 * unit, 3.2 * unit, 16 * unit, h - 4.2 * unit);
  canvas.drawRRect(
    RRect.fromRectAndRadius(body.inflate(0.9 * unit), Radius.circular(4.6 * unit)),
    Paint()..color = BiliColors.thumbRim,
  );

  final antennae = Path()
    ..moveTo(6.2 * unit, body.top + 0.6 * unit)
    ..lineTo(4.2 * unit, 0.9 * unit)
    ..moveTo(11.8 * unit, body.top + 0.6 * unit)
    ..lineTo(13.8 * unit, 0.9 * unit);
  canvas.drawPath(
    antennae,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * unit
      ..strokeCap = StrokeCap.round
      ..color = BiliColors.thumbBody,
  );

  canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(3.8 * unit)), Paint()..color = BiliColors.thumbBody);
  final screen = Rect.fromLTRB(
    body.left + 1.7 * unit,
    body.top + 1.5 * unit,
    body.right - 1.7 * unit,
    body.bottom - 1.5 * unit,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(screen, Radius.circular(2.2 * unit)),
    Paint()..color = BiliColors.thumbScreen,
  );

  final eye = Size(1.7 * unit, math.min(4.2 * unit, screen.height * 0.5));
  final eyePaint = Paint()..color = BiliColors.thumbBody;
  for (final dx in [-2.7 * unit, 2.7 * unit]) {
    final rect = Rect.fromCenter(center: screen.center.translate(dx, 0), width: eye.width, height: eye.height);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(eye.width / 2)), eyePaint);
  }
}

/// The thin line along the bottom edge while the controls are hidden.
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
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = BiliColors.chromeTrack)
      ..drawRect(
        Offset.zero & Size(size.width * _fraction(position(), duration()), size.height),
        Paint()..color = BiliColors.pink,
      );
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) => oldDelegate.position != position || oldDelegate.duration != duration;
}
