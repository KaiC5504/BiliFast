import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/logic.dart';
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import '../shared/toast.dart';
import 'panels/panel_controller.dart';
import 'player_ui.dart';
import 'seek_bar.dart';

const _fade = Duration(milliseconds: 220);
const _press = Duration(milliseconds: 90);

/// The landscape full-screen controls, filling the screen (BiliNative `LandscapeChrome.swift`, measured on 04): back
/// and the title, ⋮, 截图 and the rotation lock on the right edge, the time, the bar and the bottom row. The bars
/// slide in from their edges as the controls show and stand aside while a panel is open. The top actions, 弹幕设置 and
/// the danmaku field come in later slices; their room is kept so nothing else moves when they do.
class LandscapeChrome extends StatelessWidget {
  const LandscapeChrome({super.key, required this.ui});

  final PlayerUi ui;

  static const _timeStyle = TextStyle(
    color: BiliColors.onVideo,
    fontSize: BiliMetrics.chromeTimeFont,
    height: 1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([ui.chrome, ui.panels, ui.session, ui.orientation]),
      builder: (context, _) {
        final shown = ui.chrome.visible && ui.panels.value == null;
        return IgnorePointer(
          key: const ValueKey('landscape-chrome'),
          ignoring: !shown,
          child: DefaultTextStyle(
            style: fullScreenText,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ChromeSlide(
                  shown: shown,
                  from: Offset.zero,
                  child: const Column(
                    children: [
                      ChromeShade(height: BiliMetrics.chromeTopShade, fromTop: true),
                      Spacer(),
                      ChromeShade(height: BiliMetrics.chromeBottomShade, fromTop: false),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: ChromeSlide(
                    shown: shown,
                    from: const Offset(0, -BiliMetrics.chromeSlide),
                    child: _topBar(insets),
                  ),
                ),
                Positioned(
                  right: math.max(insets.right - 1, 0),
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -BiliMetrics.chromeSideLift),
                      child: ChromeSlide(
                        shown: shown,
                        from: const Offset(BiliMetrics.chromeSlide, 0),
                        child: _sideColumn(context),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ChromeSlide(
                    shown: shown,
                    from: const Offset(0, BiliMetrics.chromeSlide),
                    child: _bottomBar(insets),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  VoidCallback _touch(VoidCallback action) => () {
    ui.chrome.show();
    action();
  };

  Widget _topBar(EdgeInsets insets) {
    return Padding(
      padding: EdgeInsets.only(
        left: insets.left + BiliMetrics.landscapeEdge,
        right: insets.right + BiliMetrics.landscapeEdge,
        top: insets.top,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: BiliMetrics.chromeTitleTop),
              child: SizedBox(
                height: BiliMetrics.chromeTitleRow,
                child: Row(
                  children: [
                    FullScreenButton(
                      key: const ValueKey('landscape-back'),
                      label: '返回',
                      height: BiliMetrics.chromeTitleRow,
                      onTap: ui.onBack,
                      child: const ChromeBackGlyph(),
                    ),
                    Expanded(
                      child: Text(
                        ui.session.title,
                        key: const ValueKey('landscape-title'),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: BiliColors.onVideo,
                          fontSize: BiliMetrics.titleText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: BiliMetrics.chromeActionsRoom),
          Padding(
            padding: const EdgeInsets.only(top: BiliMetrics.chromeMoreTop),
            child: FullScreenMoreButton(key: const ValueKey('landscape-more'), ui: ui),
          ),
        ],
      ),
    );
  }

  Widget _sideColumn(BuildContext context) {
    final locked = ui.orientation.locked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ui.session.canCaptureFrame) ...[
          FullScreenButton(
            key: const ValueKey('landscape-capture'),
            label: '截图',
            onTap: _touch(() => unawaited(_capture(context))),
            child: const CustomPaint(
              size: Size(BiliMetrics.chromeCameraWidth, BiliMetrics.chromeCameraHeight),
              painter: _CameraPainter(),
            ),
          ),
          const SizedBox(height: BiliMetrics.chromeSideGap),
        ],
        FullScreenButton(
          key: const ValueKey('landscape-lock'),
          label: locked ? '解锁屏幕方向' : '锁定屏幕方向',
          onTap: _touch(ui.orientation.toggleLock),
          child: AnimatedSwitcher(
            duration: _fade,
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: CustomPaint(
              key: ValueKey(locked),
              size: const Size(BiliMetrics.chromeLockWidth, BiliMetrics.chromeLockHeight),
              painter: _LockPainter(locked: locked),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _capture(BuildContext context) async {
    final message = (await ui.session.captureFrame()).message;
    if (context.mounted) showToast(context, message);
  }

  Widget _bottomBar(EdgeInsets insets) {
    final session = ui.session;
    final bar = FullScreenSeekBar.repaintOf(ui);
    return Padding(
      padding: EdgeInsets.only(left: insets.left, right: insets.right, bottom: insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: BiliMetrics.chromeTimeBox,
            child: Padding(
              padding: const EdgeInsets.only(left: BiliMetrics.chromeTimeInset),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ListenableBuilder(
                  listenable: bar,
                  builder: (context, _) => Text(
                    TimeFormat.pair(session.position, session.duration.value),
                    key: const ValueKey('landscape-time'),
                    style: _timeStyle,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: BiliMetrics.chromeBarTop),
            child: FullScreenSeekBar(key: const ValueKey('landscape-bar'), ui: ui, repaint: bar),
          ),
          Padding(
            padding: const EdgeInsets.only(top: BiliMetrics.chromeRowTop, right: BiliMetrics.chromeRowTrailing),
            child: Row(
              children: [
                FullScreenPlayButton(key: const ValueKey('landscape-play'), ui: ui),
                Padding(
                  padding: const EdgeInsets.only(left: BiliMetrics.landscapeEdge),
                  child: FullScreenButton(
                    key: const ValueKey('landscape-danmaku'),
                    label: session.danmakuOn ? '关闭弹幕' : '开启弹幕',
                    onTap: _touch(() => session.setDanmakuOn(!session.danmakuOn)),
                    child: DanmakuGlyph(on: session.danmakuOn),
                  ),
                ),
                // 弹幕设置 and the danmaku field (later slices) sit here.
                const SizedBox(width: BiliMetrics.chromeSettingsRoom),
                const Expanded(child: SizedBox.shrink()),
                const SizedBox(width: BiliMetrics.chromeSpeedGap),
                FullScreenButton.text(
                  key: const ValueKey('landscape-speed'),
                  label: '倍速',
                  text: speedLabel(session.rate),
                  onTap: _touch(() => ui.panels.open(PlayerPanel.speed)),
                ),
                const SizedBox(width: BiliMetrics.chromeQualityGap),
                FullScreenButton.text(
                  key: const ValueKey('landscape-quality'),
                  label: '清晰度',
                  text: session.qualityName(session.quality),
                  fontSize: BiliMetrics.chromeQualityText,
                  bold: true,
                  onTap: _touch(() => ui.panels.open(PlayerPanel.quality)),
                ),
                if (session.episodes.isNotEmpty) ...[
                  const SizedBox(width: BiliMetrics.chromeEpisodesGap),
                  FullScreenButton.text(
                    key: const ValueKey('landscape-episodes'),
                    label: '选集',
                    text: '选集',
                    onTap: _touch(() => ui.panels.open(PlayerPanel.episodes)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The full-screen controls draw over the page's own text style, which may be outside any Material.
const fullScreenText = TextStyle(
  fontFamily: BiliFonts.family,
  color: BiliColors.onVideo,
  decoration: TextDecoration.none,
);

/// 倍速 at 1×, otherwise the rate as the 倍速 panel lists it (1.5X, 1.25X, 2.0X).
String speedLabel(double rate) {
  if (rate == 1) return '倍速';
  var text = rate.toStringAsFixed(2);
  if (text.endsWith('0')) text = text.substring(0, text.length - 1);
  return '${text}X';
}

/// Fades its child in while sliding it [from] an offset (a share of its own size) as [shown] turns on.
class ChromeSlide extends StatelessWidget {
  const ChromeSlide({super.key, required this.shown, required this.from, required this.child});

  final bool shown;
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: shown ? 1 : 0,
    duration: _fade,
    curve: Curves.easeOut,
    child: AnimatedSlide(offset: shown ? Offset.zero : from, duration: _fade, curve: Curves.easeOutCubic, child: child),
  );
}

/// The dark ramp behind the controls at the top or bottom edge, so white glyphs read over bright frames.
class ChromeShade extends StatelessWidget {
  const ChromeShade({super.key, required this.height, required this.fromTop});

  final double height;
  final bool fromTop;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: const [BiliColors.chromeShade, BiliColors.chromeShadeClear],
          ),
        ),
      ),
    ),
  );
}

/// Shrinks a little under the finger, so a tap on the controls is felt.
class ChromePressable extends StatefulWidget {
  const ChromePressable({super.key, required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<ChromePressable> createState() => _ChromePressableState();
}

class _ChromePressableState extends State<ChromePressable> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? BiliMetrics.fullScreenPressedScale : 1,
        duration: _press,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    ),
  );
}

/// A control on the full-screen chrome: a glyph in a 44 pt square, or a line of text.
class FullScreenButton extends StatelessWidget {
  const FullScreenButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.width = BiliMetrics.chromeButton,
    this.height = BiliMetrics.chromeButton,
  });

  FullScreenButton.text({
    super.key,
    required this.label,
    required String text,
    required this.onTap,
    double fontSize = BiliMetrics.bodyText,
    bool bold = false,
  }) : width = null,
       height = BiliMetrics.chromeButton,
       child = Padding(
         padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.chromeTextPad),
         child: Text(
           text,
           maxLines: 1,
           softWrap: false,
           style: TextStyle(
             color: BiliColors.onVideo,
             fontSize: fontSize,
             fontWeight: bold ? FontWeight.bold : FontWeight.normal,
           ),
         ),
       );

  final String label;
  final VoidCallback onTap;
  final Widget child;

  /// Null: as wide as the text.
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) => ChromePressable(
    label: label,
    onTap: onTap,
    child: SizedBox(
      width: width,
      height: height,
      child: Center(widthFactor: width == null ? 1 : null, child: child),
    ),
  );
}

/// The thin back chevron.
class ChromeBackGlyph extends StatelessWidget {
  const ChromeBackGlyph({
    super.key,
    this.width = BiliMetrics.chromeBackWidth,
    this.height = BiliMetrics.chromeBackHeight,
    this.color = BiliColors.onVideo,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(width, height), painter: _ChevronPainter(color));
}

/// ⋮, opening the 更多 panel.
class FullScreenMoreButton extends StatelessWidget {
  const FullScreenMoreButton({super.key, required this.ui, this.color = BiliColors.onVideo});

  final PlayerUi ui;
  final Color color;

  @override
  Widget build(BuildContext context) => FullScreenButton(
    label: '更多',
    onTap: () {
      ui.chrome.show();
      ui.panels.open(PlayerPanel.more);
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: BiliMetrics.chromeMoreDotSpacing),
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const SizedBox.square(dimension: BiliMetrics.chromeMoreDotSize),
          ),
        ],
      ],
    ),
  );
}

/// Play or pause; it shows play once the video has ended.
class FullScreenPlayButton extends StatelessWidget {
  const FullScreenPlayButton({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final session = ui.session;
    return ListenableBuilder(
      listenable: Listenable.merge([session.readout.status, session]),
      builder: (context, _) {
        final playing = session.readout.wantsPlay && !session.ended;
        return FullScreenButton(
          label: playing ? '暂停' : '播放',
          onTap: () {
            ui.chrome.show();
            session.togglePlay();
          },
          child: AnimatedSwitcher(
            duration: _press * 2,
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: CustomPaint(
              key: ValueKey(playing),
              size: const Size(BiliMetrics.chromePlayWidth, BiliMetrics.chromePlayHeight),
              painter: _PlayPainter(playing: playing),
            ),
          ),
        );
      },
    );
  }
}

/// 弹 on a little TV: a pink tick in its corner while danmaku show, a cross while they are off.
class DanmakuGlyph extends StatelessWidget {
  const DanmakuGlyph({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: BiliMetrics.chromeDanmakuWidth,
    height: BiliMetrics.chromeDanmakuHeight,
    child: Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: _DanmakuTvPainter())),
        // The box's centre, below the antennae.
        const Positioned(
          left: _DanmakuTvPainter.left,
          top: _DanmakuTvPainter.top,
          right: BiliMetrics.chromeDanmakuWidth - _DanmakuTvPainter.right,
          bottom: BiliMetrics.chromeDanmakuHeight - _DanmakuTvPainter.bottom,
          child: Center(
            child: Text(
              '弹',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: BiliColors.onVideo,
                fontSize: BiliMetrics.chromeDanmakuText,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: _fade,
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: CustomPaint(
              key: ValueKey(on),
              size: const Size(BiliMetrics.chromeDanmakuWidth, BiliMetrics.chromeDanmakuHeight),
              painter: _DanmakuMarkPainter(on: on),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The [SeekBar] driven by the session: a drag scrubs, a resting finger hints, a lift seeks.
class FullScreenSeekBar extends StatelessWidget {
  const FullScreenSeekBar({super.key, required this.ui, required this.repaint, this.style = SeekBarStyle.tv});

  final PlayerUi ui;
  final Listenable repaint;
  final SeekBarStyle style;

  /// What the bar and the time redraw on.
  static Listenable repaintOf(PlayerUi ui) {
    final session = ui.session;
    return Listenable.merge([session.readout.seconds, session.readout.buffered, session.scrubbing, session.duration]);
  }

  @override
  Widget build(BuildContext context) {
    final session = ui.session;
    return SeekBar(
      position: () => session.position,
      duration: () => session.duration.value,
      buffered: () => session.readout.bufferedEnd(session.position),
      repaint: repaint,
      chapters: session.chapters,
      style: style,
      onScrub: session.scrub,
      onRest: session.hint,
      onCancel: session.cancelScrub,
      onCommit: (seconds) {
        ui.chrome.show();
        unawaited(session.commitSeek(seconds));
      },
    );
  }
}

Paint _line(Color color, [double width = BiliMetrics.chromeLineStroke]) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = color;

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = BiliMetrics.chromeBackStroke / 2;
    canvas.drawPath(
      Path()
        ..moveTo(size.width - inset, inset)
        ..lineTo(inset, size.height / 2)
        ..lineTo(size.width - inset, size.height - inset),
      _line(color, BiliMetrics.chromeBackStroke),
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}

/// The official play glyph is a triangle with well rounded corners; pause is two rounded bars of the same height.
class _PlayPainter extends CustomPainter {
  const _PlayPainter({required this.playing});

  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = BiliColors.onVideo;
    if (playing) {
      const bar = BiliMetrics.chromePauseBar;
      final height = size.height * BiliMetrics.chromePauseShare;
      final top = (size.height - height) / 2;
      final left = (size.width - bar * 2 - BiliMetrics.chromePauseGap) / 2;
      for (final x in [left, left + bar + BiliMetrics.chromePauseGap]) {
        canvas.drawRRect(
          RRect.fromLTRBR(x, top, x + bar, top + height, const Radius.circular(BiliMetrics.chromePlayCorner)),
          fill,
        );
      }
      return;
    }
    // A triangle drawn inside the outline by the corner radius and stroked with round joins of twice that width:
    // its outer edge is the full triangle with round corners.
    const r = BiliMetrics.chromePlayCorner;
    final a = Offset.zero, b = Offset(0, size.height), c = Offset(size.width, size.height / 2);
    final ab = (a - b).distance, bc = (b - c).distance, ca = (c - a).distance;
    final perimeter = ab + bc + ca;
    final centre = (a * bc + b * ca + c * ab) / perimeter;
    final inradius = size.width * size.height / perimeter;
    Offset inward(Offset p) => centre + (p - centre) * ((inradius - r) / inradius);
    final path = Path()
      ..moveTo(inward(a).dx, inward(a).dy)
      ..lineTo(inward(b).dx, inward(b).dy)
      ..lineTo(inward(c).dx, inward(c).dy)
      ..close();
    canvas
      ..drawPath(path, fill)
      ..drawPath(path, _line(BiliColors.onVideo, r * 2));
  }

  @override
  bool shouldRepaint(_PlayPainter oldDelegate) => oldDelegate.playing != playing;
}

/// Points measured on 04 at 3 px per pt, inside a 21 × 20 box.
class _DanmakuTvPainter extends CustomPainter {
  const _DanmakuTvPainter();

  static const left = 1.5, top = 3.9, right = 19.9, bottom = 18.9, radius = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    const corner = Radius.circular(radius);
    // The box leaves its bottom-right corner open for the tick or the cross.
    final box = Path()
      ..moveTo(right, 14.3)
      ..lineTo(right, top + radius)
      ..arcToPoint(const Offset(right - radius, top), radius: corner, clockwise: false)
      ..lineTo(left + radius, top)
      ..arcToPoint(const Offset(left, top + radius), radius: corner, clockwise: false)
      ..lineTo(left, bottom - radius)
      ..arcToPoint(const Offset(left + radius, bottom), radius: corner, clockwise: false)
      ..lineTo(11.8, bottom)
      ..moveTo(5.5, 0.7)
      ..lineTo(7.4, top - 0.4)
      ..moveTo(13.9, 0.7)
      ..lineTo(12, top - 0.4);
    canvas.drawPath(box, _line(BiliColors.onVideo));
  }

  @override
  bool shouldRepaint(_DanmakuTvPainter oldDelegate) => false;
}

class _DanmakuMarkPainter extends CustomPainter {
  const _DanmakuMarkPainter({required this.on});

  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    if (on) {
      canvas.drawPath(
        Path()
          ..moveTo(12.4, 16.4)
          ..lineTo(15.7, 18.6)
          ..lineTo(20.4, 14.5),
        _line(BiliColors.pink),
      );
      return;
    }
    canvas.drawPath(
      Path()
        ..moveTo(14.2, 14.2)
        ..lineTo(19.2, 19.2)
        ..moveTo(19.2, 14.2)
        ..lineTo(14.2, 19.2),
      _line(BiliColors.onVideo),
    );
  }

  @override
  bool shouldRepaint(_DanmakuMarkPainter oldDelegate) => oldDelegate.on != on;
}

/// 04's camera, 20 × 17: the body with its hump, the lens, and the flash mark at the top right.
class _CameraPainter extends CustomPainter {
  const _CameraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const s = BiliMetrics.chromeLineStroke / 2;
    final right = size.width - s, bottom = size.height - s;
    const top = 4.2, r = 3.6;
    const corner = Radius.circular(r);
    final body = Path()
      ..moveTo(s + r, top)
      ..lineTo(4.6, top)
      ..lineTo(6.4, 1.2)
      ..lineTo(12.6, 1.2)
      ..lineTo(14.4, top)
      ..lineTo(right - r, top)
      ..arcToPoint(Offset(right, top + r), radius: corner)
      ..lineTo(right, bottom - r)
      ..arcToPoint(Offset(right - r, bottom), radius: corner)
      ..lineTo(s + r, bottom)
      ..arcToPoint(Offset(s, bottom - r), radius: corner)
      ..lineTo(s, top + r)
      ..arcToPoint(const Offset(s + r, top), radius: corner)
      ..close()
      ..addOval(Rect.fromCircle(center: Offset(size.width / 2 - 0.4, 10.2), radius: 3.3))
      ..moveTo(15.8, 0.8)
      ..lineTo(18.2, 1.3);
    canvas.drawPath(body, _line(BiliColors.onVideo));
  }

  @override
  bool shouldRepaint(_CameraPainter oldDelegate) => false;
}

/// 04's padlock, 21 × 20.5: open, the shackle lifted off to the right; locked, it closes over the body.
class _LockPainter extends CustomPainter {
  const _LockPainter({required this.locked});

  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    const s = BiliMetrics.chromeLineStroke / 2;
    const bodyTop = 8.3, bodyRight = 17.7;
    final bodyBottom = size.height - s;
    final paint = _line(BiliColors.onVideo);
    canvas.drawRRect(RRect.fromLTRBR(s, bodyTop, bodyRight, bodyBottom, const Radius.circular(3.2)), paint);
    final keyY = (bodyTop + bodyBottom) / 2;
    canvas.drawLine(Offset(7.2, keyY), Offset(10.5, keyY), _line(BiliColors.onVideo, BiliMetrics.chromeLockKey));
    final shackle = Path();
    if (locked) {
      const legLeft = 4.6, legRight = 13.6, radius = (legRight - legLeft) / 2, arcY = 4.9;
      shackle
        ..moveTo(legLeft, bodyTop)
        ..lineTo(legLeft, arcY)
        ..arcToPoint(const Offset(legRight, arcY), radius: const Radius.circular(radius))
        ..lineTo(legRight, bodyTop);
    } else {
      const legLeft = 13.3, legRight = 20.2, radius = (legRight - legLeft) / 2, arcY = 4.5;
      shackle
        ..moveTo(legLeft, bodyTop)
        ..lineTo(legLeft, arcY)
        ..arcToPoint(const Offset(legRight, arcY), radius: const Radius.circular(radius))
        ..lineTo(legRight, 6.2);
    }
    canvas.drawPath(shackle, paint);
  }

  @override
  bool shouldRepaint(_LockPainter oldDelegate) => oldDelegate.locked != locked;
}
