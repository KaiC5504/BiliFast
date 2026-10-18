import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/logic.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../video/video_route.dart';
import 'avatar_menu.dart';

/// Card sizes that depend on the text size, so the grid can give every card the same height.
abstract final class FeedCardSize {
  static const _lineHeight = 1.3;

  static double titleHeight(TextScaler scaler) => scaler.scale(BiliMetrics.cardTitleText) * _lineHeight * 2;

  /// The tag, uploader and ⋮ row with its gaps. Its text keeps one size, as Swift's fixed `.system(size:)` did.
  static const footerHeight = BiliMetrics.cardFooterInset * 2 + BiliMetrics.cardTagHeight;

  /// The whole card for a column [width] wide: 4:3 cover, two title lines, the footer and their gaps.
  static double height(double width, TextScaler scaler) =>
      width / BiliMetrics.coverAspect + BiliMetrics.cardTitleTop + titleHeight(scaler) + footerHeight;
}

/// One 推荐 card (01, port of FeedCard.swift): the cover with counts and duration, a two-line title, and the tag,
/// uploader and ⋮ footer. It gives a little under the finger.
class FeedCardView extends StatefulWidget {
  const FeedCardView({super.key, required this.card, required this.onOpen, required this.onWatchLater});

  final FeedCard card;
  final VoidCallback onOpen;
  final VoidCallback onWatchLater;

  /// Covers say 0:18, not 00:18 (01).
  static String duration(int seconds) {
    final clock = TimeFormat.clock(seconds.toDouble());
    return clock.startsWith('0') && clock.length == 5 ? clock.substring(1) : clock;
  }

  @override
  State<FeedCardView> createState() => _FeedCardViewState();
}

class _FeedCardViewState extends State<FeedCardView> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final scaler = MediaQuery.textScalerOf(context);
    // One element for VoiceOver, named by the title; ⋮'s 稍后再看 is its action.
    return Semantics(
      button: true,
      label: card.title,
      onTap: widget.onOpen,
      customSemanticsActions: {const CustomSemanticsAction(label: '稍后再看'): widget.onWatchLater},
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onOpen,
        child: AnimatedScale(
          scale: _pressed ? BiliMetrics.pressedScale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(BiliMetrics.cardRadius),
            child: ColoredBox(
              color: BiliColors.card,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Cover(card: card),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: BiliMetrics.cardInset,
                      right: BiliMetrics.cardInset,
                      top: BiliMetrics.cardTitleTop,
                    ),
                    child: SizedBox(
                      height: FeedCardSize.titleHeight(scaler),
                      child: Text(
                        card.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: BiliMetrics.cardTitleText,
                          color: BiliColors.text,
                          height: FeedCardSize._lineHeight,
                        ),
                      ),
                    ),
                  ),
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1,
                    child: SizedBox(
                      height: FeedCardSize.footerHeight,
                      child: Padding(
                        padding: const EdgeInsets.only(left: BiliMetrics.cardInset),
                        child: Row(
                          children: [
                            _Badge(card: card),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                card.ownerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: BiliMetrics.cardFooterText,
                                  color: BiliColors.secondaryText,
                                ),
                              ),
                            ),
                            _More(onWatchLater: widget.onWatchLater),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.card});

  final FeedCard card;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: BiliMetrics.coverAspect,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Hero(tag: VideoRoute.coverTag(card.bvid), child: RemoteImage(card.cover)),
        const Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: BiliMetrics.coverShadeHeight,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [BiliColors.chromeShadeClear, BiliColors.coverShade],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: BiliMetrics.cardInset,
          right: BiliMetrics.cardInset,
          bottom: 6,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1,
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: BiliFonts.family,
                fontSize: BiliMetrics.cardStatText,
                color: BiliColors.onCover,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              // On a card too narrow for them all, the counts give way before the duration does.
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.smart_display_outlined,
                          size: BiliMetrics.cardStatIcon,
                          color: BiliColors.onCover,
                        ),
                        const SizedBox(width: 3),
                        Flexible(child: Text(CountFormat.short(card.views))),
                        const SizedBox(width: 10),
                        const Icon(Icons.subtitles_outlined, size: BiliMetrics.cardStatIcon, color: BiliColors.onCover),
                        const SizedBox(width: 3),
                        Flexible(child: Text(CountFormat.short(card.danmaku))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(FeedCardView.duration(card.duration)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.card});

  final FeedCard card;

  @override
  Widget build(BuildContext context) {
    final reason = card.reason;
    if (reason != null && reason.isNotEmpty) return _Tag(reason);
    if (card.isVertical) return const _Tag('竖屏');
    return const UpBadge();
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    height: BiliMetrics.cardTagHeight,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: BiliColors.reasonTint, borderRadius: BorderRadius.circular(2)),
    child: Text(
      text,
      maxLines: 1,
      style: const TextStyle(fontSize: BiliMetrics.cardTagText, color: BiliColors.reason, height: 1),
    ),
  );
}

