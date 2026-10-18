import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show VideoCard;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/logic.dart' show CountFormat, TimeFormat;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../video/player_session.dart';
import 'panels/panel_controller.dart';
import 'player_ui.dart';
import 'portrait_controls.dart';

/// Hands a link to the share sheet.
typedef ShareLink = Future<void> Function(Uri link);

Future<void> shareThroughSystem(Uri link) async {
  await SharePlus.instance.share(ShareParams(uri: link));
}

/// The small player's end screen (BiliNative `EndScreens.swift`, laid out as the official app's 26): the last frame
/// dimmed, back and ⋮, 推荐视频 with the first related video and 立即播放, then 重播 and 分享. It fills the player and
/// its parts rise in one after another.
class EndScreenPortrait extends StatefulWidget {
  const EndScreenPortrait({super.key, required this.ui, this.share = shareThroughSystem});

  final PlayerUi ui;

  /// Tests pass their own so nothing reaches the platform.
  final ShareLink share;

  @override
  State<EndScreenPortrait> createState() => _EndScreenPortraitState();
}

class _EndScreenPortraitState extends State<EndScreenPortrait> with SingleTickerProviderStateMixin {
  late final _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();

  PlayerUi get _ui => widget.ui;
  PlayerSession get _session => widget.ui.session;

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Animation<double> _stage(double from, double to) =>
      CurvedAnimation(parent: _entrance, curve: Interval(from, to, curve: Curves.easeOutCubic));

  VoidCallback _tap(VoidCallback action) => () {
    _ui.chrome.show();
    action();
  };

