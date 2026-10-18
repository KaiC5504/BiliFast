import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/logic.dart';
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import '../shared/toast.dart';
import 'panels/panel_controller.dart';
import 'player_ui.dart';
import 'portrait_controls.dart';
import 'seek_bar.dart';

const _fade = Duration(milliseconds: 220);
const _press = Duration(milliseconds: 90);

/// The landscape full-screen controls, filling the screen (BiliNative `LandscapeChrome.swift`, measured on 04): back
/// and the title, ⋮, 截图 and the rotation lock on the right edge, the time, the bar and the bottom row. The bars
/// slide in from their edges as the controls show and stand aside while a panel is open. The top actions (slice 6),
/// 弹幕设置 and the danmaku field (slice 5) have their room kept so nothing else moves when they come.
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
      child: Padding(
        padding: const EdgeInsets.only(top: BiliMetrics.chromeMoreTop),
        child: Row(
          children: [
            ChromeTap(key: const ValueKey('landscape-back'), label: '返回', onTap: ui.onBack, child: const BackGlyph()),
            Expanded(
              child: Text(
                ui.session.title,
                key: const ValueKey('landscape-title'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BiliColors.onVideo,
                  fontSize: BiliMetrics.chromeTitleText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: BiliMetrics.chromeActionsRoom),
            ChromeTap(
              key: const ValueKey('landscape-more'),
              label: '更多',
              onTap: _touch(() => ui.panels.open(PlayerPanel.more)),
              child: const MoreDots(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideColumn(BuildContext context) {
    final locked = ui.orientation.locked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ui.session.canCaptureFrame) ...[
          ChromeTap(
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
        ChromeTap(
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
      padding: EdgeInsets.only(
        left: insets.left,
        right: insets.right,
        bottom: insets.bottom + BiliMetrics.chromeRowBottom,
      ),
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
                _PlayButton(key: const ValueKey('landscape-play'), ui: ui),
                Padding(
                  padding: const EdgeInsets.only(left: BiliMetrics.landscapeEdge),
                  child: ChromeTap(
                    key: const ValueKey('landscape-danmaku'),
                    label: session.danmakuOn ? '关闭弹幕' : '开启弹幕',
                    onTap: _touch(() => session.setDanmakuOn(!session.danmakuOn)),
                    child: DanmakuGlyph(on: session.danmakuOn),
                  ),
                ),
                // 弹幕设置 and the danmaku field (slice 5) sit here.
                const SizedBox(width: BiliMetrics.chromeSettingsRoom),
                const Expanded(child: SizedBox.shrink()),
                const SizedBox(width: BiliMetrics.chromeSpeedGap),
                _TextButton(
                  key: const ValueKey('landscape-speed'),
                  label: '倍速',
                  text: speedLabel(session.rate),
                  onTap: _touch(() => ui.panels.open(PlayerPanel.speed)),
                ),
                const SizedBox(width: BiliMetrics.chromeQualityGap),
                _TextButton(
                  key: const ValueKey('landscape-quality'),
                  label: '清晰度',
                  text: QualityNames.short(
                    qn: session.playingQuality,
                    serverText: session.qualityName(session.playingQuality),
                  ),
                  bold: true,
                  onTap: _touch(() => ui.panels.open(PlayerPanel.quality)),
                ),
                if (session.episodes.isNotEmpty) ...[
                  const SizedBox(width: BiliMetrics.chromeEpisodesGap),
                  _TextButton(
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

/// A line of text on the bottom row, as tall as the glyph buttons.
class _TextButton extends StatelessWidget {
  const _TextButton({super.key, required this.label, required this.text, required this.onTap, this.bold = false});

  final String label;
  final String text;
  final VoidCallback onTap;
  final bool bold;

  @override
  Widget build(BuildContext context) => ChromeTap(
    label: label,
    square: false,
    onTap: onTap,
    child: SizedBox(
      height: BiliMetrics.chromeButton,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.chromeTextPad),
        child: Center(
          widthFactor: 1,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: BiliColors.onVideo,
              fontSize: BiliMetrics.chromeLabelText,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Play or pause, drawn larger and rounder than the small player's (04).
class _PlayButton extends StatelessWidget {
  const _PlayButton({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final session = ui.session;
    return ListenableBuilder(
      listenable: Listenable.merge([session.readout.status, session]),
      builder: (context, _) {
        final playing = session.readout.wantsPlay && !session.ended;
        return ChromeTap(
          label: playing ? '暂停' : '播放',
          onTap: () {
            ui.chrome.show();
            session.togglePlay();
          },
          child: Transform.translate(
            offset: const Offset(BiliMetrics.chromePlayShift, 0),
            child: AnimatedSwitcher(
              duration: _press * 2,
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: CustomPaint(
                key: ValueKey(playing),
                size: const Size(BiliMetrics.chromePlayWidth, BiliMetrics.chromePlayHeight),
                painter: _PlayPainter(playing: playing),
              ),
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

/// Maps a point traced on 04 inside a box of [grid] points (3 px per pt) into [size], so the glyphs scale with their
/// box as the small player's do.
Offset Function(double x, double y) _traced(Size grid, Size size) =>
    (x, y) => Offset(x * size.width / grid.width, y * size.height / grid.height);

extension on Path {
  void moveToPoint(Offset point) => moveTo(point.dx, point.dy);

  void lineToPoint(Offset point) => lineTo(point.dx, point.dy);
}

Radius _round(Size grid, Size size, double r) =>
    Radius.elliptical(r * size.width / grid.width, r * size.height / grid.height);

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

const _danmakuGrid = Size(BiliMetrics.chromeDanmakuWidth, BiliMetrics.chromeDanmakuHeight);

/// The TV, traced on its 21 × 20 box.
class _DanmakuTvPainter extends CustomPainter {
  const _DanmakuTvPainter();

  static const left = 1.5, top = 3.9, right = 19.9, bottom = 18.9, radius = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final p = _traced(_danmakuGrid, size);
    final corner = _round(_danmakuGrid, size, radius);
    // The box leaves its bottom-right corner open for the tick or the cross.
    final box = Path()
      ..moveToPoint(p(right, 14.3))
      ..lineToPoint(p(right, top + radius))
      ..arcToPoint(p(right - radius, top), radius: corner, clockwise: false)
      ..lineToPoint(p(left + radius, top))
      ..arcToPoint(p(left, top + radius), radius: corner, clockwise: false)
      ..lineToPoint(p(left, bottom - radius))
      ..arcToPoint(p(left + radius, bottom), radius: corner, clockwise: false)
      ..lineToPoint(p(11.8, bottom))
      ..moveToPoint(p(5.5, 0.7))
      ..lineToPoint(p(7.4, top - 0.4))
      ..moveToPoint(p(13.9, 0.7))
      ..lineToPoint(p(12, top - 0.4));
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
    final p = _traced(_danmakuGrid, size);
    final path = on
        ? (Path()
            ..moveToPoint(p(12.4, 16.4))
            ..lineToPoint(p(15.7, 18.6))
            ..lineToPoint(p(20.4, 14.5)))
        : (Path()
            ..moveToPoint(p(14.2, 14.2))
            ..lineToPoint(p(19.2, 19.2))
            ..moveToPoint(p(19.2, 14.2))
            ..lineToPoint(p(14.2, 19.2)));
    canvas.drawPath(path, _line(on ? BiliColors.pink : BiliColors.onVideo));
  }

  @override
  bool shouldRepaint(_DanmakuMarkPainter oldDelegate) => oldDelegate.on != on;
}

/// 04's camera, traced on its 20 × 17 box: the body with its hump, the lens, and the flash mark at the top right.
class _CameraPainter extends CustomPainter {
  const _CameraPainter();

  static const _grid = Size(BiliMetrics.chromeCameraWidth, BiliMetrics.chromeCameraHeight);

  @override
  void paint(Canvas canvas, Size size) {
    final p = _traced(_grid, size);
    const s = BiliMetrics.chromeLineStroke / 2;
    const right = BiliMetrics.chromeCameraWidth - s, bottom = BiliMetrics.chromeCameraHeight - s;
    const top = 4.2, r = 3.6;
    final corner = _round(_grid, size, r);
    final lens = p(BiliMetrics.chromeCameraWidth / 2 - 0.4, 10.2);
    final body = Path()
      ..moveToPoint(p(s + r, top))
      ..lineToPoint(p(4.6, top))
      ..lineToPoint(p(6.4, 1.2))
      ..lineToPoint(p(12.6, 1.2))
      ..lineToPoint(p(14.4, top))
      ..lineToPoint(p(right - r, top))
      ..arcToPoint(p(right, top + r), radius: corner)
      ..lineToPoint(p(right, bottom - r))
      ..arcToPoint(p(right - r, bottom), radius: corner)
      ..lineToPoint(p(s + r, bottom))
      ..arcToPoint(p(s, bottom - r), radius: corner)
      ..lineToPoint(p(s, top + r))
      ..arcToPoint(p(s + r, top), radius: corner)
      ..close()
      ..addOval(Rect.fromCenter(center: lens, width: p(6.6, 0).dx, height: p(0, 6.6).dy))
      ..moveToPoint(p(15.8, 0.8))
      ..lineToPoint(p(18.2, 1.3));
    canvas.drawPath(body, _line(BiliColors.onVideo));
  }

  @override
  bool shouldRepaint(_CameraPainter oldDelegate) => false;
}

/// 04's padlock, traced on its 21 × 20.5 box: open, the shackle lifted off to the right; locked, it closes over the
/// body.
class _LockPainter extends CustomPainter {
  const _LockPainter({required this.locked});

  final bool locked;

  static const _grid = Size(BiliMetrics.chromeLockWidth, BiliMetrics.chromeLockHeight);

  @override
  void paint(Canvas canvas, Size size) {
    final p = _traced(_grid, size);
    const s = BiliMetrics.chromeLineStroke / 2;
    const bodyTop = 8.3, bodyRight = 17.7, bodyBottom = BiliMetrics.chromeLockHeight - s;
    final paint = _line(BiliColors.onVideo);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromPoints(p(s, bodyTop), p(bodyRight, bodyBottom)), _round(_grid, size, 3.2)),
      paint,
    );
    const keyY = (bodyTop + bodyBottom) / 2;
    canvas.drawLine(p(7.2, keyY), p(10.5, keyY), _line(BiliColors.onVideo, BiliMetrics.chromeLockKey));
    final (legLeft, legRight, arcY, end) = locked ? (4.6, 13.6, 4.9, bodyTop) : (13.3, 20.2, 4.5, 6.2);
    final shackle = Path()
      ..moveToPoint(p(legLeft, bodyTop))
      ..lineToPoint(p(legLeft, arcY))
      ..arcToPoint(p(legRight, arcY), radius: _round(_grid, size, (legRight - legLeft) / 2))
      ..lineToPoint(p(legRight, end));
    canvas.drawPath(shackle, paint);
  }

  @override
  bool shouldRepaint(_LockPainter oldDelegate) => oldDelegate.locked != locked;
}
