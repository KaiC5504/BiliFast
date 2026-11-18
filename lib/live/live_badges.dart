import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../shared/remote_image.dart';
import '../shared/theme.dart';

/// A room's text in the app's font: [size] on a [line] tall line, untracked.
TextStyle liveStyle(double size, Color color, {double? line, FontWeight weight = FontWeight.w400}) => TextStyle(
  inherit: false,
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: line == null ? null : line / size,
  leadingDistribution: line == null ? null : TextLeadingDistribution.even,
  letterSpacing: 0,
  decoration: TextDecoration.none,
);

/// An ARGB from an answer, or [fallback] for 0.
Color liveColor(int argb, Color fallback) => argb == 0 ? fallback : Color(argb);

/// 荣耀等级's chip (the badge and its number); nothing for level 0. The chat's rows ask for [onDark]; 高能榜's white
/// sheet takes the pale one.
class LiveWealthChip extends StatelessWidget {
  const LiveWealthChip({super.key, required this.level, this.onDark = false});

  final int level;
  final bool onDark;

  /// The badge's tier: one per ten levels, the last from 31 on.
  static int tier(int level) => ((level - 1) ~/ 10).clamp(0, 3);

  static Color fill(int level, {bool onDark = false}) {
    if (!onDark) return LiveRoomTheme.wealthLightFill;
    const fills = LiveRoomTheme.wealthFills;
    return fills[level > 30 ? 2 : (level > 10 ? 1 : 0)];
  }