  void _share() {
    final link = _session.shareLink;
    if (link == null) return;
    unawaited(
      widget.share(link).catchError((Object error) {
        Logger.shared.warn(LogCategory.ui, 'share failed', {'error': '${error.runtimeType}'});
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final card = _session.related.firstOrNull;
        return Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(opacity: _stage(0, 0.45), child: const ColoredBox(color: BiliColors.endDim)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Rise(
                  animation: _stage(0.1, 0.6),
                  child: Row(
                    children: [
                      ChromeTap(
                        key: const ValueKey('end-back'),
                        label: '返回',
                        onTap: _tap(_ui.onBack),
                        child: const BackGlyph(),
                      ),
                      const Spacer(),
                      ChromeTap(
                        key: const ValueKey('end-more'),
                        label: '更多',
                        onTap: _tap(() => _ui.panels.open(PlayerPanel.more)),
                        child: const MoreDots(),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (card != null)
                  _Rise(
                    animation: _stage(0.2, 0.8),
                    child: _Recommended(card: card, onPlay: _tap(() => _session.playRelated(card))),
                  ),
                const Spacer(),
                _Rise(
                  animation: _stage(0.35, 1),
                  child: Padding(
                    padding: const EdgeInsets.only(left: BiliMetrics.endActionsLeading),
                    child: Row(
                      spacing: BiliMetrics.endActionSpacing,
                      children: [
                        _EndAction(
                          key: const ValueKey('end-replay'),
                          title: '重播',
                          glyph: const _ReplayGlyph(),
                          onTap: _tap(() => unawaited(_session.replay())),
                        ),
                        if (_session.shareLink != null)
                          _EndAction(
                            key: const ValueKey('end-share'),
                            title: '分享',
                            glyph: const _ShareGlyph(),
                            onTap: _tap(_share),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Rise extends StatelessWidget {
  const _Rise({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => Opacity(
      opacity: animation.value.clamp(0, 1),
      child: Transform.translate(offset: Offset(0, (1 - animation.value) * BiliMetrics.endRise), child: child),
    ),
    child: child,
  );
}

/// 推荐视频 and its one card: the cover, the title, the uploader and counts, and 立即播放.
class _Recommended extends StatelessWidget {
  const _Recommended({required this.card, required this.onPlay});

  final VideoCard card;
  final VoidCallback onPlay;

  static const _caption = TextStyle(color: BiliColors.endCaption, fontSize: BiliMetrics.endCaptionFont, height: 1);
  static const _title = TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.endTitleFont, height: 1.2);
  static const _meta = TextStyle(color: BiliColors.endMeta, fontSize: BiliMetrics.endMetaFont, height: 1);
  static const _button = TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.endButtonFont, height: 1);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: BiliMetrics.endInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('推荐视频', style: _caption),
          const SizedBox(height: BiliMetrics.endCaptionGap),
          SizedBox(
            height: BiliMetrics.endCoverHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ChromeTap(
                  key: const ValueKey('end-cover'),
                  label: '播放：${card.title}',
                  square: false,
                  onTap: onPlay,
                  child: _Cover(card: card),
                ),
                const SizedBox(width: BiliMetrics.endCoverGap),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: Text(card.title, style: _title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: BiliMetrics.endUploaderTop,
                        height: BiliMetrics.endMetaRow,
                        child: Row(
                          spacing: BiliMetrics.endMetaGap,
                          children: [
                            const _UpBadge(),
                            Flexible(
                              child: Text(card.ownerName, style: _meta, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: BiliMetrics.endCountsTop,
                        height: BiliMetrics.endMetaRow,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.smart_display_outlined,
                              size: BiliMetrics.endMetaIcon,
                              color: BiliColors.endMeta,
                            ),
                            const SizedBox(width: BiliMetrics.endMetaGap),
                            Text(CountFormat.short(card.views), style: _meta),
                            const SizedBox(width: BiliMetrics.endMetaSpacing),
                            const Icon(
                              Icons.subtitles_outlined,
                              size: BiliMetrics.endMetaIcon,
                              color: BiliColors.endMeta,
                            ),
                            const SizedBox(width: BiliMetrics.endMetaGap),
                            Text(CountFormat.short(card.danmaku), style: _meta),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                ChromeTap(
                  key: const ValueKey('end-play-now'),
                  label: '立即播放',
                  square: false,
                  onTap: onPlay,
                  child: Container(
                    width: BiliMetrics.endButtonWidth,
                    height: BiliMetrics.endButtonHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BiliColors.endButton,
                      borderRadius: BorderRadius.circular(BiliMetrics.endButtonHeight / 2),
                    ),
                    child: const Text('立即播放', style: _button, maxLines: 1, softWrap: false),
                  ),
                ),
                const SizedBox(width: BiliMetrics.endButtonTrailing),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.card});

  final VideoCard card;

  static const _time = TextStyle(
    color: BiliColors.onVideo,
    fontSize: BiliMetrics.endCoverTimeFont,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );

  /// Covers say 0:48, not 00:48.
  static String _clock(int seconds) {
    final clock = TimeFormat.clock(seconds.toDouble());
    return clock.length == 5 && clock.startsWith('0') ? clock.substring(1) : clock;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(BiliMetrics.endCoverRadius),
      child: SizedBox(
        width: BiliMetrics.endCoverWidth,
        height: BiliMetrics.endCoverHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RemoteImage(card.cover, size: const Size(BiliMetrics.endCoverWidth, BiliMetrics.endCoverHeight)),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: BiliMetrics.endCoverShadeHeight,
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
            Positioned(
              right: BiliMetrics.endCoverTextInset,
              bottom: BiliMetrics.endCoverTextBottom,
              child: Text(_clock(card.duration), style: _time),
            ),
            Center(
              child: CustomPaint(
                size: const Size(BiliMetrics.endPlayGlyphWidth, BiliMetrics.endPlayGlyphHeight),
                painter: PlayPausePainter(const AlwaysStoppedAnimation(0), color: BiliColors.endPlayGlyph),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpBadge extends StatelessWidget {
  const _UpBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: BiliMetrics.endUpWidth,
    height: BiliMetrics.endUpHeight,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: BiliColors.endMeta, width: BiliMetrics.endUpBorder),
      borderRadius: BorderRadius.circular(BiliMetrics.endUpRadius),
    ),
    child: const Text(
      'UP',
      style: TextStyle(
        color: BiliColors.endMeta,
        fontSize: BiliMetrics.endUpFont,
        fontWeight: FontWeight.bold,
        height: 1,
      ),
    ),
  );
}

class _EndAction extends StatelessWidget {
  const _EndAction({super.key, required this.title, required this.glyph, required this.onTap});

  final String title;
  final Widget glyph;
  final VoidCallback onTap;

  static const _style = TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.endActionFont, height: 1);

  @override
  Widget build(BuildContext context) {
    return ChromeTap(
      label: title,
      square: false,
      onTap: onTap,
      child: SizedBox(
        height: BiliMetrics.chromeButton,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: BiliMetrics.endActionGap,
          children: [glyph, Text(title, style: _style)],
        ),
      ),
    );
  }
}

Paint _endStroke() => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = BiliMetrics.chromeGlyphStroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = BiliColors.onVideo;

/// 重播: a circle open at the lower right, its arrowhead at three o'clock pointing on round (26).
class _ReplayGlyph extends StatelessWidget {
  const _ReplayGlyph();

  @override
  Widget build(BuildContext context) => const CustomPaint(
    size: Size(BiliMetrics.replayGlyphWidth, BiliMetrics.replayGlyphHeight),
    painter: _ReplayPainter(),
  );
}

class _ReplayPainter extends CustomPainter {
  const _ReplayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Proportions measured on 26 at 8×: a ring of 0.45 of the height, open from 46° round to -8°, and a chevron whose
    // tip sits just outside the ring at three o'clock.
    final unit = size.height / 18;
    final centre = Offset(8.85 * unit, 9 * unit);
    final radius = 8 * unit;
    const start = 46 * math.pi / 180;
    const sweep = 306 * math.pi / 180;
    final path = Path()
      ..addArc(Rect.fromCircle(center: centre, radius: radius), start, sweep)
      ..moveTo(centre.dx + 5.95 * unit, centre.dy - 0.55 * unit)
      ..lineTo(centre.dx + 8.65 * unit, centre.dy + 2.55 * unit)
      ..lineTo(centre.dx + 11.35 * unit, centre.dy - 0.55 * unit);
    canvas.drawPath(path, _endStroke());
  }

  @override
  bool shouldRepaint(_ReplayPainter oldDelegate) => false;
}

/// 分享: the outlined arrow turning up and right (26).
class _ShareGlyph extends StatelessWidget {
  const _ShareGlyph();

  @override
  Widget build(BuildContext context) => const CustomPaint(
    size: Size(BiliMetrics.shareGlyphWidth, BiliMetrics.shareGlyphHeight),
    painter: _SharePainter(),
  );
}

class _SharePainter extends CustomPainter {
  const _SharePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Traced from 26 on a 20 × 17 grid.
    final sx = size.width / 20, sy = size.height / 17;
    Offset p(double x, double y) => Offset(x * sx, y * sy);
    final neckTop = p(9.3, 5.3), neckBottom = p(9.6, 10.9), tail = p(0.9, 13.4);
    final lower = p(4.85, 10.5), upper = p(1.5, 6.3);
    final path = Path()
      ..moveTo(neckTop.dx, neckTop.dy)
      ..lineTo(p(9.9, 0.9).dx, p(9.9, 0.9).dy)
      ..lineTo(p(18.9, 7.8).dx, p(18.9, 7.8).dy)
      ..lineTo(p(9.9, 14.5).dx, p(9.9, 14.5).dy)
      ..lineTo(neckBottom.dx, neckBottom.dy)
      ..quadraticBezierTo(lower.dx, lower.dy, tail.dx, tail.dy)
      ..quadraticBezierTo(upper.dx, upper.dy, neckTop.dx, neckTop.dy)
      ..close();
    canvas.drawPath(path, _endStroke());
  }

  @override
  bool shouldRepaint(_SharePainter oldDelegate) => false;
}
