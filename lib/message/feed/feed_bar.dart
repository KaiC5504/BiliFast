import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../dynamic/following/following_page.dart' show FollowingBarLook;
import '../../shared/theme.dart';
import 'feed_parts.dart';

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// 我的关注's round glass button (129): a disc of the bar's [fill] lifted by white, a darker rim, light along its top
/// and bottom edges and a soft shadow; with [back], its ‹.
class FeedGlassPainter extends CustomPainter {
  const FeedGlassPainter({required this.fill, this.back = false});

  final Color fill;
  final bool back;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    const radius = FollowingListTheme.backDisc / 2;
    final disc = Rect.fromCircle(center: centre, radius: radius);
    canvas
      ..drawCircle(
        centre.translate(0, FollowingListTheme.backShadowDrop),
        radius,
        Paint()
          ..color = FollowingListTheme.backShadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, FollowingListTheme.backShadowBlur / 2),
      )
      ..drawCircle(centre, radius, Paint()..color = Color.alphaBlend(FollowingListTheme.backLift, fill))
      ..drawCircle(
        centre,
        radius - FollowingListTheme.backRimWidth / 2,
        _stroke(FollowingListTheme.backRim, FollowingListTheme.backRimWidth),
      );
    final gloss = _stroke(FollowingListTheme.backGloss, FollowingListTheme.backGlossWidth)
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          FollowingListTheme.backGloss,
          FollowingListTheme.backGloss.withValues(alpha: 0),
          FollowingListTheme.backGloss.withValues(alpha: 0),
          FollowingListTheme.backGloss,
        ],
        stops: const [0, 0.3, 0.7, 1],
      ).createShader(disc);
    canvas.drawCircle(centre, radius - FollowingListTheme.backRimWidth - FollowingListTheme.backGlossWidth / 2, gloss);
    if (!back) return;
    final tip = centre.dx + FollowingListTheme.backTip;
    const end = FollowingListTheme.backTip + FollowingListTheme.backWidth;
    canvas.drawPath(
      Path()
        ..moveTo(centre.dx + end, centre.dy - FollowingListTheme.backHalfHeight)
        ..lineTo(tip, centre.dy)
        ..lineTo(centre.dx + end, centre.dy + FollowingListTheme.backHalfHeight),
      _stroke(FollowingListTheme.backInk, FollowingListTheme.backStroke),
    );
  }

  @override
  bool shouldRepaint(FeedGlassPainter oldDelegate) => oldDelegate.fill != fill || oldDelegate.back != back;
}

/// 新增粉丝's bare ‹, its arms spanning the box.
class FeedChevronPainter extends CustomPainter {
  const FeedChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = MessageFeedTheme.plainBackStroke / 2;
    canvas.drawPath(
      Path()
        ..moveTo(size.width - inset, inset)
        ..lineTo(inset, size.height / 2)
        ..lineTo(size.width - inset, size.height - inset),
      _stroke(MessageFeedTheme.plainInk, MessageFeedTheme.plainBackStroke),
    );
  }

  @override
  bool shouldRepaint(FeedChevronPainter oldDelegate) => false;
}

Widget _gear(Color color) => Image.asset(
  'assets/images/message/feed_gear.png',
  width: MessageFeedTheme.gearWidth,
  height: MessageFeedTheme.gearHeight,
  color: color,
);

/// 回复与@'s and 收到喜欢's bar (197, 198): the 装扮's colour behind the status bar and the row, the title centred,
/// ‹ and the gear in glass discs; a 2/3 hairline under it.
class FeedBar extends StatelessWidget {
  const FeedBar({super.key, required this.title, required this.look, required this.onBack, required this.onGear});

  final String title;
  final FollowingBarLook look;
  final VoidCallback onBack;
  final VoidCallback onGear;

