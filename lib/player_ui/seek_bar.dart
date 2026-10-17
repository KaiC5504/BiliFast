import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../shared/theme.dart';

/// The seek bar (port of ProgressBar.swift, without chapter ticks yet): played in pink, buffered in white at
/// 40%, the rest at 20%, and the TV-face thumb. It paints from [repaint] without rebuilding. A touch scrubs at
/// once and the finger is followed; [onCommit] comes when it lifts.
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
  });

  /// How long the finger must stay put for [onRest].
  static const restDelay = Duration(milliseconds: 150);

  /// A finger never stays exactly still; moving less than this many logical pixels is still resting.
  static const restSlop = 3.0;

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

  @override
  State<SeekBar> createState() => _SeekBarState();

  static double _seconds(double x, {required double width, required double duration}) {
    final travel = math.max(width - BiliMetrics.thumbWidth, 1.0);
    final ratio = ((x - BiliMetrics.thumbWidth / 2) / travel).clamp(0.0, 1.0);
    return ratio * math.max(duration, 0);
  }
}

class _SeekBarState extends State<SeekBar> {
  Timer? _restTimer;

  /// Where the finger last came to rest.
  double? _anchor;

  @override
  void dispose() {
    _restTimer?.cancel();
    super.dispose();
  }

  void _follow(double x, double width) {
    if (widget.onRest == null) return;
    final anchor = _anchor;
    if (anchor != null && (x - anchor).abs() <= SeekBar.restSlop) return;
    _anchor = x;
    _restTimer?.cancel();
    _restTimer = Timer(SeekBar.restDelay, () {
      _restTimer = null;
      if (mounted) widget.onRest?.call(SeekBar._seconds(x, width: width, duration: widget.duration()));
    });
  }

  void _lifted() {
    _restTimer?.cancel();
    _restTimer = null;
    _anchor = null;
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
            double at(Offset local) => SeekBar._seconds(local.dx, width: width, duration: widget.duration());
            void scrub(Offset local) {
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
              child: CustomPaint(
                size: Size(width, BiliMetrics.barTouchHeight),
                painter: _SeekBarPainter(
                  position: widget.position,
                  duration: widget.duration,
                  buffered: widget.buffered,
                  repaint: widget.repaint,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

double _fraction(double seconds, double duration) {
  if (duration <= 0 || !seconds.isFinite) return 0;
  return (seconds / duration).clamp(0.0, 1.0);
}

class _SeekBarPainter extends CustomPainter {
  _SeekBarPainter({required this.position, required this.duration, required this.buffered, required Listenable repaint})
    : super(repaint: repaint);

  final double Function() position;
  final double Function() duration;
  final double Function() buffered;

  @override
  void paint(Canvas canvas, Size size) {
    const thumbWidth = BiliMetrics.thumbWidth;
    final width = size.width;
    final travel = math.max(width - thumbWidth, 1.0);
    final duration = this.duration();
    final playedTo = travel * _fraction(position(), duration) + thumbWidth / 2;
    final bufferedTo = math.min(math.max(travel * _fraction(buffered(), duration) + thumbWidth / 2, playedTo), width);

    final top = (size.height - BiliMetrics.barHeight) / 2;
    const radius = Radius.circular(BiliMetrics.barHeight / 2);
    RRect capsule(double to) => RRect.fromLTRBR(0, top, to, top + BiliMetrics.barHeight, radius);
    canvas
      ..drawRRect(capsule(width), Paint()..color = BiliColors.chromeTrack)
      ..drawRRect(capsule(bufferedTo), Paint()..color = BiliColors.chromeBuffered)
      ..drawRRect(capsule(math.max(playedTo, 0)), Paint()..color = BiliColors.pink);

    canvas.save();
    canvas.translate(playedTo - thumbWidth / 2, (size.height - BiliMetrics.thumbHeight) / 2);
    paintTVThumb(canvas, const Size(thumbWidth, BiliMetrics.thumbHeight));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SeekBarPainter oldDelegate) =>
      oldDelegate.position != position || oldDelegate.duration != duration || oldDelegate.buffered != buffered;
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
