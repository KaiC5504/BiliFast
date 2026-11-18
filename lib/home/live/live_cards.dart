import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../app/zoom_back_route.dart';
import '../../dynamic/post/post_glyphs.dart' show VerifyBadgePainter;
import '../../shared/cover_placeholder.dart';
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';

/// 直播's text: the font, size and colour, no tracking.
TextStyle liveStyle(double size, Color color, {FontWeight weight = FontWeight.w400}) => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: 0,
  decoration: TextDecoration.none,
);

/// One line of [text], cut with … when it runs out of room.
Widget liveLine(String text, TextStyle style, {Key? key, TextAlign align = TextAlign.left}) => Text(
  text,
  key: key,
  style: style,
  strutStyle: BiliFonts.strut(style),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  textAlign: align,
);

abstract final class LiveArt {
  /// The 直播中 bars, white, animated (the APK's `live_ing`).
  static const bars = 'assets/images/live/live_ing.gif';
  static const watched = 'assets/images/live/tab_watching.png';
  static const liked = 'assets/images/live/tab_thumb.png';
  static const coverSwitch = 'assets/images/live/tab_cover_switch.png';
  static const areas = 'assets/images/live/tab_areas.png';
}

/// The 直播中 bars in their 16 square box, tinted [color] (white as drawn).
class LiveBars extends StatelessWidget {
  const LiveBars({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    // Each of the gif's frames repaints only its own 16 pt square, not the list around it.
    child: Image.asset(
      LiveArt.bars,
      width: LiveTabTheme.liveTagBarsBox,
      height: LiveTabTheme.liveTagBarsBox,
      color: color,
      colorBlendMode: color == null ? null : BlendMode.srcIn,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    ),
  );
}

/// A face with the verify bolt at its bottom right.
class LiveVerifiedFace extends StatelessWidget {
  const LiveVerifiedFace({super.key, required this.url, required this.size, required this.verify, required this.badge});

  final String url;
  final double size;
  final LiveVerify verify;
  final double badge;

  @override
  Widget build(BuildContext context) {
    final bolt = switch (verify) {
      LiveVerify.none => null,
      LiveVerify.personal => DynamicVerify.personal,
      LiveVerify.organization => DynamicVerify.organisation,
    };
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: ClipOval(child: RemoteImage.avatar(url.isEmpty ? null : url))),
          if (bolt != null)
            Positioned(
              right: -LiveTabTheme.badgeRing,
              bottom: -LiveTabTheme.badgeRing,
              width: badge,
              height: badge,
              child: CustomPaint(key: const ValueKey('live-verify'), painter: VerifyBadgePainter(bolt)),
            ),
        ],
      ),
    );
  }
}

/// A cover's tag at its top left (TopStar, SS主播, 全站第5): its picture poking out of the corner, the words on the
/// answer's colours.
class LiveCoverTag extends StatelessWidget {
  const LiveCoverTag({super.key, required this.badge});

  final LiveBadge badge;

  @override
  Widget build(BuildContext context) {
    final colors = [for (final value in badge.colors) Color(value)];
    final fill = switch (colors.length) {
      0 => LiveTabTheme.tagFill,
      1 => [colors.first, colors.first],
      _ => colors,
    };
    final icon = badge.icon;
    return SizedBox(
      height: LiveTabTheme.tagHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: LiveTabTheme.tagHeight,
            padding: EdgeInsets.only(
              left: icon.isEmpty ? LiveTabTheme.tagTextTrail : LiveTabTheme.tagIconWidth + LiveTabTheme.tagTextLead,
              right: LiveTabTheme.tagTextTrail,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: fill),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(LiveTabTheme.radius),
                bottomRight: Radius.circular(LiveTabTheme.tagRadius),
              ),
            ),
            child: liveLine(badge.text, liveStyle(LiveTabTheme.tagText, LiveTabTheme.onCover)),
          ),
          if (icon.isNotEmpty)
            Positioned(
              left: 0,
              bottom: 0,
              width: LiveTabTheme.tagIconWidth,
              height: LiveTabTheme.tagIconHeight,
              child: RemoteImage(icon, fit: BoxFit.contain, fadeIn: false),
            ),
        ],
      ),
    );
  }
}

/// The shade along a cover's bottom, under its counts.
class LiveCoverShade extends StatelessWidget {
  const LiveCoverShade({super.key});

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.bottomCenter,
    child: SizedBox(
      height: LiveTabTheme.shadeHeight,
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
  );
}

/// A white icon from the APK, [width] wide at its own shape.
class LiveStatIcon extends StatelessWidget {
  const LiveStatIcon(this.asset, {super.key, required this.width});

  final String asset;
  final double width;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: width,
    color: LiveTabTheme.onCover,
    colorBlendMode: BlendMode.srcIn,
    excludeFromSemantics: true,
  );
}

