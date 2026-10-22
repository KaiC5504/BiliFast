import 'dart:async';

import 'package:bili_core/api.dart' show VideoCard;
import 'package:bili_core/logic.dart' show CountFormat, TimeFormat;
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart' show Icons, Material, MaterialType;
import 'package:flutter/widgets.dart';

import '../../player_ui/end_screen_portrait.dart' show CountGlyph, CountPainter;
import '../../shared/menu.dart';
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../video_route.dart';

/// The related videos under 简介 (03, 18), as a sliver: cover with duration, title, UP and counts, and ⋮ 稍后再看.
/// The web list carries no recommendation reason (03's orange tags come from the app's own feed), so every row shows
/// the UP badge, as 18 does.
class RelatedSliver extends StatefulWidget {
  const RelatedSliver({super.key, required this.cards, required this.onOpen, required this.onWatchLater});

  final List<VideoCard> cards;
  final ValueChanged<VideoCard> onOpen;
  final ValueChanged<VideoCard> onWatchLater;

  /// Covers say 2:55, not 02:55.
  static String duration(int seconds) {
    final clock = TimeFormat.clock(seconds.toDouble());
    return clock.length == 5 && clock.startsWith('0') ? clock.substring(1) : clock;
  }

  @override
  State<RelatedSliver> createState() => _RelatedSliverState();
}

class _RelatedSliverState extends State<RelatedSliver> {
  /// Bumped for each new list, so its rows come in again; rows built later, while scrolling, just appear.
  int _generation = 0;
  bool _revealing = false;

  @override
  void initState() {
    super.initState();
    _revealing = widget.cards.isNotEmpty;
  }

  @override
  void didUpdateWidget(RelatedSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.cards.firstOrNull?.bvid;
    final now = widget.cards.firstOrNull?.bvid;
    if (now != null && now != before) {
      _generation++;
      _revealing = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    if (cards.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    if (_revealing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealing = false);
    }
    final revealing = _revealing && !MediaQuery.disableAnimationsOf(context);
    final seen = <String>{};
    final heroes = [for (final card in cards) seen.add(card.bvid)];
    return SliverPadding(
      padding: const EdgeInsets.only(top: IntroListTheme.sectionTop),
      sliver: SliverFixedExtentList.builder(
        itemExtent: IntroListTheme.relatedRowHeight,
        itemCount: cards.length,
        itemBuilder: (context, index) {
          final card = cards[index];
          final row = _RelatedRow(
            card: card,
            first: index == 0,
            hero: heroes[index],
            onOpen: () => widget.onOpen(card),
            onWatchLater: () => widget.onWatchLater(card),
          );
          return KeyedSubtree(
            key: ValueKey((_generation, card.bvid)),
            child: revealing && index < IntroListTheme.revealRows
                ? _Reveal(delay: IntroListTheme.revealStagger * index, child: row)
                : row,
          );
        },
      ),
    );
  }
}

class _RelatedRow extends StatelessWidget {
  const _RelatedRow({
    required this.card,
    required this.first,
    required this.hero,
    required this.onOpen,
    required this.onWatchLater,
  });

  final VideoCard card;
  final bool first;
  final bool hero;
  final VoidCallback onOpen;
  final VoidCallback onWatchLater;

  static const _textLeft = BiliMetrics.gutter + IntroListTheme.relatedCoverWidth + IntroListTheme.relatedTextGap;
  static const _coverTop = IntroListTheme.relatedCoverTop;

  TextStyle get _meta => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: IntroListTheme.relatedMetaText,
    height: 1,
    color: BiliColors.secondaryText,
  );

