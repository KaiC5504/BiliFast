import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show VideoCard;
import 'package:bili_core/logic.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../shared/remote_image.dart';
import '../shared/theme.dart';
import 'landscape_chrome.dart';
import 'player_ui.dart';

/// Hands a link to the share sheet.
typedef ShareLink = Future<void> Function(Uri link);

Future<void> shareWithSystem(Uri link) async {
  await SharePlus.instance.share(ShareParams(uri: link));
}

/// The full-screen end screen (BiliNative `EndScreens.swift`, measured on 27): back, 重播 and 分享, and a row of
/// related videos that rise in one after another. It fills the screen. The uploader, 充电鸣谢 and 点赞 投币 收藏 come
/// in later slices; their room is kept so nothing else moves when they do.
class EndScreenLandscape extends StatefulWidget {
  const EndScreenLandscape({super.key, required this.ui, this.share = shareWithSystem});

  final PlayerUi ui;

  /// Where 分享 sends the link; tests pass their own so nothing reaches the platform.
  final ShareLink share;

  @override
  State<EndScreenLandscape> createState() => _EndScreenLandscapeState();
}

class _EndScreenLandscapeState extends State<EndScreenLandscape> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();
  late final CurvedAnimation _fadeIn = CurvedAnimation(parent: _entrance, curve: const Interval(0, 0.4));

  @override
  void dispose() {
    _fadeIn.dispose();
    _entrance.dispose();
    super.dispose();
  }

  /// How far in [index]'s card is: each starts a little after the one before.
  double _cardProgress(int index) {
    final start = math.min(0.2 + index * 0.08, 0.6);
    return Curves.easeOutCubic.transform(((_entrance.value - start) / (1 - start)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final ui = widget.ui;
    final insets = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: ui.session,
      builder: (context, _) {
        final session = ui.session;
        final link = session.shareLink;
        final related = session.related;
        final rule = Padding(
          padding: EdgeInsets.only(left: insets.left, right: insets.right),
          child: const SizedBox(
            height: BiliMetrics.landscapeEndRule,
            width: double.infinity,
            child: ColoredBox(color: BiliColors.landscapeEndRule),
          ),
        );
        return FadeTransition(
          key: const ValueKey('end-landscape'),
          opacity: _fadeIn,
          child: DefaultTextStyle(
            style: fullScreenText,
            child: ColoredBox(
              color: BiliColors.landscapeEndDim,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        left: math.max(insets.left - 1, 0),
                        top: BiliMetrics.landscapeEndBackTop,
                        bottom: BiliMetrics.landscapeEndBackTop,
                      ),
                      child: FullScreenButton(
                        key: const ValueKey('end-back'),
                        label: '返回',
                        height: BiliMetrics.landscapeEndBackHeight,
                        onTap: ui.onBack,
                        child: const ChromeBackGlyph(),
                      ),
                    ),
                    rule,
                    SizedBox(
                      height: BiliMetrics.landscapeEndRow,
                      child: Padding(
                        padding: EdgeInsets.only(left: insets.left, right: insets.right),
                        child: Row(
                          children: [
                            const Spacer(),
                            _EndAction(
                              key: const ValueKey('end-replay'),
                              title: '重播',
                              glyph: const CustomPaint(
                                size: Size.square(BiliMetrics.landscapeEndActionIcon),
                                painter: _ReplayPainter(),
                              ),
                              onTap: () => unawaited(session.replay()),
                            ),
                            const SizedBox(width: BiliMetrics.landscapeEndDividerGap),
                            const SizedBox(
                              width: BiliMetrics.landscapeEndRule,
                              height: BiliMetrics.landscapeEndDividerHeight,
                              child: ColoredBox(color: BiliColors.landscapeEndRule),
                            ),
                            const SizedBox(width: BiliMetrics.landscapeEndDividerGap),
                            // 点赞, 投币 and 收藏 (a later slice) sit here.
                            const SizedBox(width: BiliMetrics.landscapeEndActionWidth * 3),
                            if (link != null)
                              _EndAction(
                                key: const ValueKey('end-share'),
                                title: '分享',
                                glyph: const CustomPaint(
                                  size: Size(BiliMetrics.landscapeEndShareWidth, BiliMetrics.landscapeEndShareHeight),
                                  painter: _SharePainter(),
                                ),
                                onTap: () => unawaited(widget.share(link)),
                              )
                            else
                              const SizedBox(width: BiliMetrics.landscapeEndActionWidth),
                          ],
                        ),
                      ),
                    ),
                    rule,
                    if (related.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.only(
                          left: insets.left + BiliMetrics.landscapeEndInset,
                          top: BiliMetrics.landscapeEndHeaderTop,
                        ),
                        child: const Text(
                          '推荐视频',
                          style: TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.landscapeEndHeaderText),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: insets.left,
                          right: insets.right,
                          top: BiliMetrics.landscapeEndRowTop,
                        ),
                        child: ClipRect(
                          child: SingleChildScrollView(
                            key: const ValueKey('end-related'),
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.landscapeEndInset),
                            child: AnimatedBuilder(
                              animation: _entrance,
                              builder: (context, _) => Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final (index, card) in related.indexed) ...[
                                    if (index > 0) const SizedBox(width: BiliMetrics.landscapeEndCardGap),
                                    Opacity(
                                      opacity: _cardProgress(index),
                                      child: Transform.translate(
                                        offset: Offset(0, (1 - _cardProgress(index)) * BiliMetrics.landscapeEndRise),
                                        child: _RelatedCard(card: card, onTap: () => session.playRelated(card)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EndAction extends StatelessWidget {
  const _EndAction({super.key, required this.title, required this.glyph, required this.onTap});

  final String title;
  final Widget glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChromePressable(
    label: title,
    onTap: onTap,
    child: SizedBox(
      width: BiliMetrics.landscapeEndActionWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: BiliMetrics.landscapeEndActionIcon,
            child: Center(child: glyph),
          ),
          const SizedBox(height: BiliMetrics.landscapeEndActionGap),
          Text(
            title,
            style: const TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.landscapeEndActionText),
          ),
        ],
      ),
    ),
  );
}

/// A related video's cover with its counts and duration on it, the title and the uploader, as in 27's row.
class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.card, required this.onTap});

  final VideoCard card;
  final VoidCallback onTap;

  static const _countStyle = TextStyle(
    color: BiliColors.chromeViews,
    fontSize: BiliMetrics.landscapeEndCountText,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Covers say 0:48, not 00:48.
  static String _duration(int seconds) {
    final text = TimeFormat.clock(seconds.toDouble());
    return text.length == 5 && text.startsWith('0') ? text.substring(1) : text;
  }

  @override
  Widget build(BuildContext context) => ChromePressable(
    label: card.title,
    onTap: onTap,
    child: SizedBox(
      width: BiliMetrics.landscapeEndCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(BiliMetrics.landscapeEndCoverRadius),
            child: SizedBox(
              width: BiliMetrics.landscapeEndCardWidth,
              height: BiliMetrics.landscapeEndCoverHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RemoteImage(card.cover, placeholder: const ColoredBox(color: BiliColors.landscapeEndPlaceholder)),
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      height: BiliMetrics.landscapeEndCoverShadeHeight,
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [BiliColors.chromeShadeClear, BiliColors.landscapeEndCoverShade],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: BiliMetrics.landscapeEndCoverInset,
                    right: BiliMetrics.landscapeEndCoverInset,
                    bottom: BiliMetrics.landscapeEndCoverBottom,
                    child: Row(
                      children: [
                        // On a cover too narrow for them all, the counts give way before the duration does.
                        Expanded(
                          child: ClipRect(
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.smart_display_outlined,
                                  size: BiliMetrics.landscapeEndCountIcon,
                                  color: BiliColors.chromeViews,
                                ),
                                const SizedBox(width: BiliMetrics.landscapeEndCountGap),
                                Flexible(
                                  child: Text(CountFormat.short(card.views), style: _countStyle, softWrap: false),
                                ),
                                const SizedBox(width: BiliMetrics.landscapeEndCountSpacing),
                                const Icon(
                                  Icons.subtitles_outlined,
                                  size: BiliMetrics.landscapeEndCountIcon,
                                  color: BiliColors.chromeViews,
                                ),
                                const SizedBox(width: BiliMetrics.landscapeEndCountGap),
                                Flexible(
                                  child: Text(CountFormat.short(card.danmaku), style: _countStyle, softWrap: false),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: BiliMetrics.landscapeEndCountGap),
                        Text(_duration(card.duration), style: _countStyle.copyWith(color: BiliColors.onVideo)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: BiliMetrics.landscapeEndCardTitleTop),
            child: Text(
              card.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.landscapeEndCardTitle),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: BiliMetrics.landscapeEndUploaderTop),
            child: Row(
              children: [
                Container(
                  height: BiliMetrics.upBadgeHeight,
                  padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.landscapeEndUpBadgePad),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: BiliColors.chromeSecondary),
                    borderRadius: BorderRadius.circular(BiliMetrics.landscapeEndUpBadgeRadius),
                  ),
                  child: const Text(
                    'UP',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: BiliColors.chromeSecondary,
                      fontSize: BiliMetrics.upBadgeText,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: BiliMetrics.landscapeEndCountGap),
                Expanded(
                  child: Text(
                    card.ownerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BiliColors.chromeSecondary,
                      fontSize: BiliMetrics.landscapeEndUploaderText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Paint _endStroke() => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = BiliMetrics.chromeLineStroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = BiliColors.onVideo;

/// A circle open at the upper right, its arrowhead at the top pointing clockwise.
class _ReplayPainter extends CustomPainter {
  const _ReplayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - BiliMetrics.chromeLineStroke;
    final paint = _endStroke();
    canvas.drawArc(Rect.fromCircle(center: centre, radius: radius), -math.pi / 2, -math.pi * 5 / 3, false, paint);
    final tip = Offset(centre.dx + radius * 0.25, centre.dy - radius);
    final head = radius * 0.42;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - head, tip.dy - head)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - head, tip.dy + head),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ReplayPainter oldDelegate) => false;
}

/// The outlined arrow that turns up and to the right.
class _SharePainter extends CustomPainter {
  const _SharePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final s = BiliMetrics.chromeLineStroke / 2;
    final neck = w * 0.6;
    canvas.drawPath(
      Path()
        ..moveTo(neck, s)
        ..lineTo(w - s, h * 0.45)
        ..lineTo(neck, h * 0.9 - s)
        ..lineTo(neck, h * 0.64)
        ..cubicTo(w * 0.32, h * 0.62, w * 0.14, h * 0.74, s, h - s)
        ..cubicTo(w * 0.08, h * 0.5, w * 0.28, h * 0.3, neck, h * 0.28)
        ..close(),
      _endStroke(),
    );
  }

  @override
  bool shouldRepaint(_SharePainter oldDelegate) => false;
}