class LiveMorePainter extends CustomPainter {
  const LiveMorePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final paint = Paint()..color = LiveTabTheme.moreInk;
    for (final step in const [-1, 0, 1]) {
      canvas.drawCircle(centre.translate(0, step * LiveTabTheme.morePitch), LiveTabTheme.moreDot / 2, paint);
    }
  }

  @override
  bool shouldRepaint(LiveMorePainter oldDelegate) => false;
}

/// A › of [color], [LiveTabTheme.chevronWidth] wide, centred in its box.
class LiveChevronPainter extends CustomPainter {
  LiveChevronPainter({Color? color, this.left = false}) : color = color ?? LiveTabTheme.chevronInk;

  final Color color;

  /// ‹ instead.
  final bool left;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final half = Size(size.width / 2, size.height / 2);
    final tip = left ? -half.width : half.width;
    final path = Path()
      ..moveTo(centre.dx - tip, centre.dy - half.height)
      ..lineTo(centre.dx + tip, centre.dy)
      ..lineTo(centre.dx - tip, centre.dy + half.height);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = left ? LiveTabTheme.followingBackStroke : LiveTabTheme.chevronStroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(LiveChevronPainter oldDelegate) => oldDelegate.color != color || oldDelegate.left != left;
}

/// A room's cover filling its box, the placeholder until it comes.
class LiveCover extends StatelessWidget {
  const LiveCover({super.key, required this.card});

  final LiveCard card;

  @override
  Widget build(BuildContext context) => RemoteImage(
    card.cover.isEmpty ? null : card.cover,
    cover: true,
    placeholder: const CoverPlaceholder(),
    fadeIn: false,
  );
}

/// The area's two-column card (205): the cover with its tag, corner picture, 👁 and 👍 counts and the area; under it
/// the face, the title, the name and ⋮.
class LiveGridCard extends StatelessWidget {
  const LiveGridCard({super.key, required this.card, required this.onOpen, required this.onMore});

  final LiveCard card;
  final void Function(ZoomSource source) onOpen;
  final VoidCallback onMore;

  /// The card [width] wide.
  static double height(double width) => width / LiveTabTheme.gridCoverAspect + LiveTabTheme.gridBand;

  @override
  Widget build(BuildContext context) => ZoomSourceBox(
    builder: (context, source) => Semantics(
      button: true,
      label: '${card.title}，${card.uname}',
      onTap: () => onOpen(source),
      child: GestureDetector(
        key: ValueKey('live-card-${card.roomId}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpen(source),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LiveTabTheme.radius),
          child: ColoredBox(
            color: LiveTabTheme.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(aspectRatio: LiveTabTheme.gridCoverAspect, child: _cover()),
                SizedBox(height: LiveTabTheme.gridBand, child: _band()),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _cover() {
    final style = liveStyle(LiveTabTheme.statText, LiveTabTheme.onCover);
    final badge = card.badge;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        LiveCover(card: card),
        const LiveCoverShade(),
        Positioned(
          left: LiveTabTheme.statLead,
          right: LiveTabTheme.statTrail,
          bottom: LiveTabTheme.statCentre - LiveTabTheme.statText,
          height: LiveTabTheme.statText * 2,
          child: ExcludeSemantics(
            child: Row(
              children: [
                if (card.watchedText.isNotEmpty) ...[
                  const LiveStatIcon(LiveArt.watched, width: LiveTabTheme.watchedIcon),
                  const SizedBox(width: LiveTabTheme.statIconGap),
                  Text(card.watchedText, maxLines: 1, style: style),
                  const SizedBox(width: LiveTabTheme.statGap),
                ],
                if (card.likeText.isNotEmpty) ...[
                  const LiveStatIcon(LiveArt.liked, width: LiveTabTheme.likedIcon),
                  const SizedBox(width: LiveTabTheme.statIconGap),
                  Text(card.likeText, maxLines: 1, style: style),
                ],
                const Spacer(),
                Flexible(child: liveLine(card.areaName, style, align: TextAlign.right)),
              ],
            ),
          ),
        ),
        if (badge != null) Positioned(left: 0, top: 0, child: LiveCoverTag(badge: badge)),
        if (card.cornerIcon.isNotEmpty)
          Positioned(
            right: 0,
            top: 0,
            height: LiveTabTheme.cornerHeight,
            child: RemoteImage(card.cornerIcon, fit: BoxFit.fitHeight, fadeIn: false),
          ),
      ],
    );
  }

  Widget _band() {
    return Stack(
      children: [
        Positioned(
          left: LiveTabTheme.gridFaceLead,
          top: (LiveTabTheme.gridBand - LiveTabTheme.gridFace) / 2,
          child: LiveVerifiedFace(
            url: card.face,
            size: LiveTabTheme.gridFace,
            verify: card.verify,
            badge: LiveTabTheme.gridBadge,
          ),
        ),
        Positioned(
          left: LiveTabTheme.gridTextLead,
          right: LiveTabTheme.gridTextTrail,
          top: 0,
          bottom: 0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              liveLine(card.title, liveStyle(LiveTabTheme.gridTitleText, LiveTabTheme.text)),
              const SizedBox(height: LiveTabTheme.gridLineGap),
              liveLine(card.uname, liveStyle(LiveTabTheme.gridNameText, LiveTabTheme.secondary)),
            ],
          ),
        ),
        Positioned(
          right: LiveTabTheme.moreRight - LiveTabTheme.moreTarget / 2 + LiveTabTheme.moreDot / 2,
          bottom: 0,
          width: LiveTabTheme.moreTarget,
          height: LiveTabTheme.gridBand / 2 + LiveTabTheme.gridLineGap,
          child: Semantics(
            button: true,
            label: '更多',
            onTap: onMore,
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('live-card-more-${card.roomId}'),
              behavior: HitTestBehavior.opaque,
              onTap: onMore,
              child: const CustomPaint(painter: LiveMorePainter()),
            ),
          ),
        ),
      ],
    );
  }
}

