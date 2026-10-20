import 'dart:async';

import 'package:flutter/widgets.dart';

import '../device/status_bar.dart';
import '../shared/theme.dart';

/// The status bar landscape full screen draws in place of iOS's (04, 05): the time centred at the top; on the right
/// a WIFI capsule while on Wi-Fi, the battery's percentage and its glyph. It watches [feed] for as long as it is
/// mounted, so the level is current whenever the controls bring it up.
class LandscapeStatusBar extends StatefulWidget {
  const LandscapeStatusBar({super.key, required this.feed, this.now = DateTime.now});

  final StatusBarFeed feed;

  /// The clock read for the time; tests hand in their own.
  final DateTime Function() now;

  /// HH:mm, as 04, 05 and 34 show it.
  static String timeOf(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  State<LandscapeStatusBar> createState() => _LandscapeStatusBarState();
}

class _LandscapeStatusBarState extends State<LandscapeStatusBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.feed.watch(true);
    _scheduleTick();
  }

  @override
  void didUpdateWidget(LandscapeStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feed != widget.feed) {
      oldWidget.feed.watch(false);
      widget.feed.watch(true);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.feed.watch(false);
    super.dispose();
  }

  void _scheduleTick() {
    final now = widget.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _tick = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return IgnorePointer(
      child: SizedBox(
        height: LandscapeStatusTheme.centre * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Baseline(
                baseline: LandscapeStatusTheme.timeBaseline,
                baselineType: TextBaseline.alphabetic,
                child: Text(
                  LandscapeStatusBar.timeOf(widget.now()),
                  key: const ValueKey('status-time'),
                  maxLines: 1,
                  softWrap: false,
                  style: _style(LandscapeStatusTheme.timeText),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: insets.right + LandscapeStatusTheme.trailing,
              child: ValueListenableBuilder(
                valueListenable: widget.feed.status,
                builder: (context, status, _) => _Levels(status: status),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle _style(double size) => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  color: BiliColors.onVideo,
  fontSize: size,
  fontWeight: FontWeight.normal,
  letterSpacing: 0,
  decoration: TextDecoration.none,
);

/// WIFI, the percentage and the battery, each on the bar's centre line or baseline.
class _Levels extends StatelessWidget {
  const _Levels({required this.status});

  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final battery = status.battery;
    // No reference shows cellular or no network yet, so only Wi-Fi draws anything.
    final wifi = status.network == StatusNetwork.wifi;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wifi)
          const Padding(
            padding: EdgeInsets.only(top: LandscapeStatusTheme.centre - LandscapeStatusTheme.capsuleHeight / 2),
            child: _WifiCapsule(),
          ),
        if (battery != null) ...[
          if (wifi) const SizedBox(width: LandscapeStatusTheme.capsuleGap),
          Baseline(
            baseline: LandscapeStatusTheme.smallBaseline,
            baselineType: TextBaseline.alphabetic,
            child: Text(
              '${(battery * 100).round()}%',
              key: const ValueKey('status-battery-level'),
              maxLines: 1,
              softWrap: false,
              style: _style(LandscapeStatusTheme.smallText),
            ),
          ),
          const SizedBox(width: LandscapeStatusTheme.batteryGap),
          Padding(
            padding: const EdgeInsets.only(top: LandscapeStatusTheme.centre - LandscapeStatusTheme.batteryHeight / 2),
            child: BatteryGlyph(level: battery, charging: status.charging),
          ),
        ],
      ],
    );
  }
}

class _WifiCapsule extends StatelessWidget {
  const _WifiCapsule();

  // A DecoratedBox rather than a Container, which would pad the text by the outline's width.
  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('status-wifi'),
    decoration: const ShapeDecoration(
      shape: StadiumBorder(
        side: BorderSide(
          color: LandscapeStatusTheme.capsuleOutline,
          width: LandscapeStatusTheme.capsuleStroke,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
    ),
    child: SizedBox(
      width: LandscapeStatusTheme.capsuleWidth,
      height: LandscapeStatusTheme.capsuleHeight,
      child: Align(
        alignment: Alignment.topCenter,
        child: Baseline(
          // The capsule starts half its height above the bar's centre line; the text keeps the bar's baseline.
          baseline:
              LandscapeStatusTheme.smallBaseline -
              (LandscapeStatusTheme.centre - LandscapeStatusTheme.capsuleHeight / 2),
          baselineType: TextBaseline.alphabetic,
          child: Text('WIFI', maxLines: 1, softWrap: false, style: _style(LandscapeStatusTheme.smallText)),
        ),
      ),
    ),
  );
}

/// The battery body and its cap, filled to [level] (0 to 1): white, or green under a bolt while [charging].
class BatteryGlyph extends StatelessWidget {
  const BatteryGlyph({super.key, required this.level, required this.charging});

  final double level;
  final bool charging;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size(
        LandscapeStatusTheme.batteryWidth + LandscapeStatusTheme.capWidth,
        LandscapeStatusTheme.batteryHeight,
      ),
      painter: BatteryPainter(level: level, charging: charging),
    ),
  );
}