  static double heightOf(BuildContext context) =>
      MediaQuery.paddingOf(context).top + MessageFeedTheme.barRow + MessageFeedTheme.barHairline;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    const half = MessageFeedTheme.buttonTarget / 2;
    const centre = FollowingListTheme.rowCentre;
    final style = feedStyle(
      MessageFeedTheme.titleText,
      look.ink,
      line: MessageFeedTheme.titleLine,
      weight: MessageFeedTheme.titleWeight,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: look.lightStatus ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: SizedBox(
        key: const ValueKey('feed-bar'),
        height: heightOf(context),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top + MessageFeedTheme.barRow,
              child: ColoredBox(color: look.fill),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MessageFeedTheme.barHairline,
              child: ColoredBox(color: MessageFeedTheme.hairline),
            ),
            Positioned(
              left: MessageFeedTheme.buttonCentreX + half,
              right: MessageFeedTheme.buttonCentreX + half,
              top: top,
              height: centre * 2,
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, FollowingListTheme.titleDrop),
                  child: feedLine(title, style, key: const ValueKey('feed-title'), align: TextAlign.center),
                ),
              ),
            ),
            Positioned(
              left: MessageFeedTheme.buttonCentreX - half,
              top: top + centre - half,
              width: MessageFeedTheme.buttonTarget,
              height: MessageFeedTheme.buttonTarget,
              child: FeedTap(
                key: const ValueKey('feed-back'),
                label: '返回',
                onTap: onBack,
                child: CustomPaint(painter: FeedGlassPainter(fill: look.fill, back: true)),
              ),
            ),
            Positioned(
              right: MessageFeedTheme.buttonCentreX - half,
              top: top + centre - half,
              width: MessageFeedTheme.buttonTarget,
              height: MessageFeedTheme.buttonTarget,
              child: FeedTap(
                key: const ValueKey('feed-gear'),
                label: '设置',
                onTap: onGear,
                child: CustomPaint(
                  painter: FeedGlassPainter(fill: look.fill),
                  child: Center(child: _gear(MessageFeedTheme.gearInk)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 新增粉丝's bar (199): white, the title centred, a bare ‹ and gear, a 1/3 rule along its bottom.
class FeedPlainBar extends StatelessWidget {
  const FeedPlainBar({super.key, required this.title, required this.onBack, required this.onGear});

  final String title;
  final VoidCallback onBack;
  final VoidCallback onGear;

  static double heightOf(BuildContext context) => MediaQuery.paddingOf(context).top + MessageFeedTheme.plainBar;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    const half = MessageFeedTheme.buttonTarget / 2;
    const centre = MessageFeedTheme.plainCentre;
    final style = feedStyle(
      MessageFeedTheme.plainTitleText,
      MessageFeedTheme.plainInk,
      line: MessageFeedTheme.plainTitleLine,
      weight: MessageFeedTheme.plainTitleWeight,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BiliTheme.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: ColoredBox(
        color: MessageFeedTheme.page,
        child: SizedBox(
          key: const ValueKey('feed-bar'),
          height: heightOf(context),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: top + MessageFeedTheme.plainRuleTop,
                height: MessageFeedTheme.plainRule,
                child: ColoredBox(color: MessageFeedTheme.plainRuleInk),
              ),
              Positioned(
                left: MessageFeedTheme.plainBackCentreX + half,
                right: MessageFeedTheme.plainGearRight + half,
                top: top + centre - MessageFeedTheme.plainTitleLine / 2,
                height: MessageFeedTheme.plainTitleLine,
                child: Center(
                  child: feedLine(title, style, key: const ValueKey('feed-title'), align: TextAlign.center),
                ),
              ),
              Positioned(
                left: MessageFeedTheme.plainBackCentreX - half,
                top: top + centre - half,
                width: MessageFeedTheme.buttonTarget,
                height: MessageFeedTheme.buttonTarget,
                child: FeedTap(
                  key: const ValueKey('feed-back'),
                  label: '返回',
                  onTap: onBack,
                  child: const Center(
                    child: SizedBox(
                      width: MessageFeedTheme.plainBackWidth,
                      height: MessageFeedTheme.plainBackHeight,
                      child: CustomPaint(painter: FeedChevronPainter()),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: MessageFeedTheme.plainGearRight - half,
                top: top + centre - half,
                width: MessageFeedTheme.buttonTarget,
                height: MessageFeedTheme.buttonTarget,
                child: FeedTap(
                  key: const ValueKey('feed-gear'),
                  label: '设置',
                  onTap: onGear,
                  child: Center(child: _gear(MessageFeedTheme.plainInk)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
