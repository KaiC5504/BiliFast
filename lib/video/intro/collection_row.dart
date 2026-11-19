import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

import '../../shared/in_sight.dart';
import '../../shared/menu.dart';
import '../../shared/theme.dart';
import '../player_session.dart' show Episode;

/// 合集 · name, with the playing episode's place (⫴ 221/221 >) (03). Opens the 选集 sheet.
class CollectionRow extends StatelessWidget {
  const CollectionRow({super.key, required this.title, required this.episodes, required this.onOpen});

  final String title;
  final List<Episode> episodes;
  final VoidCallback onOpen;

  /// "2/3", or just the count when none of them is playing (a later part of a listed video).
  static String place(List<Episode> episodes) {
    final index = episodes.indexWhere((episode) => episode.current);
    return index < 0 ? '${episodes.length}' : '${index + 1}/${episodes.length}';
  }

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) return const SizedBox.shrink();
    final place = CollectionRow.place(episodes);
    final radius = BorderRadius.circular(BiliMetrics.cardRadius);
    final titleStyle = TextStyle(
      fontFamily: BiliFonts.family,
      fontSize: IntroListTheme.collectionTitleText,
      color: BiliColors.text,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BiliMetrics.gutter,
        IntroListTheme.sectionTop,
        BiliMetrics.gutter,
        IntroListTheme.sectionBottom,
      ),
      child: Semantics(
        button: true,
        label: '合集 · $title',
        value: place,
        onTap: onOpen,
        excludeSemantics: true,
        child: ClipRRect(
          borderRadius: radius,
          child: PressHighlight(
            onTap: onOpen,
            child: Container(
              height: IntroListTheme.collectionHeight,
              color: PageTheme.chipFill,
              padding: const EdgeInsets.only(
                left: IntroListTheme.collectionLead,
                right: IntroListTheme.collectionTrailing,
              ),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '合集 · $title',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                        strutStyle: BiliFonts.strutOf(context, titleStyle),
                      ),
                    ),
                    const SizedBox(width: BiliMetrics.gutter),
                    PlayingBars(color: IntroListTheme.iconInk),
                    const SizedBox(width: IntroListTheme.collectionBarsGap),
                    Text(
                      place,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: BiliFonts.family,
                        fontSize: IntroListTheme.collectionPlaceText,
                        color: IntroListTheme.iconInk,
                      ),
                    ),
                    const SizedBox(width: IntroListTheme.collectionChevronGap),
                    Chevron(
                      size: const Size(IntroListTheme.collectionChevronWidth, IntroListTheme.collectionChevronHeight),
                      stroke: IntroListTheme.chevronStroke,
                      color: IntroListTheme.iconInk,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The official app's "now playing" mark, the APK's Lottie: three round-ended bars rising and falling out of step,
/// centred on the line. It moves all the time, the video paused or not, as the official one does, but only while it
/// is in sight, and at [IntroListTheme.barsFps]: each of its frames is a whole frame of the app, which a paused page
/// otherwise never draws. Reduce Motion holds it on font-check 02's frame.
class PlayingBars extends StatelessWidget {
  const PlayingBars({super.key, required this.color, this.height = IntroListTheme.barsHeight});

  static const asset = 'assets/lottie/detail_playing.json';

  /// Tests hold every mark still, as Reduce Motion does, or no pumpAndSettle under one would settle.
  @visibleForTesting
  static bool debugHoldStill = false;

  /// Parses the Lottie ahead of the first video page, whose marks would otherwise miss their first frames.
  static Future<void> precache() => AssetLottie(asset).load();

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scale = height / IntroListTheme.barsHeight;
    final comp = IntroListTheme.barsComp * scale;
    final still = debugHoldStill || MediaQuery.disableAnimationsOf(context);
    final bars = SizedBox(
      width: IntroListTheme.barsWidth * scale,
      height: height,
      child: OverflowBox(
        minWidth: comp,
        maxWidth: comp,
        minHeight: comp,
        maxHeight: comp,
        child: Lottie.asset(
          PlayingBars.asset,
          controller: still ? const AlwaysStoppedAnimation(IntroListTheme.barsStill) : null,
          // The held frame lies between two of the file's. Moving, the package's ticker waits on a timer between
          // frames at this rate, so no vsync in between draws anything.
          frameRate: still ? FrameRate.max : const FrameRate(IntroListTheme.barsFps),
          // Each frame repaints the mark's own layer, never the page's picture around it.
          addRepaintBoundary: true,
          delegates: LottieDelegates(
            values: [
              ValueDelegate.strokeColor(const ['**'], value: color),
            ],
          ),
          width: comp,
          height: comp,
        ),
      ),
    );
    return still ? bars : TickingInSight(child: bars);
  }
}

/// A thin › with round ends, as at the end of the official app's rows and chips.
class Chevron extends StatelessWidget {
  const Chevron({super.key, required this.size, required this.stroke, required this.color});

  final Size size;
  final double stroke;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: size, painter: _ChevronPainter(stroke, color));
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.stroke, this.color);

  final double stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = stroke / 2;
    canvas.drawPath(
      Path()
        ..moveTo(inset, inset)
        ..lineTo(size.width - inset, size.height / 2)
        ..lineTo(inset, size.height - inset),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.stroke != stroke || oldDelegate.color != color;
}
