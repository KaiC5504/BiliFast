import 'package:bili_core/logic.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'chrome_state.dart';
import 'player_ui.dart';

/// The gesture HUD in the middle of the player: 倍速中, the seek time, brightness and volume (BiliNative
/// `PlayerHUD.swift`, measured on the official app's 25). It fills the player and takes no touches.
class PlayerHud extends StatelessWidget {
  const PlayerHud({super.key, required this.ui});

  final PlayerUi ui;

  static const _appear = Duration(milliseconds: 260);
  static const _vanish = Duration(milliseconds: 160);
  static const _speedKey = ValueKey('hud-speed');
  static final _pop = Tween<double>(begin: 0.82, end: 1);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<Hud?>(
        valueListenable: ui.chrome.hud,
        builder: (context, hud, _) => AnimatedSwitcher(
          duration: _appear,
          reverseDuration: _vanish,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          transitionBuilder: (child, animation) {
            final scale = CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: _pop.animate(scale),
                alignment: child.key == _speedKey ? Alignment.topCenter : Alignment.center,
                child: child,
              ),
            );
          },
          child: switch (hud) {
            null => const SizedBox.shrink(key: ValueKey('hud-none')),
            SpeedUpHud() => const Align(
              key: _speedKey,
              alignment: Alignment.topCenter,
              child: Padding(padding: EdgeInsets.only(top: BiliMetrics.hudTop), child: _SpeedUpPill()),
            ),
            SeekHud(:final target, :final duration) => Center(
              key: const ValueKey('hud-seek'),
              child: _SeekPill(target: target, duration: duration),
            ),
            LevelHud(:final kind, :final value) => Center(
              key: ValueKey('hud-level-${kind.name}'),
              child: _LevelPill(kind: kind, value: value),
            ),
          },
        ),
      ),
    );
  }
}

const _label = TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.hudFont, height: 1.2);

class _Label extends StatelessWidget {
  const _Label(this.text);

  final Text text;

  @override
  Widget build(BuildContext context) =>
      Transform.translate(offset: const Offset(0, BiliMetrics.hudLabelDrop), child: text);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.padding = const EdgeInsets.symmetric(horizontal: BiliMetrics.hudPadding)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: BiliMetrics.hudHeight,
      constraints: const BoxConstraints(minWidth: BiliMetrics.hudMinWidth),
      padding: padding,
      decoration: const BoxDecoration(
        color: BiliColors.hudFill,
        borderRadius: BorderRadius.all(Radius.circular(BiliMetrics.hudRadius)),
      ),
      child: Align(widthFactor: 1, child: MediaQuery.withNoTextScaling(child: child)),
    );
  }
}

class _SpeedUpPill extends StatelessWidget {
  const _SpeedUpPill();

  @override
  Widget build(BuildContext context) {
    return const _Pill(
      padding: EdgeInsets.only(left: BiliMetrics.hudSpeedPaddingLeft, right: BiliMetrics.hudSpeedPaddingRight),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SpeedArrows(),
          SizedBox(width: BiliMetrics.hudGap),
          _Label(Text('倍速中', style: _label, maxLines: 1)),
        ],
      ),
    );
  }
}

/// The two overlapping arrows of 25. The back one slides out from behind the front one as the pill appears and
/// rests where the official app draws it.
class _SpeedArrows extends StatefulWidget {
  const _SpeedArrows();

  @override
  State<_SpeedArrows> createState() => _SpeedArrowsState();
}

class _SpeedArrowsState extends State<_SpeedArrows> with SingleTickerProviderStateMixin {
  static const _slide = Duration(milliseconds: 420);

  late final AnimationController _controller = AnimationController(vsync: this, duration: _slide);
  late final Animation<double> _spread = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(BiliMetrics.hudArrowStep + BiliMetrics.hudArrowWidth, BiliMetrics.hudArrowHeight),
      painter: _ArrowsPainter(_spread),
    );
  }
}

class _ArrowsPainter extends CustomPainter {
  _ArrowsPainter(this.spread) : super(repaint: spread);