  TextStyle get _count => _meta.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    final cover = RemoteImage(
      card.cover,
      size: const Size(IntroListTheme.relatedCoverWidth, IntroListTheme.relatedCoverHeight),
      cover: true,
    );
    final title = TextStyle(
      fontFamily: BiliFonts.family,
      fontSize: IntroListTheme.relatedTitleText,
      height: IntroListTheme.relatedTitleLine / IntroListTheme.relatedTitleText,
      color: BiliColors.text,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              button: true,
              label: card.title,
              onTap: onOpen,
              excludeSemantics: true,
              child: PressHighlight(
                onTap: onOpen,
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: first ? 0 : IntroListTheme.relatedDividerInset,
                      right: 0,
                      height: BiliMetrics.panelHairline,
                      child: const ColoredBox(color: BiliColors.divider),
                    ),
                    Positioned(
                      left: BiliMetrics.gutter,
                      top: _coverTop,
                      width: IntroListTheme.relatedCoverWidth,
                      height: IntroListTheme.relatedCoverHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(IntroListTheme.relatedCoverRadius),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (hero) Hero(tag: VideoRoute.coverTag(card.bvid), child: cover) else cover,
                            if (card.duration > 0)
                              Positioned(
                                right: IntroListTheme.durationInset,
                                bottom: IntroListTheme.durationInset,
                                height: IntroListTheme.durationHeight,
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(horizontal: IntroListTheme.durationPad),
                                  decoration: BoxDecoration(
                                    color: IntroListTheme.durationFill,
                                    borderRadius: BorderRadius.circular(IntroListTheme.durationRadius),
                                  ),
                                  child: Text(
                                    RelatedSliver.duration(card.duration),
                                    style: TextStyle(
                                      fontFamily: BiliFonts.family,
                                      fontSize: IntroListTheme.durationText,
                                      height: 1,
                                      color: BiliColors.onCover,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: _textLeft,
                      right: BiliMetrics.gutter,
                      top: _coverTop - IntroListTheme.relatedTitleLift,
                      child: Text(
                        card.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: title,
                        strutStyle: BiliFonts.strut(title),
                      ),
                    ),
                    _line(
                      IntroListTheme.relatedUploaderCentre,
                      right: BiliMetrics.gutter,
                      Row(
                        children: [
                          const _UpBadge(),
                          const SizedBox(width: IntroListTheme.relatedMetaGap),
                          Flexible(
                            child: Text(
                              card.ownerName,
                              style: _meta,
                              strutStyle: BiliFonts.strut(_meta),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _line(
                      IntroListTheme.relatedCountsCentre,
                      right: IntroListTheme.moreCentreFromRight + IntroListTheme.moreTarget / 2,
                      Row(
                        children: [
                          const _CountIcon(CountGlyph.views),
                          const SizedBox(width: IntroListTheme.relatedMetaGap),
                          Text(CountFormat.short(card.views), style: _count, strutStyle: BiliFonts.strut(_count)),
                          const SizedBox(width: IntroListTheme.relatedCountSpacing),
                          const _CountIcon(CountGlyph.danmaku),
                          const SizedBox(width: IntroListTheme.relatedMetaGap),
                          Text(CountFormat.short(card.danmaku), style: _count, strutStyle: BiliFonts.strut(_count)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: IntroListTheme.moreCentreFromRight - IntroListTheme.moreTarget / 2,
            top: _coverTop + IntroListTheme.relatedCountsCentre - IntroListTheme.moreTarget / 2,
            width: IntroListTheme.moreTarget,
            height: IntroListTheme.moreTarget,
            child: _More(onWatchLater: onWatchLater),
          ),
        ],
      ),
    );
  }

  /// A line of meta text centred [centre] below the cover's top.
  static Widget _line(double centre, Widget child, {required double right}) => Positioned(
    left: _textLeft + IntroListTheme.relatedMetaLead,
    right: right,
    top: _coverTop + centre - IntroListTheme.relatedMetaLine / 2,
    height: IntroListTheme.relatedMetaLine,
    child: child,
  );
}

class _UpBadge extends StatelessWidget {
  const _UpBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: BiliMetrics.endUpWidth,
    height: BiliMetrics.endUpHeight,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: BiliColors.secondaryText, width: BiliMetrics.endUpBorder),
      borderRadius: BorderRadius.circular(BiliMetrics.endUpRadius),
    ),
    child: Text(
      'UP',
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontFamily: BiliFonts.family,
        color: BiliColors.secondaryText,
        fontSize: BiliMetrics.endUpFont,
        fontWeight: FontWeight.bold,
        height: 1,
      ),
    ),
  );
}

class _CountIcon extends StatelessWidget {
  const _CountIcon(this.glyph);

  final CountGlyph glyph;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(BiliMetrics.endCountIconWidth, BiliMetrics.endCountIconHeight),
    painter: CountPainter(glyph, color: BiliColors.secondaryText),
  );
}

class _More extends StatelessWidget {
  const _More({required this.onWatchLater});

  final VoidCallback onWatchLater;

  void _open(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    unawaited(
      Navigator.of(context).push(
        _RelatedMenuRoute(
          anchor: anchor,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          onWatchLater: onWatchLater,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '更多',
    onTap: () => _open(context),
    excludeSemantics: true,
    child: GestureDetector(
      key: const ValueKey('related-more'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: const Center(
        child: CustomPaint(
          size: Size(IntroListTheme.moreDot, IntroListTheme.moreDot * 3 + IntroListTheme.moreDotGap * 2),
          painter: _DotsPainter(),
        ),
      ),
    ),
  );
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = BiliColors.secondaryText;
    const radius = IntroListTheme.moreDot / 2;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(radius, radius + i * (IntroListTheme.moreDot + IntroListTheme.moreDotGap)),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => false;
}

/// ⋮'s menu, as the feed card's: frosted glass growing out of the dots, below them or, near the bottom, above.
class _RelatedMenuRoute extends PopupRoute<void> {
  _RelatedMenuRoute({required this.anchor, required this.reduceMotion, required this.onWatchLater});

  final Rect anchor;
  final bool reduceMotion;
  final VoidCallback onWatchLater;

  static const _height = BiliMetrics.menuRowHeight;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => reduceMotion ? Duration.zero : const Duration(milliseconds: 150);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final below =
        anchor.bottom + BiliMetrics.cardMenuGap + _height <= screen.height - padding.bottom - BiliMetrics.gutter;
    final left = clampDouble(
      anchor.right - BiliMetrics.cardMenuWidth,
      BiliMetrics.gutter,
      screen.width - BiliMetrics.gutter - BiliMetrics.cardMenuWidth,
    );
    return Stack(
      children: [
        Positioned(
          left: left,
          top: below ? anchor.bottom + BiliMetrics.cardMenuGap : anchor.top - BiliMetrics.cardMenuGap - _height,
          child: ScaleTransition(
            alignment: below ? Alignment.topRight : Alignment.bottomRight,
            scale: Tween(begin: 0.8, end: 1.0).animate(animation),
            child: FadeTransition(
              opacity: animation,
              child: Material(
                type: MaterialType.transparency,
                child: GlassPanel(
                  width: BiliMetrics.cardMenuWidth,
                  child: MenuRow(
                    key: const ValueKey('related-watch-later'),
                    title: '稍后再看',
                    icon: Icons.schedule,
                    onTap: () {
                      Navigator.of(context).pop();
                      onWatchLater();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;

  CurvedAnimation? _curve;

  @override
  Animation<double> createAnimation() =>
      _curve = CurvedAnimation(parent: super.createAnimation(), curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }
}

/// Fades a row in while it rises into place, after [delay].
class _Reveal extends StatefulWidget {
  const _Reveal({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: widget.delay + IntroListTheme.revealDuration,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _in,
    curve: Interval(widget.delay.inMicroseconds / _in.duration!.inMicroseconds, 1, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    _in.forward().ignore();
  }

  @override
  void dispose() {
    _curve.dispose();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _curve.value,
      child: Transform.translate(offset: Offset(0, (1 - _curve.value) * IntroListTheme.revealRise), child: child),
    ),
  );
}
