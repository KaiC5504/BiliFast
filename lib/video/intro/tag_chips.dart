import 'package:bili_core/api.dart' show VideoTag, VideoTagKind;
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import 'collection_row.dart' show Chevron;

/// The topic and BGM chips in a sideways row (03); plain tags are the title block's. There are no topic or music
/// pages yet, so they lead nowhere and aren't buttons.
class TagChips extends StatelessWidget {
  const TagChips({super.key, required this.tags});

  final List<VideoTag> tags;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final tag in tags)
        if (tag.kind != VideoTagKind.normal) tag,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: IntroListTheme.sectionTop, bottom: IntroListTheme.sectionBottom),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1,
        child: SizedBox(
          height: IntroListTheme.chipHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.gutter),
            itemCount: shown.length,
            separatorBuilder: (context, index) => const SizedBox(width: IntroListTheme.chipGap),
            itemBuilder: (context, index) => _Chip(shown[index]),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.tag);

  final VideoTag tag;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tag.name,
    excludeSemantics: true,
    child: Container(
      height: IntroListTheme.chipHeight,
      padding: const EdgeInsets.only(left: IntroListTheme.chipLead, right: IntroListTheme.chipTrailing),
      decoration: BoxDecoration(
        color: BiliColors.softGrey,
        borderRadius: BorderRadius.circular(IntroListTheme.chipHeight / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tag.kind == VideoTagKind.bgm)
            const CustomPaint(
              size: Size(IntroListTheme.musicGlyphWidth, IntroListTheme.musicGlyphHeight),
              painter: _MusicPainter(),
            )
          else
            const CustomPaint(
              size: Size(IntroListTheme.topicGlyphWidth, IntroListTheme.topicGlyphHeight),
              painter: _TopicPainter(),
            ),
          const SizedBox(width: IntroListTheme.chipIconGap),
          ChipName(tag.name),
          const SizedBox(width: IntroListTheme.chipChevronGap),
          const Chevron(
            size: Size(IntroListTheme.chipChevronWidth, IntroListTheme.chipChevronHeight),
            stroke: IntroListTheme.chipChevronStroke,
            color: IntroListTheme.chipGlyphColor,
          ),
        ],
      ),
    ),
  );
}

/// A chip's name. One longer than the chip allows fades out at the right edge and, after a rest, scrolls round once
/// so the whole of it has been seen, as 18's does; with reduced motion it only fades.
class ChipName extends StatefulWidget {
  const ChipName(this.text, {super.key});

  final String text;

  @override
  State<ChipName> createState() => _ChipNameState();
}

class _ChipNameState extends State<ChipName> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(vsync: this);
  double? _started;

  TextStyle get _style => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: IntroListTheme.chipText,
    color: IntroListTheme.chipTextColor,
    height: 1,
  );

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  double _measure(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: _style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Runs once per text width: the rest, then one lap of the name and the gap behind it.
  void _schedule(double width, bool still) {
    if (still) {
      _run.stop();
      return;
    }
    if (_started == width) return;
    _started = width;
    final travel = width + IntroListTheme.marqueeGap;
    _run
      ..duration =
          IntroListTheme.marqueeRest + Duration(milliseconds: (travel / IntroListTheme.marqueeSpeed * 1000).round())
      ..value = 0;
    _run.forward().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final width = _measure(context);
    final text = Text(widget.text, maxLines: 1, softWrap: false, style: _style);
    if (width <= IntroListTheme.chipTextMax) return text;
    final still = MediaQuery.disableAnimationsOf(context);
    if (still ? _run.isAnimating : _started != width) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _schedule(width, still);
      });
    }
    final travel = width + IntroListTheme.marqueeGap;
    return SizedBox(
      width: IntroListTheme.chipTextMax,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _run,
          builder: (context, child) {
            final total = _run.duration?.inMicroseconds;
            final rest = total == null ? 1.0 : IntroListTheme.marqueeRest.inMicroseconds / total;
            final t = still || _run.value <= rest ? 0.0 : (_run.value - rest) / (1 - rest);
            final offset = Curves.easeInOut.transform(t) * travel;
            final moving = offset > 0 && offset < travel;
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  moving ? const Color(0x00000000) : const Color(0xFF000000),
                  const Color(0xFF000000),
                  const Color(0xFF000000),
                  const Color(0x00000000),
                ],
                stops: [0, IntroListTheme.chipFade / bounds.width, 1 - IntroListTheme.chipFade / bounds.width, 1],
              ).createShader(bounds),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Transform.translate(offset: Offset(-offset, 0), child: child),
              ),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              text,
              const SizedBox(width: IntroListTheme.marqueeGap),
              text,
            ],
          ),
        ),
      ),
    );
  }
}

/// Two beamed quavers, drawn from 03 at 3 px per point.
class _MusicPainter extends CustomPainter {
  const _MusicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = IntroListTheme.chipGlyphColor;
    const head = 1.94;
    canvas
      ..drawCircle(const Offset(1.95, 10.84), head, paint)
      ..drawCircle(const Offset(10.0, 9.17), head, paint)
      ..drawRect(const Rect.fromLTRB(2.77, 1.6, 4.02, 10.84), paint)
      ..drawRect(const Rect.fromLTRB(10.82, 0.7, 11.97, 9.17), paint)
      ..drawPath(
        Path()
          ..moveTo(2.77, 1.9)
          ..quadraticBezierTo(2.77, 1.12, 3.6, 1.04)
          ..lineTo(11.4, 0.14)
          ..quadraticBezierTo(11.97, 0.1, 11.97, 0.7)
          ..lineTo(11.97, 2.5)
          ..lineTo(2.77, 3.47)
          ..close(),
        paint,
      );
  }

  @override
  bool shouldRepaint(_MusicPainter oldDelegate) => false;
}

/// Bilibili's topic mark: a # on a little television with its two antennae, drawn from 03 at 3 px per point.
class _TopicPainter extends CustomPainter {
  const _TopicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = IntroListTheme.topicGlyphStroke;
    final paint = Paint()
      ..color = IntroListTheme.chipGlyphColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawRRect(
        RRect.fromLTRBR(
          stroke / 2,
          2.08 + stroke / 2,
          size.width - stroke / 2,
          size.height - stroke / 2,
          const Radius.circular(2.25),
        ),
        paint,
      )
      ..drawLine(const Offset(3.89, 0.55), const Offset(5.28, 2.08), paint)
      ..drawLine(const Offset(9.17, 0.55), const Offset(7.78, 2.08), paint)
      ..drawLine(const Offset(5.42, 4.6), const Offset(4.85, 10.2), paint)
      ..drawLine(const Offset(7.92, 4.6), const Offset(7.35, 10.2), paint)
      ..drawLine(const Offset(3.4, 5.97), const Offset(9.7, 5.97), paint)
      ..drawLine(const Offset(3.3, 8.61), const Offset(9.6, 8.61), paint);
  }

  @override
  bool shouldRepaint(_TopicPainter oldDelegate) => false;
}