/// The area at a followed room's cover's bottom left and 👁 with its count at the right (205's strip, 206).
class LiveCoverCounts extends StatelessWidget {
  const LiveCoverCounts({super.key, required this.card});

  final LiveCard card;

  @override
  Widget build(BuildContext context) {
    final style = liveStyle(LiveTabTheme.coverStatText, LiveTabTheme.onCover);
    return Positioned(
      left: LiveTabTheme.coverStatLead,
      right: LiveTabTheme.coverStatTrail,
      bottom: LiveTabTheme.coverStatCentre - LiveTabTheme.coverStatText,
      height: LiveTabTheme.coverStatText * 2,
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(child: liveLine(card.areaName, style)),
            if (card.watchedText.isNotEmpty) ...[
              const LiveStatIcon(LiveArt.watched, width: LiveTabTheme.coverWatchedIcon),
              const SizedBox(width: LiveTabTheme.statIconGap),
              Text(card.watchedText, maxLines: 1, style: style),
            ],
          ],
        ),
      ),
    );
  }
}

/// A followed room as 206 draws it, two to a row: the cover with its tag and counts over the face, the name and the
/// title.
class LiveFollowedCard extends StatelessWidget {
  const LiveFollowedCard({super.key, required this.card, required this.onOpen});

  final LiveCard card;
  final void Function(ZoomSource source) onOpen;

  static double height(double width) => width / LiveTabTheme.followingCoverAspect + LiveTabTheme.followingBand;

  @override
  Widget build(BuildContext context) => ZoomSourceBox(
    builder: (context, source) => Semantics(
      button: true,
      label: '${card.uname}，${card.title}',
      onTap: () => onOpen(source),
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('live-followed-${card.roomId}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpen(source),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LiveTabTheme.radius),
          child: ColoredBox(
            color: LiveTabTheme.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: LiveTabTheme.followingCoverAspect,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      LiveCover(card: card),
                      const LiveCoverShade(),
                      LiveCoverCounts(card: card),
                      if (card.badge case final badge?) Positioned(left: 0, top: 0, child: LiveCoverTag(badge: badge)),
                    ],
                  ),
                ),
                SizedBox(
                  height: LiveTabTheme.followingBand,
                  child: LiveRoomLines(
                    card: card,
                    face: LiveTabTheme.followingFace,
                    faceLead: LiveTabTheme.followingFaceLead,
                    textLead:
                        LiveTabTheme.followingTextLead - LiveTabTheme.followingFaceLead - LiveTabTheme.followingFace,
                    badge: LiveTabTheme.stripBadge,
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

/// The face, then the name over the title, centred in the height given.
class LiveRoomLines extends StatelessWidget {
  const LiveRoomLines({
    super.key,
    required this.card,
    required this.face,
    required this.faceLead,
    required this.textLead,
    required this.badge,
  });

  final LiveCard card;
  final double face;
  final double faceLead;
  final double textLead;
  final double badge;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: faceLead),
      LiveVerifiedFace(url: card.face, size: face, verify: card.verify, badge: badge),
      SizedBox(width: textLead),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            liveLine(card.uname, liveStyle(LiveTabTheme.stripNameText, LiveTabTheme.text)),
            const SizedBox(height: LiveTabTheme.stripLineGap),
            liveLine(card.title, liveStyle(LiveTabTheme.stripTitleText, LiveTabTheme.secondary)),
          ],
        ),
      ),
      const SizedBox(width: LiveTabTheme.sectionInset),
    ],
  );
}
