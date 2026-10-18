import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'landscape_chrome.dart';
import 'seek_bar.dart';
import 'player_ui.dart';

/// 竖屏's controls, filling the screen (BiliNative `VerticalChrome.swift`, measured on 09): back and ⋮ at the top, the
/// title over the bar, then the 弹 toggle, 详情页 and 横屏全屏. The uploader, the action column, the search row and
/// the 发弹幕 field come in later slices; their room is kept so nothing else moves when they do.
class VerticalChrome extends StatelessWidget {
  const VerticalChrome({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([ui.chrome, ui.panels, ui.session]),
      builder: (context, _) {
        final shown = ui.chrome.visible && ui.panels.value == null;
        return IgnorePointer(
          key: const ValueKey('vertical-chrome'),
          ignoring: !shown,
          child: DefaultTextStyle(
            style: fullScreenText,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: math.max(insets.top - BiliMetrics.verticalTopLift, 0),
                  child: ChromeSlide(shown: shown, from: const Offset(0, -BiliMetrics.chromeSlide), child: _topRow()),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: insets.bottom,
                  child: ChromeSlide(
                    shown: shown,
                    from: const Offset(0, BiliMetrics.chromeSlide / 2),
                    child: _bottom(),
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

  Widget _topRow() => Row(
    children: [
      FullScreenButton(
        key: const ValueKey('vertical-back'),
        label: '返回',
        onTap: ui.onBack,
        child: const ChromeBackGlyph(
          width: BiliMetrics.verticalBackWidth,
          height: BiliMetrics.verticalBackHeight,
          color: BiliColors.chromeFaint,
        ),
      ),
      const Spacer(),
      FullScreenMoreButton(key: const ValueKey('vertical-more'), ui: ui, color: BiliColors.chromeFaint),
    ],
  );

  Widget _bottom() {
    final session = ui.session;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: BiliMetrics.verticalInfoInset, right: BiliMetrics.verticalColumnRoom),
          child: Text(
            session.title,
            key: const ValueKey('vertical-title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BiliColors.onVideo,
              fontSize: BiliMetrics.verticalTitleText,
              height: BiliMetrics.verticalTitleLeading,
            ),
          ),
        ),
        // The search suggestion row (a later slice) sits between the title and the bar.
        const SizedBox(height: BiliMetrics.verticalSearchRoom),
        // The row starts a little above the bar's touch area ends, as in 09.
        SizedBox(
          height: BiliMetrics.barTouchHeight - BiliMetrics.verticalRowLift,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: BiliMetrics.barTouchHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.verticalInfoInset),
              child: FullScreenSeekBar(
                key: const ValueKey('vertical-bar'),
                ui: ui,
                repaint: FullScreenSeekBar.repaintOf(ui),
                style: SeekBarStyle.dot,
              ),
            ),
          ),
        ),
        SizedBox(
          height: BiliMetrics.chromeButton,
          child: Row(
            children: [
              const SizedBox(width: BiliMetrics.verticalInfoInset),
              Expanded(child: _field()),
              const SizedBox(width: BiliMetrics.verticalDetailGap),
              FullScreenButton(
                key: const ValueKey('vertical-detail'),
                label: '详情页',
                onTap: _touch(ui.orientation.exitToInline),
                child: const _DetailGlyph(),
              ),
              const SizedBox(width: BiliMetrics.verticalLandscapeGap),
              FullScreenButton(
                key: const ValueKey('vertical-landscape'),
                label: '横屏全屏',
                onTap: _touch(ui.orientation.enterLandscape),
                child: const CustomPaint(
                  size: Size.square(BiliMetrics.verticalFullScreenGlyph),
                  painter: _FullScreenPainter(),
                ),
              ),
              const SizedBox(width: BiliMetrics.landscapeEdge),
            ],
          ),
        ),
      ],
    );
  }

  /// The dark capsule of 09's 发弹幕 field, with the 弹 toggle at its right end; the field itself is a later slice.
  Widget _field() {
    final session = ui.session;
    return Container(
      height: BiliMetrics.verticalFieldHeight,
      decoration: const ShapeDecoration(color: BiliColors.chromeDarkField, shape: StadiumBorder()),
      child: Row(
        children: [
          const Spacer(),
          Container(
            width: BiliMetrics.verticalDividerWidth,
            height: BiliMetrics.verticalDividerHeight,
            color: BiliColors.chromeDivider,
          ),
          FullScreenButton(
            key: const ValueKey('vertical-danmaku'),
            label: session.danmakuOn ? '关闭弹幕' : '开启弹幕',
            width: BiliMetrics.verticalToggleWidth,
            height: BiliMetrics.verticalFieldHeight,
            onTap: _touch(() => session.setDanmakuOn(!session.danmakuOn)),
            child: DanmakuGlyph(on: session.danmakuOn),
          ),
        ],
      ),
    );
  }
}

/// Inward corners with a small 详情页 pill above and to the right, as on 09.
class _DetailGlyph extends StatelessWidget {
  const _DetailGlyph();

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.center,
    children: [
      const CustomPaint(
        size: Size(BiliMetrics.verticalCornersWidth, BiliMetrics.verticalCornersHeight),
        painter: _CornersPainter(),
      ),
      Transform.translate(
        offset: const Offset(BiliMetrics.verticalBadgeX, BiliMetrics.verticalBadgeY),
        child: Container(
          height: BiliMetrics.verticalBadgeHeight,
          padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.verticalBadgePad),
          alignment: Alignment.center,
          decoration: const ShapeDecoration(
            color: BiliColors.chromeBadgeFill,
            shape: StadiumBorder(
              side: BorderSide(color: BiliColors.chromeBadgeBorder, width: BiliMetrics.verticalBadgeBorder),
            ),
          ),
          child: const Text(
            '详情页',
            softWrap: false,
            textScaler: TextScaler.noScaling,
            style: TextStyle(color: BiliColors.chromeBadgeText, fontSize: BiliMetrics.verticalBadgeText, height: 1),
          ),
        ),
      ),
    ],
  );
}

Paint _stroke() => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = BiliMetrics.verticalGlyphStroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = BiliColors.onVideo;

/// Four brackets whose elbows sit in from the corners, their arms pointing back to the edges.
class _CornersPainter extends CustomPainter {
  const _CornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final arm = math.min(size.width, size.height) * 0.3;
    final path = Path();
    for (final (x, y, sx, sy) in [
      (0.0, 0.0, 1.0, 1.0),
      (size.width, 0.0, -1.0, 1.0),
      (0.0, size.height, 1.0, -1.0),
      (size.width, size.height, -1.0, -1.0),
    ]) {
      final ex = x + sx * arm, ey = y + sy * arm;
      path
        ..moveTo(x, ey)
        ..lineTo(ex, ey)
        ..lineTo(ex, y);
    }
    canvas.drawPath(path, _stroke());
  }

  @override
  bool shouldRepaint(_CornersPainter oldDelegate) => false;
}

/// A top-left and a bottom-right bracket.
class _FullScreenPainter extends CustomPainter {
  const _FullScreenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final arm = size.width * 0.56;
    canvas.drawPath(
      Path()
        ..moveTo(0, arm)
        ..lineTo(0, 0)
        ..lineTo(arm, 0)
        ..moveTo(size.width, size.height - arm)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width - arm, size.height),
      _stroke(),
    );
  }

  @override
  bool shouldRepaint(_FullScreenPainter oldDelegate) => false;
}