class BatteryPainter extends CustomPainter {
  const BatteryPainter({required this.level, required this.charging});

  final double level;
  final bool charging;

  static const _inner = Rect.fromLTRB(
    LandscapeStatusTheme.fillInset,
    LandscapeStatusTheme.fillInset,
    LandscapeStatusTheme.batteryWidth - LandscapeStatusTheme.fillInset,
    LandscapeStatusTheme.batteryHeight - LandscapeStatusTheme.fillInset,
  );

  /// The level's share of the space inside the outline.
  Rect get fill => Rect.fromLTWH(_inner.left, _inner.top, _inner.width * level.clamp(0, 1), _inner.height);

  Color get fillColor => charging ? LandscapeStatusTheme.charging : BiliColors.onVideo;

  @override
  void paint(Canvas canvas, Size size) {
    const half = LandscapeStatusTheme.batteryStroke / 2;
    final ink = Paint()..color = BiliColors.onVideo;
    canvas
      ..drawRRect(
        RRect.fromLTRBR(
          half,
          half,
          LandscapeStatusTheme.batteryWidth - half,
          LandscapeStatusTheme.batteryHeight - half,
          const Radius.circular(LandscapeStatusTheme.batteryCorner - half),
        ),
        Paint()
          ..color = BiliColors.onVideo
          ..style = PaintingStyle.stroke
          ..strokeWidth = LandscapeStatusTheme.batteryStroke,
      )
      ..drawRRect(
        RRect.fromRectAndCorners(
          const Rect.fromLTWH(
            LandscapeStatusTheme.batteryWidth,
            (LandscapeStatusTheme.batteryHeight - LandscapeStatusTheme.capHeight) / 2,
            LandscapeStatusTheme.capWidth,
            LandscapeStatusTheme.capHeight,
          ),
          topRight: const Radius.circular(LandscapeStatusTheme.capWidth),
          bottomRight: const Radius.circular(LandscapeStatusTheme.capWidth),
        ),
        ink,
      );
    if (level > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, const Radius.circular(LandscapeStatusTheme.fillCorner)),
        Paint()..color = fillColor,
      );
    }
    if (charging) canvas.drawPath(_bolt, ink);
  }

  /// 05's bolt, traced on the 19 × 10 body: it runs past the fill's top and bottom into the gap inside the outline.
  static final _bolt = Path()
    ..addPolygon(const [
      Offset(10.5, 1.1),
      Offset(10, 4),
      Offset(13, 4),
      Offset(9.6, 9),
      Offset(10, 6),
      Offset(7.2, 6),
    ], true);

  @override
  bool shouldRepaint(BatteryPainter oldDelegate) => oldDelegate.level != level || oldDelegate.charging != charging;
}
