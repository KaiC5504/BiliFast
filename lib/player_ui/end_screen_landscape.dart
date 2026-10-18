import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show VideoCard, VideoOwner;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/logic.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import 'end_screen_portrait.dart' show ShareLink, shareThroughSystem;
import 'landscape_chrome.dart';
import 'player_ui.dart';
import 'portrait_controls.dart';

/// The full-screen end screen (BiliNative `EndScreens.swift`, measured on 27): back, the uploader, 重播 and 分享, and a
/// row of related videos that rise in one after another. It fills the screen. 充电鸣谢, 充电, 关注 and 点赞 投币 收藏
/// (slice 6) have their room kept so nothing else moves when they come.
class EndScreenLandscape extends StatefulWidget {
  const EndScreenLandscape({super.key, required this.ui, this.share = shareThroughSystem});

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

  Future<void> _share(Uri link) async {
    try {
      await widget.share(link);
    } on Object catch (error) {
      Logger.shared.warn(LogCategory.ui, 'share failed', {'error': '${error.runtimeType}'});
      if (mounted) showToast(context, '分享失败');
    }
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
        final owner = session.detail?.owner;
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
                      padding: EdgeInsets.only(left: insets.left),
                      child: ChromeTap(
                        key: const ValueKey('end-back'),
                        label: '返回',
                        onTap: ui.onBack,
                        child: const BackGlyph(),
                      ),
                    ),
                    rule,
                    SizedBox(
                      height: BiliMetrics.landscapeEndRow,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: insets.left,
                          right: math.max(insets.right - BiliMetrics.landscapeEndActionsOutset, 0),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: owner == null ? const SizedBox.shrink() : _Uploader(owner: owner)),
                            _EndAction(
                              key: const ValueKey('end-replay'),
                              title: '重播',
                              glyph: const CustomPaint(
                                size: Size(BiliMetrics.replayGlyphWidth, BiliMetrics.replayGlyphHeight),
                                painter: _ReplayPainter(),
                              ),
                              onTap: () => unawaited(session.replay()),
                            ),
                            const SizedBox(width: BiliMetrics.landscapeEndDividerGap),
                            const SizedBox(
                              key: ValueKey('end-divider'),
                              width: BiliMetrics.landscapeEndRule,
                              height: BiliMetrics.landscapeEndDividerHeight,
                              child: ColoredBox(color: BiliColors.landscapeEndRule),
                            ),
                            const SizedBox(width: BiliMetrics.landscapeEndDividerGap),
                            // 点赞, 投币 and 收藏 (slice 6) sit here.
                            const SizedBox(width: BiliMetrics.landscapeEndActionWidth * 3),
                            if (link != null)
                              _EndAction(
                                key: const ValueKey('end-share'),
                                title: '分享',
                                glyph: const CustomPaint(
                                  size: Size(BiliMetrics.shareGlyphWidth, BiliMetrics.shareGlyphHeight),
                                  painter: _SharePainter(),
                                ),
                                onTap: () => unawaited(_share(link)),
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

/// The uploader's ringed avatar and name; 充电 and 关注 (slice 6) go under the name.
class _Uploader extends StatelessWidget {
  const _Uploader({required this.owner});

  final VideoOwner owner;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('end-uploader'),
    children: [
      const SizedBox(width: BiliMetrics.landscapeEndAvatarInset),
      Container(
        width: BiliMetrics.landscapeEndAvatar,
        height: BiliMetrics.landscapeEndAvatar,
        padding: const EdgeInsets.all(BiliMetrics.landscapeEndAvatarRing),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: BiliColors.onVideo, width: BiliMetrics.landscapeEndAvatarRing),
        ),
        child: ClipOval(
          child: RemoteImage(
            owner.face,
            size: const Size.square(BiliMetrics.landscapeEndAvatar),
            placeholder: const ColoredBox(color: BiliColors.landscapeEndPlaceholder),
          ),
        ),
      ),
      const SizedBox(width: BiliMetrics.landscapeEndAvatarGap),
      Expanded(
        child: SizedBox(
          height: BiliMetrics.landscapeEndAvatar,
          child: Text(
            owner.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.landscapeEndNameText),
          ),
        ),
      ),
    ],
  );
}

