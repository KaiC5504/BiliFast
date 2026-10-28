import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show VideoCard;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/logic.dart' show CountFormat, TimeFormat;
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../video/actions/video_actions.dart';
import '../video/player_session.dart';
import 'panels/panel_controller.dart';
import 'player_ui.dart';
import 'portrait_controls.dart';

/// Hands a link to the share sheet; completes true only when the share sheet reports a share.
typedef ShareLink = Future<bool> Function(Uri link);

/// Windows has no sheet and answers unavailable, which must not count as a share.
Future<bool> shareThroughSystem(Uri link) async {
  final result = await SharePlus.instance.share(ShareParams(uri: link));
  return result.status == ShareResultStatus.success;
}

/// 分享 on an end screen over the page's player.
Future<void> shareFromEndScreen(BuildContext context, PlayerUi ui, ShareLink share) async {
  // Through the actions the page counts the share once the sheet completes it.
  if (ui.details?.actions case final actions?) {
    actions.ask(ActionPrompt.share);
    return;
  }
  final link = ui.session.shareLink;
  if (link == null) return;
  try {
    await share(link);
  } catch (error) {
    Logger.shared.warn(LogCategory.ui, 'share failed', {'error': '$error'});
    if (context.mounted) showToast(context, '分享失败');
  }
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

  Future<void> _share() => shareFromEndScreen(context, _ui, widget.share);

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
                EndRise(
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
                  EndRise(
                    animation: _stage(0.2, 0.8),
                    child: _Recommended(card: card, onPlay: _tap(() => _session.playRelated(card))),
                  ),
                const Spacer(),
                EndRise(
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
                            onTap: _tap(() => unawaited(_share())),
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

/// Fades its child in as it rises [BiliMetrics.endRise] into place.
class EndRise extends StatelessWidget {
  const EndRise({super.key, required this.animation, required this.child});

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

  /// Figures as wide as the official app's SF digits, which are tabular by default.
  static const _count = TextStyle(
    color: BiliColors.endMeta,
    fontSize: BiliMetrics.endMetaFont,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );
  static const _button = TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.endButtonFont, height: 1);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: BiliMetrics.endInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: Offset(0, BiliMetrics.endCaptionDrop),
            child: const Text('推荐视频', style: _caption),
          ),
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
                        child: Text(
                          card.title,
                          style: _title,
                          strutStyle: BiliFonts.strutOf(context, _title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: BiliMetrics.endUploaderTop,
                        height: BiliMetrics.endMetaRow,
                        child: Row(
                          spacing: BiliMetrics.endMetaGap,
                          children: [
                            const EndUpBadge(),
                            Flexible(
                              child: Text(
                                card.ownerName,
                                style: _meta,
                                strutStyle: BiliFonts.strutOf(context, _meta),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                            const EndCountIcon(CountGlyph.views),
                            const SizedBox(width: BiliMetrics.endMetaGap),
                            Text(CountFormat.short(card.views), style: _count),
                            const SizedBox(width: BiliMetrics.endMetaSpacing),
                            const EndCountIcon(CountGlyph.danmaku),
                            const SizedBox(width: BiliMetrics.endMetaGap),
                            Text(CountFormat.short(card.danmaku), style: _count),
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
                  // The pill is 30 tall and sits on the cover's bottom line, so the rest of a 44 target goes above it.
                  child: SizedBox(
                    height: BiliMetrics.chromeButton,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      widthFactor: 1,
                      child: Container(
                        width: BiliMetrics.endButtonWidth,
                        height: BiliMetrics.endButtonHeight,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: BiliColors.endButton,
                          borderRadius: BorderRadius.circular(BiliMetrics.endButtonHeight / 2),
                        ),
                        child: Transform.translate(
                          offset: Offset(0, BiliMetrics.endButtonTextDrop),
                          child: const Text('立即播放', style: _button, maxLines: 1, softWrap: false),
                        ),
                      ),
                    ),
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
            RemoteImage(
              card.cover,
              size: const Size(BiliMetrics.endCoverWidth, BiliMetrics.endCoverHeight),
              cover: true,
            ),
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

class EndUpBadge extends StatelessWidget {
  const EndUpBadge({super.key});

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
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        color: BiliColors.endMeta,
        fontSize: BiliMetrics.endUpFont,
        fontWeight: FontWeight.bold,
        height: 1,
      ),
    ),
  );
}

enum CountGlyph { views, danmaku }

/// Bilibili's own count icons, the same box as the UP badge: a small play triangle, or two dot-and-dash rows.
class EndCountIcon extends StatelessWidget {
  const EndCountIcon(this.glyph, {super.key});

  final CountGlyph glyph;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(BiliMetrics.endCountIconWidth, BiliMetrics.endCountIconHeight),
    painter: CountPainter(glyph),
  );
}

class CountPainter extends CustomPainter {
  const CountPainter(this.glyph, {this.color = BiliColors.endMeta});

  final CountGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = BiliMetrics.endUpBorder;
    final box = (Offset.zero & size).deflate(stroke / 2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(BiliMetrics.endUpRadius)), line);

    // Measured on 26 at 3 px per point, inside its 13.3 × 11.3 box.
    final sx = size.width / 13.3, sy = size.height / 11.3;
    Offset p(double x, double y) => Offset(x * sx, y * sy);
    switch (glyph) {
      case CountGlyph.views:
        final triangle = Path()..addPolygon([p(5.45, 3.7), p(8.65, 5.6), p(5.45, 7.5)], true);
        canvas
          ..drawPath(triangle, Paint()..color = color)
          ..drawPath(triangle, line..strokeWidth = stroke / 2);
      case CountGlyph.danmaku:
        final dot = Paint()..color = color;
        for (final (y, x) in [(4.17, 3.35), (6.83, 4.35)]) {
          canvas
            ..drawCircle(p(x, y), 0.65 * sx, dot)
            ..drawLine(p(x + 2.05, y), p(x + 5.95, y), line);
        }
    }
  }

  @override
  bool shouldRepaint(CountPainter oldDelegate) => oldDelegate.glyph != glyph || oldDelegate.color != color;
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

/// 重播, as 26 shows: a circle open at the lower right, its arrowhead at three o'clock pointing on round.
class _ReplayGlyph extends StatelessWidget {
  const _ReplayGlyph();

  @override
  Widget build(BuildContext context) => const CustomPaint(
    size: Size(BiliMetrics.replayGlyphWidth, BiliMetrics.replayGlyphHeight),
    painter: ReplayPainter(),
  );
}

class ReplayPainter extends CustomPainter {
  const ReplayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Proportions measured on 26 at 8×: a ring of radius 0.44 of the height, open from 46° round to -8°, and a chevron whose
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
  bool shouldRepaint(ReplayPainter oldDelegate) => false;
}

/// 分享, as 26 shows: the outlined arrow turning up and right.
class _ShareGlyph extends StatelessWidget {
  const _ShareGlyph();

  @override
  Widget build(BuildContext context) => const CustomPaint(
    size: Size(BiliMetrics.shareGlyphWidth, BiliMetrics.shareGlyphHeight),
    painter: SharePainter(),
  );
}

class SharePainter extends CustomPainter {
  const SharePainter();

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
  bool shouldRepaint(SharePainter oldDelegate) => false;
}
