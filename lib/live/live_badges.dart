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

/// 荣耀等级's chip (the V and its number, 207's chat and 230's rows); nothing for level 0.
class LiveWealthChip extends StatelessWidget {
  const LiveWealthChip({super.key, required this.level});

  final int level;

  static Color fill(int level) {
    const fills = LiveRoomTheme.wealthFills;
    return fills[level >= 20 ? 2 : (level >= 10 ? 1 : 0)];
  }

  @override
  Widget build(BuildContext context) {
    if (level <= 0) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('live-wealth'),
      height: LiveRoomTheme.wealthHeight,
      padding: const EdgeInsets.only(left: LiveRoomTheme.wealthPadLeft, right: LiveRoomTheme.wealthPadRight),
      decoration: BoxDecoration(
        color: fill(level),
        borderRadius: BorderRadius.circular(LiveRoomTheme.wealthHeight / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: LiveRoomTheme.wealthV,
            height: LiveRoomTheme.wealthVHeight,
            child: CustomPaint(painter: _WealthVPainter()),
          ),
          const SizedBox(width: LiveRoomTheme.wealthGap),
          Text(
            '$level',
            maxLines: 1,
            style: liveStyle(
              LiveRoomTheme.wealthText,
              LiveRoomTheme.ink,
              line: LiveRoomTheme.wealthHeight,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The 荣耀 V: two arms meeting in a notched point, lit from above.
class _WealthVPainter extends CustomPainter {
  const _WealthVPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.34, 0)
      ..lineTo(w * 0.5, h * 0.52)
      ..lineTo(w * 0.66, 0)
      ..lineTo(w, 0)
      ..lineTo(w * 0.56, h)
      ..lineTo(w * 0.44, h)
      ..close();
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [LiveRoomTheme.wealthVTop, LiveRoomTheme.wealthVBottom],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WealthVPainter oldDelegate) => false;
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