  final Animation<double> spread;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _arrow(BiliMetrics.hudArrowStep * spread.value, size.height),
      Paint()..color = BiliColors.hudArrowBack,
    );
    canvas.drawPath(_arrow(0, size.height), Paint()..color = BiliColors.hudArrowFront);
  }

  /// A play triangle with its corners rounded.
  static Path _arrow(double left, double height) {
    const width = BiliMetrics.hudArrowWidth;
    const r = BiliMetrics.hudArrowCorner;
    final top = Offset(left, 0);
    final tip = Offset(left + width, height / 2);
    final bottom = Offset(left, height);
    Offset toward(Offset from, Offset to) => from + (to - from) / (to - from).distance * r;
    return Path()
      ..moveTo(toward(top, bottom).dx, toward(top, bottom).dy)
      ..quadraticBezierTo(top.dx, top.dy, toward(top, tip).dx, toward(top, tip).dy)
      ..lineTo(toward(tip, top).dx, toward(tip, top).dy)
      ..quadraticBezierTo(tip.dx, tip.dy, toward(tip, bottom).dx, toward(tip, bottom).dy)
      ..lineTo(toward(bottom, tip).dx, toward(bottom, tip).dy)
      ..quadraticBezierTo(bottom.dx, bottom.dy, toward(bottom, top).dx, toward(bottom, top).dy)
      ..close();
  }

  @override
  bool shouldRepaint(_ArrowsPainter oldDelegate) => oldDelegate.spread != spread;
}

class _SeekPill extends StatelessWidget {
  const _SeekPill({required this.target, required this.duration});

  final double target;
  final double duration;

  @override
  Widget build(BuildContext context) {
    final fraction = duration > 0 ? (target / duration).clamp(0.0, 1.0) : 0.0;
    return _Pill(
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label(
              Text(
                TimeFormat.pair(target, duration),
                key: const ValueKey('hud-seek-label'),
                style: _label.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
            const SizedBox(height: BiliMetrics.hudSeekGap),
            _Bar(fraction: fraction, fill: BiliColors.pink),
          ],
        ),
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.kind, required this.value});

  final LevelKind kind;
  final double value;

  static const _settle = Duration(milliseconds: 90);
  static const _iconSwap = Duration(milliseconds: 120);

  IconData get _icon => switch (kind) {
    LevelKind.brightness when value < 1 / 3 => Icons.brightness_low_rounded,
    LevelKind.brightness when value < 2 / 3 => Icons.brightness_medium_rounded,
    LevelKind.brightness => Icons.brightness_high_rounded,
    LevelKind.volume when value <= 0 => Icons.volume_off_rounded,
    LevelKind.volume when value < 0.5 => Icons.volume_down_rounded,
    LevelKind.volume => Icons.volume_up_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icon;
    return _Pill(
      child: Semantics(
        label: kind == LevelKind.brightness ? '亮度' : '音量',
        value: '${(value.clamp(0.0, 1.0) * 100).round()}%',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: _iconSwap,
              child: Icon(icon, key: ValueKey(icon), size: BiliMetrics.hudIcon, color: BiliColors.onVideo),
            ),
            const SizedBox(width: BiliMetrics.hudGap),
            SizedBox(
              width: BiliMetrics.hudBarWidth,
              // Hardware buttons step the volume in sixteenths; the bar glides between them.
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value.clamp(0.0, 1.0)),
                duration: _settle,
                builder: (context, fraction, _) => _Bar(fraction: fraction, fill: BiliColors.onVideo),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.fill});

  final double fraction;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: BiliMetrics.hudBarHeight,
      child: CustomPaint(painter: _BarPainter(fraction: fraction, fill: fill)),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.fraction, required this.fill});

  final double fraction;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Offset.zero & size, radius), Paint()..color = BiliColors.chromeTrack)
      ..drawRRect(
        RRect.fromRectAndRadius(Offset.zero & Size(size.width * fraction, size.height), radius),
        Paint()..color = fill,
      );
  }

  @override
  bool shouldRepaint(_BarPainter oldDelegate) => oldDelegate.fraction != fraction || oldDelegate.fill != fill;
}