class _EndAction extends StatelessWidget {
  const _EndAction({super.key, required this.title, required this.glyph, required this.onTap});

  final String title;
  final Widget glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChromeTap(
    label: title,
    square: false,
    onTap: onTap,
    child: SizedBox(
      width: BiliMetrics.landscapeEndActionWidth,
      height: BiliMetrics.landscapeEndRow,
      child: Column(
        children: [
          const SizedBox(height: BiliMetrics.landscapeEndActionTop),
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
  Widget build(BuildContext context) => ChromeTap(
    label: card.title,
    square: false,
    onTap: onTap,
    child: SizedBox(
      width: BiliMetrics.landscapeEndCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(BiliMetrics.endCoverRadius),
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
                      height: BiliMetrics.endCoverShadeHeight,
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [BiliColors.chromeShadeClear, BiliColors.endCoverShade],
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
              style: const TextStyle(
                color: BiliColors.onVideo,
                fontSize: BiliMetrics.landscapeEndCardTitle,
                height: BiliMetrics.landscapeEndCardTitleLeading,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: BiliMetrics.landscapeEndUploaderTop),
            child: Row(
              children: [
                Container(
                  width: BiliMetrics.endUpWidth,
                  height: BiliMetrics.endUpHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: BiliColors.endMeta, width: BiliMetrics.endUpBorder),
                    borderRadius: BorderRadius.circular(BiliMetrics.endUpRadius),
                  ),
                  child: const Text(
                    'UP',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: BiliColors.endMeta,
                      fontSize: BiliMetrics.endUpFont,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: BiliMetrics.endMetaGap),
                Expanded(
                  child: Text(
                    card.ownerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: BiliColors.endMeta, fontSize: BiliMetrics.landscapeEndUploaderText),
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
  ..strokeWidth = BiliMetrics.chromeGlyphStroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = BiliColors.onVideo;

/// 重播 on 27, traced on its 21 × 18 box: a ring open at the lower right, its arrowhead at three o'clock pointing
/// on round.
class _ReplayPainter extends CustomPainter {
  const _ReplayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / BiliMetrics.replayGlyphWidth, sy = size.height / BiliMetrics.replayGlyphHeight;
    Offset p(double x, double y) => Offset(x * sx, y * sy);
    const start = 46 * math.pi / 180;
    const sweep = 306 * math.pi / 180;
    final left = p(14.8, 8.45), tip = p(17.5, 11.55), right = p(20.2, 8.45);
    final path = Path()
      ..addArc(Rect.fromPoints(p(0.85, 1), p(16.85, 17)), start, sweep)
      ..moveTo(left.dx, left.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy);
    canvas.drawPath(path, _endStroke());
  }

  @override
  bool shouldRepaint(_ReplayPainter oldDelegate) => false;
}

/// 分享 on 27, traced on its 20 × 17 box: the outlined arrow turning up and to the right.
class _SharePainter extends CustomPainter {
  const _SharePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / BiliMetrics.shareGlyphWidth, sy = size.height / BiliMetrics.shareGlyphHeight;
    Offset p(double x, double y) => Offset(x * sx, y * sy);
    final neckTop = p(9.3, 5.3), neckBottom = p(9.6, 10.9), tail = p(0.9, 13.4);
    final lower = p(4.85, 10.5), upper = p(1.5, 6.3);
    final points = [p(9.9, 0.9), p(18.9, 7.8), p(9.9, 14.5)];
    final path = Path()..moveTo(neckTop.dx, neckTop.dy);
    for (final point in points) {
      path.lineTo(point.dx, point.dy);
    }
    path
      ..lineTo(neckBottom.dx, neckBottom.dy)
      ..quadraticBezierTo(lower.dx, lower.dy, tail.dx, tail.dy)
      ..quadraticBezierTo(upper.dx, upper.dy, neckTop.dx, neckTop.dy)
      ..close();
    canvas.drawPath(path, _endStroke());
  }

  @override
  bool shouldRepaint(_SharePainter oldDelegate) => false;
}