  @override
  Widget build(BuildContext context) {
    if (level <= 0) return const SizedBox.shrink();
    final badge = tier(level);
    return Container(
      key: const ValueKey('live-wealth'),
      width: LiveRoomTheme.wealthWidth,
      height: LiveRoomTheme.wealthHeight,
      decoration: BoxDecoration(
        color: fill(level, onDark: onDark),
        borderRadius: BorderRadius.circular(LiveRoomTheme.wealthHeight / 2),
      ),
      child: Stack(
        children: [
          Positioned(
            left: LiveRoomTheme.wealthPadLeft,
            top: (LiveRoomTheme.wealthHeight - LiveRoomTheme.wealthBadgeHeights[badge]) / 2,
            width: LiveRoomTheme.wealthBadgeWidths[badge],
            height: LiveRoomTheme.wealthBadgeHeights[badge],
            child: CustomPaint(painter: _WealthBadgePainter(badge)),
          ),
          Positioned(
            left: LiveRoomTheme.wealthTextCentre * 2 - LiveRoomTheme.wealthWidth,
            right: 0,
            top: 0,
            bottom: 0,
            child: Text(
              '$level',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              textAlign: TextAlign.center,
              style: liveStyle(
                LiveRoomTheme.wealthText,
                LiveRoomTheme.ink,
                line: LiveRoomTheme.wealthHeight,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 荣耀's badges, lit from above: the V (two arms meeting in a notched point), then a diamond over it, the V winged
/// with the diamond, and a four-point star over a V whose right arm is in shade.
class _WealthBadgePainter extends CustomPainter {
  const _WealthBadgePainter(this.tier);

  final int tier;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Offset at(double x, double y) => Offset(x * w, y * h);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [LiveRoomTheme.wealthVTop, LiveRoomTheme.wealthVBottom],
      ).createShader(Offset.zero & size);

    // The V in the band from [top] down.
    Path vee(double top) {
      double y(double t) => top + (1 - top) * t;
      return Path()..addPolygon([
        at(0, y(0)),
        at(0.36, y(0)),
        at(0.5, y(0.56)),
        at(0.64, y(0)),
        at(1, y(0)),
        at(0.58, y(1)),
        at(0.42, y(1)),
      ], true);
    }

    Path diamond(double centre, double half) => Path()
      ..addPolygon([
        at(0.5, centre - half),
        at(0.5 + half * h / w, centre),
        at(0.5, centre + half),
        at(0.5 - half * h / w, centre),
      ], true);

    switch (tier) {
      case 0:
        canvas.drawPath(vee(0), paint);
      case 1:
        canvas
          ..drawPath(diamond(0.17, 0.17), paint)
          ..drawPath(vee(0.42), paint);
      case 2:
        canvas
          ..drawPath(diamond(0.3, 0.16), paint)
          ..drawPath(
            Path()..addPolygon([
              at(0, 0.12),
              at(0.22, 0.34),
              at(0.22, 0.5),
              at(0.5, 0.76),
              at(0.78, 0.5),
              at(0.78, 0.34),
              at(1, 0.12),
              at(1, 0.6),
              at(0.56, 1),
              at(0.44, 1),
              at(0, 0.6),
            ], true),
            paint,
          );
      default:
        final star = Path();
        const centre = 0.22;
        const reach = 0.22;
        const waist = 0.06;
        star.addPolygon([
          at(0.5, centre - reach),
          at(0.5 + waist * h / w, centre - waist),
          at(0.5 + reach * h / w, centre),
          at(0.5 + waist * h / w, centre + waist),
          at(0.5, centre + reach),
          at(0.5 - waist * h / w, centre + waist),
          at(0.5 - reach * h / w, centre),
          at(0.5 - waist * h / w, centre - waist),
        ], true);
        canvas
          ..drawPath(star, paint)
          ..drawPath(vee(0.48), paint)
          ..drawPath(
            Path()..addPolygon([at(0.5, 0.74), at(0.7, 0.48), at(1, 0.48), at(0.56, 1), at(0.5, 1)], true),
            Paint()..color = LiveRoomTheme.wealthVShade.withValues(alpha: 0.6),
          );
    }
  }

  @override
  bool shouldRepaint(_WealthBadgePainter oldDelegate) => oldDelegate.tier != tier;
}

/// A fan medal's chip (莲宝 p21), its guard anchor before the name when [LiveMedal.guardLevel] is set.
class LiveMedalChip extends StatelessWidget {
  const LiveMedalChip({super.key, required this.medal});

  final LiveMedal medal;

  static String? guardIcon(int level) => switch (level) {
    1 || 2 || 3 => 'assets/images/live/room_guard_icon_$level.png',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final start = medal.lit ? liveColor(medal.colorStart, LiveRoomTheme.medalFill) : LiveRoomTheme.medalUnlit;
    final end = medal.lit ? liveColor(medal.colorEnd, start) : LiveRoomTheme.medalUnlit;
    final icon = guardIcon(medal.guardLevel);
    final style = liveStyle(
      LiveRoomTheme.medalText,
      LiveRoomTheme.ink,
      line: LiveRoomTheme.medalHeight,
      weight: FontWeight.w700,
    );
    final chip = Container(
      height: LiveRoomTheme.medalHeight,
      padding: EdgeInsets.only(
        left: icon == null ? LiveRoomTheme.medalPadLeft : LiveRoomTheme.medalGuard,
        right: LiveRoomTheme.medalPadRight,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [start, end]),
        borderRadius: BorderRadius.circular(LiveRoomTheme.medalHeight / 2),
        border: medal.border == 0 || !medal.lit ? null : Border.all(color: Color(medal.border), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(medal.name, maxLines: 1, style: style),
          const SizedBox(width: LiveRoomTheme.medalLevelGap),
          Text('${medal.level}', maxLines: 1, style: style),
        ],
      ),
    );
    if (icon == null) return KeyedSubtree(key: const ValueKey('live-medal'), child: chip);
    return Stack(
      key: const ValueKey('live-medal'),
      clipBehavior: Clip.none,
      children: [
        chip,
        Positioned(
          left: -1,
          top: (LiveRoomTheme.medalHeight - LiveRoomTheme.medalGuard) / 2,
          width: LiveRoomTheme.medalGuard,
          height: LiveRoomTheme.medalGuard,
          child: Image.asset(icon, key: const ValueKey('live-medal-guard'), excludeFromSemantics: true),
        ),
      ],
    );
  }
}

/// A face [size] across, in its guard frame (总督 / 提督 / 舰长) when [guardLevel] is set, or [frame]'s picture.
class LiveFace extends StatelessWidget {
  const LiveFace({super.key, required this.url, required this.size, this.guardLevel = 0, this.frame = ''});

  final String url;
  final double size;
  final int guardLevel;
  final String frame;

  static String? guardFrame(int level) => switch (level) {
    1 || 2 || 3 => 'assets/images/live/room_guard_frame_$level.png',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final guard = guardFrame(guardLevel);
    final face = ClipOval(child: RemoteImage.avatar(url, size: Size.square(size)));
    if (guard == null && frame.isEmpty) return SizedBox.square(dimension: size, child: face);
    final outer = size * (guard != null ? LiveRoomTheme.guardFrameScale : LiveRoomTheme.serverFrameScale);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: face),
          Positioned(
            left: (size - outer) / 2,
            top: (size - outer) / 2,
            width: outer,
            height: outer,
            child: IgnorePointer(
              child: guard != null
                  ? Image.asset(guard, key: ValueKey('live-face-guard-$guardLevel'), excludeFromSemantics: true)
                  : RemoteImage(
                      frame,
                      key: const ValueKey('live-face-frame'),
                      fit: BoxFit.contain,
                      placeholder: const SizedBox.shrink(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