class UpBadge extends StatelessWidget {
  const UpBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: BiliMetrics.upBadgeHeight,
    padding: const EdgeInsets.symmetric(horizontal: 2),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: BiliColors.secondaryText),
      borderRadius: BorderRadius.circular(2.5),
    ),
    child: const Text(
      'UP',
      style: TextStyle(
        fontSize: BiliMetrics.upBadgeText,
        fontWeight: FontWeight.bold,
        color: BiliColors.secondaryText,
        height: 1,
      ),
    ),
  );
}

/// The ⋮ at the end of the footer, Swift's 24 × 24 target.
class _More extends StatelessWidget {
  const _More({required this.onWatchLater});

  final VoidCallback onWatchLater;

  void _open(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    unawaited(
      Navigator.of(context).push(
        _CardMenuRoute(
          anchor: anchor,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          onWatchLater: onWatchLater,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('card-more'),
    behavior: HitTestBehavior.opaque,
    onTap: () => _open(context),
    child: const SizedBox.square(
      dimension: BiliMetrics.cardMoreTarget,
      child: Icon(Icons.more_vert, size: BiliMetrics.cardFooterText + 4, color: BiliColors.secondaryText),
    ),
  );
}

/// ⋮'s menu (Swift's Menu): frosted glass growing out of the button, below it or, near the bottom, above; a tap
/// anywhere else closes it.
class _CardMenuRoute extends PopupRoute<void> {
  _CardMenuRoute({required this.anchor, required this.reduceMotion, required this.onWatchLater});

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
              // The route sits outside the page's Material, whose text style the row would otherwise miss.
              child: Material(
                type: MaterialType.transparency,
                child: GlassPanel(
                  width: BiliMetrics.cardMenuWidth,
                  child: MenuRow(
                    key: const ValueKey('card-watch-later'),
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

/// A card's outline while the first page loads, a light band sweeping across it.
class FeedCardSkeleton extends StatelessWidget {
  const FeedCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(BiliMetrics.cardRadius),
      child: ColoredBox(
        color: BiliColors.card,
        // Inside the card, so the sweep lights only the grey shapes and not the white around them.
        child: Shimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AspectRatio(
                aspectRatio: BiliMetrics.coverAspect,
                child: ColoredBox(color: BiliColors.shimmerBase),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: BiliMetrics.cardInset,
                  right: BiliMetrics.cardInset * 3,
                  top: BiliMetrics.cardTitleTop,
                ),
                child: SizedBox(
                  height: FeedCardSize.titleHeight(scaler),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Bar(),
                      FractionallySizedBox(widthFactor: 0.6, child: _Bar()),
                    ],
                  ),
                ),
              ),
              const SizedBox(
                height: FeedCardSize.footerHeight,
                child: Padding(
                  padding: EdgeInsets.only(left: BiliMetrics.cardInset),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(widthFactor: 0.4, child: _Bar()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext context) => Container(
    height: 12,
    decoration: BoxDecoration(color: BiliColors.shimmerBase, borderRadius: BorderRadius.circular(3)),
  );
}

/// Sweeps a light band across [child] every 1.3 s; still when the system asks for less motion.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      unawaited(_sweep.repeat());
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sweep.isAnimating) return widget.child;
    return AnimatedBuilder(
      animation: _sweep,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final at = -1.0 + _sweep.value * 3;
          return LinearGradient(
            begin: Alignment(at - 1, -0.3),
            end: Alignment(at + 1, 0.3),
            colors: const [BiliColors.shimmerBase, BiliColors.shimmerHighlight, BiliColors.shimmerBase],
            stops: const [0.35, 0.5, 0.65],
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}
