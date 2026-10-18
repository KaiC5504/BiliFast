import 'dart:math' as math;

import 'package:bili_core/api.dart' show VideoDetail;
import 'package:bili_core/logic.dart' show CountFormat;
import 'package:flutter/widgets.dart';

import '../shared/remote_image.dart';
import '../shared/theme.dart';
import 'landscape_chrome.dart';
import 'panels/panel_controller.dart';
import 'player_ui.dart';
import 'portrait_controls.dart';
import 'seek_bar.dart';

/// 竖屏's controls, filling the screen (BiliNative `VerticalChrome.swift`, measured on 09): back and ⋮ at the top, the
/// uploader, the title and its plays over the bar, then the 弹 toggle, 详情页 and 横屏全屏. The search button, 粉丝,
/// 关注, the action column and the search row (slice 6) and the 发弹幕 field (slice 5) have their room kept so nothing
/// else moves when they come.
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
                  bottom: math.max(insets.bottom - BiliMetrics.verticalBottomDrop, 0),
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
      ChromeTap(
        key: const ValueKey('vertical-back'),
        label: '返回',
        onTap: ui.onBack,
        child: const CustomPaint(
          size: Size(BiliMetrics.verticalBackWidth, BiliMetrics.verticalBackHeight),
          painter: _BackPainter(),
        ),
      ),
      const Spacer(),
      ChromeTap(
        key: const ValueKey('vertical-more'),
        label: '更多',
        onTap: _touch(() => ui.panels.open(PlayerPanel.more)),
        child: const _FaintDots(),
      ),
    ],
  );

  Widget _bottom() {
    final session = ui.session;
    final detail = session.detail;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: BiliMetrics.verticalAvatar,
          child: detail == null ? null : _Uploader(detail: detail),
        ),
        const SizedBox(height: BiliMetrics.verticalUploaderGap),
        Padding(
          padding: const EdgeInsets.only(left: BiliMetrics.verticalInfoInset, right: BiliMetrics.verticalColumnRoom),
          child: Text.rich(
            TextSpan(
              text: session.title,
              children: [
                if (detail != null) ...[
                  const WidgetSpan(child: SizedBox(width: BiliMetrics.verticalViewsGap)),
                  TextSpan(
                    text: '${CountFormat.short(detail.stat.view)}播放',
                    style: const TextStyle(fontSize: BiliMetrics.verticalViewsText),
                  ),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    // Centred on the line, so the top padding drops it by half as much.
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: BiliMetrics.verticalChevronGap,
                        top: BiliMetrics.verticalChevronTop,
                      ),
                      child: CustomPaint(
                        size: Size(BiliMetrics.verticalChevronWidth, BiliMetrics.verticalChevronHeight),
                        painter: _ChevronDownPainter(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
        // The search suggestion row (slice 6) sits between the title and the bar.
        const SizedBox(height: BiliMetrics.verticalSearchRoom),
        // The row overlaps the bar's touch area by [verticalRowLift], as on 09.
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
              ChromeTap(
                key: const ValueKey('vertical-detail'),
                label: '详情页',
                onTap: _touch(ui.orientation.exitToInline),
                child: const _DetailGlyph(),
              ),
              const SizedBox(width: BiliMetrics.verticalLandscapeGap),
              ChromeTap(
                key: const ValueKey('vertical-landscape'),
                label: '横屏全屏',
                onTap: _touch(ui.orientation.enterLandscape),
                child: const CustomPaint(size: Size.square(BiliMetrics.fullScreenGlyph), painter: _FullScreenPainter()),
              ),
              const SizedBox(width: BiliMetrics.landscapeEdge),
            ],
          ),
        ),
      ],
    );
  }

  /// The dark capsule of 09's 发弹幕 field, with the 弹 toggle at its right end; the field itself is slice 5.
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
          ChromeTap(
            key: const ValueKey('vertical-danmaku'),
            label: session.danmakuOn ? '关闭弹幕' : '开启弹幕',
            square: false,
            onTap: _touch(() => session.setDanmakuOn(!session.danmakuOn)),
            child: SizedBox(
              width: BiliMetrics.verticalToggleWidth,
              height: BiliMetrics.verticalFieldHeight,
              child: Center(child: DanmakuGlyph(on: session.danmakuOn)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The uploader's avatar with the name at its top; 粉丝 and 关注 (slice 6) go under and beside the name.
class _Uploader extends StatelessWidget {
  const _Uploader({required this.detail});

  final VideoDetail detail;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('vertical-uploader'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(width: BiliMetrics.verticalAvatarInset),
      ClipOval(
        child: SizedBox.square(
          dimension: BiliMetrics.verticalAvatar,
          child: RemoteImage(
            detail.owner.face,
            size: const Size.square(BiliMetrics.verticalAvatar),
            placeholder: const ColoredBox(color: BiliColors.landscapeEndPlaceholder),
          ),
        ),
      ),
      const SizedBox(width: BiliMetrics.verticalAvatarGap),
      Flexible(
        child: Text(
          detail.owner.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.verticalNameText),
        ),
      ),
      const SizedBox(width: BiliMetrics.verticalColumnRoom),
    ],
  );
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
          height: BiliMetrics.badgeHeight,
          padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.badgePadding),
          decoration: const ShapeDecoration(
            color: BiliColors.badgeFill,
            shape: StadiumBorder(
              side: BorderSide(color: BiliColors.badgeBorder, width: BiliMetrics.badgeBorderWidth),
            ),
          ),
          child: const Center(
            widthFactor: 1,
            child: Text(
              '详情页',
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style: TextStyle(color: BiliColors.badgeText, fontSize: BiliMetrics.badgeFont, height: 1),
            ),
          ),
        ),
      ),
    ],
  );
}

/// ⋮ in 09's faint white, without the small player's shadow.
class _FaintDots extends StatelessWidget {
  const _FaintDots();

  @override
  Widget build(BuildContext context) {
    const dot = DecoratedBox(
      decoration: BoxDecoration(color: BiliColors.chromeFaint, shape: BoxShape.circle),
      child: SizedBox.square(dimension: BiliMetrics.moreDot),
    );
    return const Column(mainAxisSize: MainAxisSize.min, spacing: BiliMetrics.moreDotGap, children: [dot, dot, dot]);
  }
}

Paint _stroke({Color color = BiliColors.onVideo, double width = BiliMetrics.chromeGlyphStroke}) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = color;

/// 09's back chevron: smaller than the small player's and faint.
class _BackPainter extends CustomPainter {
  const _BackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = BiliMetrics.backGlyphStroke / 2;
    canvas.drawPath(
      Path()
        ..moveTo(size.width - inset, inset)
        ..lineTo(inset, size.height / 2)
        ..lineTo(size.width - inset, size.height - inset),
      _stroke(color: BiliColors.chromeFaint, width: BiliMetrics.backGlyphStroke),
    );
  }

  @override
  bool shouldRepaint(_BackPainter oldDelegate) => false;
}

/// The ⌄ after the plays.
class _ChevronDownPainter extends CustomPainter {
  const _ChevronDownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = BiliMetrics.verticalChevronStroke / 2;
    canvas.drawPath(
      Path()
        ..moveTo(inset, inset)
        ..lineTo(size.width / 2, size.height - inset)
        ..lineTo(size.width - inset, inset),
      _stroke(width: BiliMetrics.verticalChevronStroke),
    );
  }

  @override
  bool shouldRepaint(_ChevronDownPainter oldDelegate) => false;
}

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
