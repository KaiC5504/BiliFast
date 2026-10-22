import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show VideoTagKind;
import 'package:bili_core/logic.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../shared/action_glyphs.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../video/actions/video_actions.dart';
import 'panels/panel_controller.dart';
import 'player_ui.dart';
import 'portrait_controls.dart';
import 'seek_bar.dart';
import 'seek_preview.dart';
import 'status_bar_view.dart';
import 'uploader_source.dart';

const _fade = Duration(milliseconds: 220);

/// The landscape full-screen controls, filling the screen (BiliNative `LandscapeChrome.swift`, measured on 04 and 05):
/// the drawn status bar, back and the title with N人正在看, the uploader's chip and the bgm under it, 点赞 评论 收藏 投币
/// 充电 分享 and ⋮, 截图 and the rotation lock on the right edge, the time, the bar and the bottom row. The bars slide in
/// from their edges as the controls show and stand aside while a panel is open; the status bar goes with the top one,
/// as 25, 27 and the panels (05, 06, 20) show none. The page details' parts have their room kept until they arrive.
/// While the bar is dragged everything but the bar fades for the seek preview (102).
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
      listenable: Listenable.merge([
        ui.chrome,
        ui.panels,
        ui.session,
        ui.orientation,
        ui.details,
        ui.overlay,
        ui.danmaku,
        ui.replyCount,
      ]),
      builder: (context, _) {
        final shown = ui.chrome.visible && ui.panels.value == null;
        return Stack(
          fit: StackFit.expand,
          children: [
            LandscapeCornerOnline(
              ui: ui,
              shown: !ui.chrome.visible && ui.panels.value == null && ui.overlay?.value == null,
            ),
            _controls(context, insets, shown),
            SeekPreview(session: ui.session, shown: shown && ui.chrome.barHeld),
          ],
        );
      },
    );
  }

  Widget _controls(BuildContext context, EdgeInsets insets, bool shown) {
    final aside = shown && !ui.chrome.barHeld;
    return IgnorePointer(
      key: const ValueKey('landscape-chrome'),
      ignoring: !shown,
      child: DefaultTextStyle(
        style: fullScreenText,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ChromeSlide(
              shown: aside,
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
                shown: aside,
                from: const Offset(0, -BiliMetrics.chromeSlide),
                child: _topBar(insets),
              ),
            ),
            Positioned(
              left: insets.left + BiliMetrics.landscapeEdge,
              right: insets.right,
              top: insets.top + LandscapeActionTheme.onlineTop,
              child: ChromeSlide(
                shown: aside,
                from: const Offset(0, -BiliMetrics.chromeSlide),
                child: _UploaderBlock(ui: ui, touch: _touch),
              ),
            ),
            Positioned(
              right: insets.right,
              top: 0,
              bottom: 0,
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -BiliMetrics.chromeSideLift),
                  child: ChromeSlide(
                    shown: aside,
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
                child: _bottomBar(insets, aside: !ui.chrome.barHeld),
              ),
            ),
          ],
        ),
      ),
    );
  }

  VoidCallback _touch(VoidCallback action) => () {
    ui.chrome.show();
    action();
  };

  Widget _topBar(EdgeInsets insets) {
    final row = _topRow(insets);
    final feed = ui.statusBar;
    if (feed == null) return row;
    return Stack(
      children: [
        row,
        Positioned(left: 0, right: 0, top: insets.top, child: LandscapeStatusBar(feed: feed)),
      ],
    );
  }

  Widget _topRow(EdgeInsets insets) {
    const titleStyle = TextStyle(
      color: BiliColors.onVideo,
      fontSize: BiliMetrics.chromeTitleText,
      fontWeight: FontWeight.w600,
    );
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
            const SizedBox(width: LandscapeActionTheme.titleInset),
            Expanded(
              child: Text(
                ui.session.title,
                key: const ValueKey('landscape-title'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
                strutStyle: fullScreenStrut(titleStyle),
              ),
            ),
            SizedBox(
              width: BiliMetrics.chromeActionsRoom,
              child: _TopActions(ui: ui, touch: _touch),
            ),
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

  /// [aside] false keeps only the bar.
  Widget _bottomBar(EdgeInsets insets, {required bool aside}) {
    final session = ui.session;
    final next = session.next;
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
          _GiveWay(
            shown: aside,
            child: SizedBox(
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
          ),
          Padding(
            padding: const EdgeInsets.only(top: BiliMetrics.chromeBarTop),
            child: FullScreenSeekBar(key: const ValueKey('landscape-bar'), ui: ui, repaint: bar, preview: true),
          ),
          _GiveWay(
            shown: aside,
            child: Padding(
              padding: const EdgeInsets.only(top: BiliMetrics.chromeRowTop, right: BiliMetrics.chromeRowTrailing),
              child: Row(
                children: [
                  // 04's play glyph is larger and rounder than the small player's, its pause bars shorter.
                  PlayPauseButton(
                    key: const ValueKey('landscape-play'),
                    session: session,
                    onTap: _touch(session.togglePlay),
                    glyphSize: const Size(BiliMetrics.chromePlayWidth, BiliMetrics.chromePlayHeight),
                    glyphShift: BiliMetrics.chromePlayShift,
                    cornerRadius: BiliMetrics.chromePlayCorner,
                    pauseBar: BiliMetrics.chromePauseBar,
                    pauseGap: BiliMetrics.chromePauseGap,
                    pauseHeight: BiliMetrics.chromePauseShare,
                  ),
                  if (next != null || session.episodes.isNotEmpty) ...[
                    const SizedBox(width: BiliMetrics.landscapeDanmakuLead),
                    _NextButton(
                      onTap: next == null ? null : _touch(() => session.playEpisode(next)),
                      keepUp: ui.chrome.show,
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(left: BiliMetrics.landscapeDanmakuLead),
                    child: ChromeTap(
                      key: const ValueKey('landscape-danmaku'),
                      label: session.danmakuOn ? '关闭弹幕' : '开启弹幕',
                      onTap: _touch(() => session.setDanmakuOn(!session.danmakuOn)),
                      child: DanmakuGlyph(on: session.danmakuOn),
                    ),
                  ),
                  // With danmaku off, 34 closes the row up behind the toggle.
                  if (ui.danmaku case final danmaku? when session.danmakuOn) ...[
                    const SizedBox(width: BiliMetrics.chromeSettingsGap),
                    ChromeTap(
                      key: const ValueKey('landscape-danmaku-settings'),
                      label: '弹幕设置',
                      onTap: _touch(() => ui.panels.open(PlayerPanel.danmakuSettings)),
                      child: const DanmakuSettingsGlyph(),
                    ),
                    const SizedBox(width: BiliMetrics.chromeFieldGap),
                    Expanded(
                      child: _DanmakuField(
                        closed: danmaku.closed,
                        onTap: danmaku.closed ? ui.chrome.show : _touch(danmaku.openSend),
                      ),
                    ),
                  ] else
                    const Expanded(child: SizedBox.shrink()),
                  const SizedBox(width: BiliMetrics.chromeSpeedGap),
                  if (session.episodes.isNotEmpty) ...[
                    _TextButton(
                      key: const ValueKey('landscape-episodes'),
                      label: '选集',
                      text: '选集',
                      onTap: _touch(() => ui.panels.open(PlayerPanel.episodes)),
                    ),
                    const SizedBox(width: LandscapeActionTheme.episodesGap),
                  ],
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom bar's time and row, faded while the bar is dragged; they keep their room so the bar stays put.
class _GiveWay extends StatelessWidget {
  const _GiveWay({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !shown,
    child: AnimatedOpacity(opacity: shown ? 1 : 0, duration: _fade, curve: Curves.easeOut, child: child),
  );
}

/// The full-screen controls draw over the page's own text style, which may be outside any Material.
TextStyle get fullScreenText => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  color: BiliColors.onVideo,
  decoration: TextDecoration.none,
);

/// [BiliFonts.strut] for a Text drawn in [style] under [fullScreenText], which replaces whatever style the page has.
StrutStyle? fullScreenStrut(TextStyle style) => BiliFonts.strut(fullScreenText.merge(style));

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

/// ⏭ after ▶ (05), playing the next part or 合集 episode; with episodes but nothing next it stays, greyed, as on 34,
/// and a tap on it only keeps the controls up.
class _NextButton extends StatelessWidget {
  const _NextButton({required this.onTap, required this.keepUp});

  final VoidCallback? onTap;
  final VoidCallback keepUp;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    final glyph = Transform.translate(
      offset: const Offset(LandscapeActionTheme.nextShift, 0),
      child: const CustomPaint(
        size: Size(LandscapeActionTheme.nextWidth, LandscapeActionTheme.nextHeight),
        painter: _NextPainter(),
      ),
    );
    if (onTap == null) {
      return Semantics(
        key: const ValueKey('landscape-next'),
        button: true,
        enabled: false,
        label: '下一集',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: keepUp,
          child: SizedBox.square(
            dimension: BiliMetrics.chromeButton,
            child: Center(
              child: Opacity(opacity: LandscapeActionTheme.nextOffOpacity, child: glyph),
            ),
          ),
        ),
      );
    }
    return ChromeTap(key: const ValueKey('landscape-next'), label: '下一集', onTap: onTap, child: glyph);
  }
}

/// 05's ⏭: a play triangle with rounded corners whose tip runs into a bar with round ends.
class _NextPainter extends CustomPainter {
  const _NextPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    const r = LandscapeActionTheme.nextCorner;
    final a = Offset.zero, b = Offset(0, h), c = Offset(LandscapeActionTheme.nextTip, h / 2);
    final ab = (a - b).distance, bc = (b - c).distance, ca = (c - a).distance;
    final centre = (a * bc + b * ca + c * ab) / (ab + bc + ca);
    final inradius = LandscapeActionTheme.nextTip * h / (ab + bc + ca);
    // Shrunk towards its incentre by r, then stroked 2r wide with round joins: the full triangle with round corners.
    Offset inward(Offset p) => centre + (p - centre) * ((inradius - r) / inradius);
    final triangle = Path()..addPolygon([inward(a), inward(b), inward(c)], true);
    final fill = Paint()..color = BiliColors.onVideo;
    canvas
      ..drawPath(triangle, fill)
      ..drawPath(
        triangle,
        Paint()
          ..color = BiliColors.onVideo
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 2
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawRRect(
        RRect.fromLTRBR(
          size.width - LandscapeActionTheme.nextBar,
          0,
          size.width,
          h,
          const Radius.circular(LandscapeActionTheme.nextBar / 2),
        ),
        fill,
      );
  }

  @override
  bool shouldRepaint(_NextPainter oldDelegate) => false;
}

/// 04's capsule, opening the send bar; with the uploader's danmaku closed it reads UP主已关闭弹幕 and opens nothing.
class _DanmakuField extends StatelessWidget {
  const _DanmakuField({required this.closed, required this.onTap});

  final bool closed;
  final VoidCallback onTap;

  static const _fieldStyle = TextStyle(
    color: BiliMetrics.chromeFieldInk,
    fontSize: BiliMetrics.chromeFieldText,
    height: 1,
  );

  @override
  Widget build(BuildContext context) {
    final text = closed ? 'UP主已关闭弹幕' : '发个友善的弹幕见证当下';
    return Semantics(
      key: const ValueKey('landscape-danmaku-field'),
      button: !closed,
      label: text,
      onTap: closed ? null : onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: BiliMetrics.chromeButton,
          child: Center(
            child: Container(
              height: BiliMetrics.chromeFieldHeight,
              padding: const EdgeInsets.only(left: BiliMetrics.chromeFieldInset),
              alignment: Alignment.centerLeft,
              decoration: const ShapeDecoration(color: BiliMetrics.chromeFieldFill, shape: StadiumBorder()),
              child: Transform.translate(
                offset: Offset(0, BiliMetrics.chromeFieldDrop),
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: _fieldStyle,
                  strutStyle: fullScreenStrut(_fieldStyle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Touch = VoidCallback Function(VoidCallback action);

Duration _motion(BuildContext context) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : _fade;

/// 点赞 评论 收藏 投币 充电 分享 at the right of the room kept before ⋮; nothing until the video's actions arrive.
class _TopActions extends StatelessWidget {
  const _TopActions({required this.ui, required this.touch});

  final PlayerUi ui;
  final _Touch touch;

  @override
  Widget build(BuildContext context) {
    final actions = ui.details?.actions;
    return AnimatedSwitcher(
      duration: _motion(context),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.centerRight, children: [...previous, ?current]),
      child: actions == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              key: ObjectKey(actions),
              listenable: actions,
              builder: (context, _) => Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final action in [
                    _TopAction(
                      key: const ValueKey('landscape-like'),
                      label: actions.liked ? '取消点赞' : '点赞',
                      glyph: ActionGlyph.like,
                      active: actions.liked,
                      count: actions.likeCount,
                      onTap: touch(() => unawaited(actions.toggleLike())),
                    ),
                    _TopAction(
                      key: const ValueKey('landscape-comments'),
                      label: '评论',
                      glyph: ActionGlyph.comment,
                      count: ui.replies,
                      onTap: touch(() => ui.onComments?.call()),
                    ),
                    _TopAction(
                      key: const ValueKey('landscape-favourite'),
                      label: actions.favorited ? '已收藏' : '收藏',
                      glyph: ActionGlyph.favourite,
                      active: actions.favorited,
                      count: actions.favCount,
                      onTap: touch(() => actions.ask(ActionPrompt.favourites)),
                    ),
                    _TopAction(
                      key: const ValueKey('landscape-coin'),
                      label: actions.coins > 0 ? '已投币' : '投币',
                      glyph: ActionGlyph.coin,
                      active: actions.coins > 0,
                      onTap: touch(() => actions.ask(ActionPrompt.coin)),
                    ),
                    _TopAction(
                      key: const ValueKey('landscape-charge'),
                      label: '充电',
                      glyph: ActionGlyph.charge,
                      onTap: touch(() => showToast(context, '暂不支持充电')),
                    ),
                    _TopAction(
                      key: const ValueKey('landscape-share'),
                      label: '分享',
                      glyph: ActionGlyph.share,
                      onTap: touch(() => actions.ask(ActionPrompt.share)),
                    ),
                  ]) ...[action, const SizedBox(width: LandscapeActionTheme.buttonGap)],
                ],
              ),
            ),
    );
  }
}

/// A 44 pt action with its count, when it has one, as a superscript at its top right (04).
class _TopAction extends StatelessWidget {
  const _TopAction({
    super.key,
    required this.label,
    required this.glyph,
    required this.onTap,
    this.active = false,
    this.count,
  });

  final String label;
  final ActionGlyph glyph;
  final VoidCallback onTap;
  final bool active;
  final int? count;

  @override
  Widget build(BuildContext context) => ChromeTap(
    label: label,
    square: false,
    onTap: onTap,
    child: SizedBox.square(
      dimension: BiliMetrics.chromeButton,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: _fitted(glyph, ActionPop(glyph, active: active, stroke: LandscapeActionTheme.outline))),
          if (count case final count? when count > 0)
            Positioned(
              left: BiliMetrics.chromeButton / 2 + LandscapeActionTheme.countLead,
              top: 0,
              child: Baseline(
                baseline: LandscapeActionTheme.countBaseline,
                baselineType: TextBaseline.alphabetic,
                child: Text(
                  CountFormat.short(count),
                  maxLines: 1,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: BiliColors.onVideo,
                    fontSize: LandscapeActionTheme.countText,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 05's 👍, 💬 and ⭐ against the outlines 简介 shares: squeezed upright about the button's centre and lifted.
Widget _fitted(ActionGlyph glyph, Widget icon) {
  final (squash, lift) = switch (glyph) {
    ActionGlyph.like => (LandscapeActionTheme.likeSquash, LandscapeActionTheme.likeLift),
    ActionGlyph.comment => (LandscapeActionTheme.commentSquash, 0.0),
    ActionGlyph.favourite => (LandscapeActionTheme.favouriteSquash, LandscapeActionTheme.favouriteLift),
    _ => (1.0, 0.0),
  };
  if (squash == 1 && lift == 0) return icon;
  return Transform.translate(
    offset: Offset(0, -lift),
    child: Transform.scale(scaleY: squash, child: icon),
  );
}

/// An action's outline glyph, solid and pink while on (as BiliNative's `.fill` icons); it swells and settles as it
/// turns on.
class ActionPop extends StatefulWidget {
  const ActionPop(
    this.glyph, {
    super.key,
    required this.active,
    this.size = LandscapeActionTheme.iconSize,
    this.stroke,
  });

  final ActionGlyph glyph;
  final bool active;
  final double size;

  /// The line in pt; null keeps the shared glyph's.
  final double? stroke;

  @override
  State<ActionPop> createState() => _ActionPopState();
}

class _ActionPopState extends State<ActionPop> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    value: 1,
  );
  late final Animation<double> _scale = _pop.drive(
    TweenSequence([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: LandscapeActionTheme.pop).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: LandscapeActionTheme.pop, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 70,
      ),
    ]),
  );

  @override
  void didUpdateWidget(ActionPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !MediaQuery.disableAnimationsOf(context)) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: ActionIcon(
      widget.glyph,
      solid: widget.active,
      size: widget.size,
      stroke: widget.stroke,
      color: widget.active ? BiliColors.pink : BiliColors.onVideo,
    ),
  );
}

/// N人正在看 under the title, then the uploader's chip (avatar, name, + 关注) and the bgm's (05). N人正在看 and the
/// uploader keep their lines whether or not they have arrived; the bgm's chip shows only for a video with one.
class _UploaderBlock extends StatelessWidget {
  const _UploaderBlock({required this.ui, required this.touch});

  final PlayerUi ui;
  final _Touch touch;

  @override
  Widget build(BuildContext context) {
    final details = ui.details;
    final owner = uploaderOf(ui.session.detail?.owner, details?.uploader, ui.session.video?.owner);
    final face = owner?.face;
    final name = owner?.name ?? '';
    final actions = details?.actions;
    final bgm = details?.tags.where((tag) => tag.kind == VideoTagKind.bgm).firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: LandscapeActionTheme.onlineHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: BiliMetrics.chromeButton + LandscapeActionTheme.onlineInset),
            child: details == null ? null : _Online(online: details.online),
          ),
        ),
        SizedBox(
          height: LandscapeActionTheme.uploaderHeight,
          child: face == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(
                    left: LandscapeActionTheme.avatarInset - LandscapeActionTheme.chipInset,
                  ),
                  child: _Chip(
                    key: const ValueKey('landscape-uploader'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: LandscapeActionTheme.chipInset),
                        ClipOval(
                          key: const ValueKey('landscape-avatar'),
                          child: SizedBox.square(
                            dimension: LandscapeActionTheme.avatar,
                            child: RemoteImage.avatar(face, size: const Size.square(LandscapeActionTheme.avatar)),
                          ),
                        ),
                        if (name.isNotEmpty) ...[
                          const SizedBox(width: LandscapeActionTheme.nameGap),
                          Flexible(
                            child: _ChipText(
                              name,
                              key: const ValueKey('landscape-uploader-name'),
                              box: LandscapeActionTheme.uploaderHeight,
                            ),
                          ),
                        ],
                        if (actions != null)
                          _Follow(actions: actions, touch: touch, divided: name.isNotEmpty)
                        else
                          const SizedBox(width: LandscapeActionTheme.followTrailing),
                      ],
                    ),
                  ),
                ),
        ),
        if (bgm != null)
          Padding(
            padding: const EdgeInsets.only(
              top:
                  LandscapeActionTheme.chipGap -
                  (LandscapeActionTheme.uploaderHeight - LandscapeActionTheme.chipHeight) / 2,
              left: LandscapeActionTheme.avatarInset - LandscapeActionTheme.chipInset,
            ),
            child: _MusicChip(name: bgm.name),
          ),
      ],
    );
  }
}

/// 05's translucent capsule behind a row of the uploader block, [LandscapeActionTheme.chipHeight] tall and centred
/// in whatever height the row takes, so its buttons can keep a taller target than the capsule.
class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: const _ChipPainter(), child: child);
}

class _ChipPainter extends CustomPainter {
  const _ChipPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width,
      height: LandscapeActionTheme.chipHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(LandscapeActionTheme.chipHeight / 2)),
      Paint()..color = LandscapeActionTheme.chipFill,
    );
  }

  @override
  bool shouldRepaint(_ChipPainter oldDelegate) => false;
}

/// A chip's 12.5 pt line in a [box] pt tall row, standing on the baseline 05's text shares whatever the font.
class _ChipText extends StatelessWidget {
  const _ChipText(this.text, {super.key, required this.box, this.color = BiliColors.onVideo});

  final String text;
  final double box;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: color, fontSize: LandscapeActionTheme.followText);
    return SizedBox(
      height: box,
      child: Baseline(
        baseline: box / 2 + LandscapeActionTheme.chipBaselineDrop,
        baselineType: TextBaseline.alphabetic,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
          strutStyle: fullScreenStrut(style),
        ),
      ),
    );
  }
}

/// 发现《…》 under the uploader (05). There is no music page yet, so it leads nowhere, as 简介's chip doesn't.
class _MusicChip extends StatelessWidget {
  const _MusicChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('landscape-bgm'),
    label: name,
    excludeSemantics: true,
    child: _Chip(
      child: SizedBox(
        height: LandscapeActionTheme.chipHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: LandscapeActionTheme.musicLead),
            const CustomPaint(
              size: Size(LandscapeActionTheme.musicGlyphWidth, LandscapeActionTheme.musicGlyphHeight),
              painter: _MusicPainter(),
            ),
            const SizedBox(width: LandscapeActionTheme.musicGap),
            Flexible(child: _ChipText(name, box: LandscapeActionTheme.chipHeight)),
            const SizedBox(width: LandscapeActionTheme.musicTrailing),
          ],
        ),
      ),
    ),
  );
}

/// 05's two beamed quavers, traced on their 13.67 × 14.33 box: a beam rising to the right over two stems, each
/// ending in a round head, the left one lower.
class _MusicPainter extends CustomPainter {
  const _MusicPainter();

  static const _grid = Size(LandscapeActionTheme.musicGlyphWidth, LandscapeActionTheme.musicGlyphHeight);

  @override
  void paint(Canvas canvas, Size size) {
    final p = _traced(_grid, size);
    final scale = size.width / _grid.width;
    final paint = Paint()..color = BiliColors.onVideo;
    final beamTopLeft = p(3.13, 1.1), beamTopRight = p(13.5, 0);
    canvas
      ..drawPath(
        Path()
          ..moveToPoint(p(3.13, 2.1))
          ..quadraticBezierTo(beamTopLeft.dx, beamTopLeft.dy, p(4.1, 1.45).dx, p(4.1, 1.45).dy)
          ..lineToPoint(p(12.7, 0))
          ..quadraticBezierTo(beamTopRight.dx, beamTopRight.dy, p(13.5, 0.8).dx, p(13.5, 0.8).dy)
          ..lineToPoint(p(13.5, 10))
          ..lineToPoint(p(12, 10))
          ..lineToPoint(p(12, 2.85))
          ..lineToPoint(p(4.63, 4.05))
          ..lineToPoint(p(4.63, 12))
          ..lineToPoint(p(3.13, 12))
          ..close(),
        paint,
      )
      ..drawCircle(p(2.25, 12), 2.33 * scale, paint)
      ..drawCircle(p(11.33, 10), 2.25 * scale, paint);
  }

  @override
  bool shouldRepaint(_MusicPainter oldDelegate) => false;
}

class _Online extends StatelessWidget {
  const _Online({required this.online});

  final ValueListenable<String?> online;

  static const _style = TextStyle(color: LandscapeActionTheme.online, fontSize: LandscapeActionTheme.onlineText);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: online,
    builder: (context, count, _) => AnimatedSwitcher(
      duration: _motion(context),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
      child: count == null
          ? const SizedBox.shrink()
          : Row(
              key: const ValueKey('landscape-online'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const CustomPaint(
                  size: Size(LandscapeActionTheme.onlineIconWidth, LandscapeActionTheme.onlineIconHeight),
                  painter: _OnlinePainter(
                    color: LandscapeActionTheme.online,
                    stroke: LandscapeActionTheme.onlineIconStroke,
                  ),
                ),
                const SizedBox(width: LandscapeActionTheme.onlineGap),
                Text(
                  '$count人正在看',
                  maxLines: 1,
                  softWrap: false,
                  style: _style,
                  strutStyle: fullScreenStrut(_style),
                ),
              ],
            ),
    ),
  );
}

/// 25's faint N人正在看 in the bottom-left corner, which takes no touches; [shown] while the controls are hidden and
/// no panel is open (BiliNative `LandscapeChrome.swift`). The end screen keeps it under its dim, as 27 does.
class LandscapeCornerOnline extends StatelessWidget {
  const LandscapeCornerOnline({super.key, required this.ui, required this.shown});

  final PlayerUi ui;
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final details = ui.details;
    if (details == null) return const SizedBox.shrink();
    final motion = _motion(context);
    return IgnorePointer(
      // The same count is read under the title once the controls show.
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.only(
              left: MediaQuery.paddingOf(context).left + LandscapeActionTheme.cornerInset,
              bottom: LandscapeActionTheme.cornerCentre - LandscapeActionTheme.cornerHeight / 2,
            ),
            child: SizedBox(
              height: LandscapeActionTheme.cornerHeight,
              child: AnimatedSwitcher(
                duration: motion,
                layoutBuilder: (current, previous) =>
                    Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                child: !shown
                    ? const SizedBox.shrink()
                    : ValueListenableBuilder(
                        valueListenable: details.online,
                        builder: (context, count, _) => AnimatedSwitcher(
                          duration: motion,
                          layoutBuilder: (current, previous) =>
                              Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                          child: count == null ? const SizedBox.shrink() : _corner(count),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _corner(String count) {
    // Outside the chrome's DefaultTextStyle, so nothing ambient (Material's spacing and line height) may leak in.
    final style = fullScreenText.copyWith(
      color: LandscapeActionTheme.corner,
      fontSize: LandscapeActionTheme.cornerText,
      fontWeight: FontWeight.normal,
      letterSpacing: 0,
      height: 1,
    );
    return Row(
      key: const ValueKey('landscape-corner-online'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const CustomPaint(
          size: Size(LandscapeActionTheme.cornerIconWidth, LandscapeActionTheme.cornerIconHeight),
          painter: _OnlinePainter(color: LandscapeActionTheme.corner, stroke: LandscapeActionTheme.cornerIconStroke),
        ),
        const SizedBox(width: LandscapeActionTheme.cornerGap),
        Text('$count人正在看', maxLines: 1, softWrap: false, style: style, strutStyle: BiliFonts.strut(style)),
      ],
    );
  }
}

/// The chip's + 关注 (05): white text with a thin plus after the divider, the chip's end its own; 已关注 is grey in
/// the same place. Without a name before it, it follows the avatar as on 04, with no divider.
class _Follow extends StatelessWidget {
  const _Follow({required this.actions, required this.touch, required this.divided});

  final VideoActions actions;
  final _Touch touch;
  final bool divided;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: actions,
    builder: (context, _) {
      final following = actions.following;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (divided) ...[
            const SizedBox(width: LandscapeActionTheme.dividerGap),
            const SizedBox(
              key: ValueKey('landscape-uploader-divider'),
              width: LandscapeActionTheme.dividerWidth,
              height: LandscapeActionTheme.dividerHeight,
              child: ColoredBox(color: LandscapeActionTheme.divider),
            ),
          ],
          ChromeTap(
            key: const ValueKey('landscape-follow'),
            label: following ? '已关注' : '关注',
            square: false,
            onTap: touch(actions.tapFollow),
            child: SizedBox(
              height: LandscapeActionTheme.uploaderHeight,
              child: Padding(
                padding: EdgeInsets.only(
                  left: divided ? LandscapeActionTheme.dividerGap : LandscapeActionTheme.avatarGap,
                  right: LandscapeActionTheme.followTrailing,
                ),
                child: AnimatedSwitcher(
                  duration: _motion(context),
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                  child: Row(
                    key: ValueKey(following),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!following) ...[
                        const CustomPaint(
                          size: Size.square(LandscapeActionTheme.plus),
                          painter: FollowPlusPainter(
                            color: BiliColors.onVideo,
                            stroke: LandscapeActionTheme.plusStroke,
                          ),
                        ),
                        const SizedBox(width: LandscapeActionTheme.plusGap),
                      ],
                      _ChipText(
                        following ? '已关注' : '关注',
                        box: LandscapeActionTheme.uploaderHeight,
                        color: following ? LandscapeActionTheme.followed : BiliColors.onVideo,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// The thin plus before 关注.
class FollowPlusPainter extends CustomPainter {
  const FollowPlusPainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke;
    canvas
      ..drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint)
      ..drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
  }

  @override
  bool shouldRepaint(FollowPlusPainter oldDelegate) => oldDelegate.color != color || oldDelegate.stroke != stroke;
}

/// 04's viewers glyph, traced on its 13 × 11 box: a head open at the bottom into two flared legs, and a second
/// person's edge behind it to the right.
class _OnlinePainter extends CustomPainter {
  const _OnlinePainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  static const _grid = Size(LandscapeActionTheme.onlineIconWidth, LandscapeActionTheme.onlineIconHeight);

  @override
  void paint(Canvas canvas, Size size) {
    final p = _traced(_grid, size);
    final scale = size.width / _grid.width;
    final front = p(4.53, 4.65);
    final back = p(9.2, 5.57);
    final path = Path()
      ..moveToPoint(p(0.31, 10.84))
      ..arcTo(Rect.fromCircle(center: front, radius: 4.22 * scale), 121.7 * math.pi / 180, 298 * math.pi / 180, false)
      ..lineToPoint(p(8.78, 10.84))
      ..arcTo(Rect.fromCircle(center: back, radius: 3.47 * scale), -73 * math.pi / 180, 134 * math.pi / 180, true)
      ..lineToPoint(p(12.67, 10.84));
    canvas.drawPath(path, _line(color, stroke));
  }

  @override
  bool shouldRepaint(_OnlinePainter oldDelegate) => oldDelegate.color != color || oldDelegate.stroke != stroke;
}

/// 弹 on a little TV: a pink tick in its corner while danmaku show, a crossed-out circle while they are off (34, 35).
class DanmakuGlyph extends StatelessWidget {
  const DanmakuGlyph({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: BiliMetrics.chromeDanmakuWidth,
    height: BiliMetrics.chromeDanmakuHeight,
    child: AnimatedSwitcher(
      duration: _motion(context),
      layoutBuilder: (current, previous) => Stack(clipBehavior: Clip.none, children: [...previous, ?current]),
      child: on
          ? const _MarkedTv(key: ValueKey(true), mark: _TickPainter())
          : const _MarkedTv(
              key: ValueKey(false),
              mark: _NoEntryPainter(),
              rightEnd: 10.2,
              bottomEnd: 10.7,
              clearance: _Clearance(_noEntryClearance),
            ),
    ),
  );
}

/// 04's 弹幕设置: the same TV with a nut over its open corner, the strokes stopping short of it.
class DanmakuSettingsGlyph extends StatelessWidget {
  const DanmakuSettingsGlyph({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: BiliMetrics.chromeDanmakuWidth,
    height: BiliMetrics.chromeDanmakuHeight,
    child: _MarkedTv(mark: _NutPainter(), rightEnd: 9.3, bottomEnd: 10.4, clearance: _Clearance(_nutClearance)),
  );
}

/// The TV and its 弹 with [mark] over the open corner; [clearance], when set, keeps 弹 a gap away from the mark.
class _MarkedTv extends StatelessWidget {
  const _MarkedTv({super.key, required this.mark, this.rightEnd = 14.3, this.bottomEnd = 11.8, this.clearance});

  final CustomPainter mark;
  final double rightEnd;
  final double bottomEnd;
  final CustomClipper<Path>? clearance;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(
        child: ClipPath(
          clipper: clearance,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _DanmakuTvPainter(rightEnd: rightEnd, bottomEnd: bottomEnd)),
              ),
              // The box's centre, below the antennae.
              const Positioned(
                left: _DanmakuTvPainter.left,
                top: _DanmakuTvPainter.top,
                right: BiliMetrics.chromeDanmakuWidth - _DanmakuTvPainter.right,
                bottom: BiliMetrics.chromeDanmakuHeight - _DanmakuTvPainter.bottom,
                child: Center(
                  child: Text(
                    '弹',
                    style: TextStyle(
                      color: BiliColors.onVideo,
                      fontSize: BiliMetrics.chromeDanmakuText,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Positioned.fill(child: CustomPaint(painter: mark)),
    ],
  );
}

/// The [SeekBar] driven by the session: a drag scrubs, a resting finger hints, a lift seeks.
class FullScreenSeekBar extends StatelessWidget {
  const FullScreenSeekBar({
    super.key,
    required this.ui,
    required this.repaint,
    this.style = SeekBarStyle.tv,
    this.preview = false,
  });

  final PlayerUi ui;
  final Listenable repaint;
  final SeekBarStyle style;

  /// Holding it shows the seek preview (102), landscape's.
  final bool preview;

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
      onHold: preview
          ? (held) {
              if (held) session.wantSeekFrames();
              ui.chrome.holdBar(held);
            }
          : null,
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

const _danmakuGrid = Size(BiliMetrics.chromeDanmakuWidth, BiliMetrics.chromeDanmakuHeight);

/// The TV, traced on its 21 × 20 box; its right side stops at [rightEnd] and its bottom at [bottomEnd].
class _DanmakuTvPainter extends CustomPainter {
  const _DanmakuTvPainter({this.rightEnd = 14.3, this.bottomEnd = 11.8});

  static const left = 1.5, top = 3.9, right = 19.9, bottom = 18.9, radius = 4.0;

  final double rightEnd;
  final double bottomEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final p = _traced(_danmakuGrid, size);
    final corner = _round(_danmakuGrid, size, radius);
    // The box leaves its bottom-right corner open for the tick, the cross or the nut.
    final box = Path()
      ..moveToPoint(p(right, rightEnd))
      ..lineToPoint(p(right, top + radius))
      ..arcToPoint(p(right - radius, top), radius: corner, clockwise: false)
      ..lineToPoint(p(left + radius, top))
      ..arcToPoint(p(left, top + radius), radius: corner, clockwise: false)
      ..lineToPoint(p(left, bottom - radius))
      ..arcToPoint(p(left + radius, bottom), radius: corner, clockwise: false)
      ..lineToPoint(p(bottomEnd, bottom))
      ..moveToPoint(p(5.5, 0.7))
      ..lineToPoint(p(7.4, top - 0.4))
      ..moveToPoint(p(13.9, 0.7))
      ..lineToPoint(p(12, top - 0.4));
    canvas.drawPath(box, _line(BiliColors.onVideo));
  }

  @override
  bool shouldRepaint(_DanmakuTvPainter oldDelegate) =>
      oldDelegate.rightEnd != rightEnd || oldDelegate.bottomEnd != bottomEnd;
}

const _nutCentre = Offset(16.75, 15.9);
const _nutRadius = 4.5;

/// 34's crossed-out circle, centred where 04's nut is.
const _noEntryCentre = Offset(16.7, 15.8);
const _noEntryRadius = 3.45;

/// The gap the TV's 弹 keeps from a mark, beyond half the mark's stroke.
const _markGap = 1.8;

/// A hexagon standing on a corner around [_nutCentre], each corner cut [round] along its edges and curved.
Path _hexagon(Offset Function(double x, double y) p, double radius, {double round = 0}) {
  final corners = [
    for (var i = 0; i < 6; i++)
      _nutCentre + Offset.fromDirection(-math.pi / 2 + i * math.pi / 3, radius),
  ];
  final path = Path();
  for (var i = 0; i < 6; i++) {
    final corner = corners[i];
    final before = corners[(i + 5) % 6], after = corners[(i + 1) % 6];
    final into = corner + (before - corner) / radius * round;
    final out = corner + (after - corner) / radius * round;
    if (i == 0) {
      path.moveToPoint(p(into.dx, into.dy));
    } else {
      path.lineToPoint(p(into.dx, into.dy));
    }
    final control = p(corner.dx, corner.dy), end = p(out.dx, out.dy);
    path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
  }
  return path..close();
}

// A hexagon's sides sit cos 30° of its corner radius from the centre, so a gap g past the sides grows the corner
// radius by g / cos 30°.
Path _nutClearance(Offset Function(double x, double y) p) =>
    _hexagon(p, _nutRadius + (BiliMetrics.chromeLineStroke / 2 + _markGap) / math.cos(math.pi / 6));

Path _noEntryClearance(Offset Function(double x, double y) p) {
  final centre = p(_noEntryCentre.dx, _noEntryCentre.dy);
  final edge = p(_noEntryCentre.dx + _noEntryRadius + BiliMetrics.chromeLineStroke / 2 + _markGap, _noEntryCentre.dy);
  return Path()..addOval(Rect.fromCircle(center: centre, radius: edge.dx - centre.dx));
}

/// Everything in the glyph's box but a mark's [shape], traced on the box.
class _Clearance extends CustomClipper<Path> {
  const _Clearance(this.shape);

  final Path Function(Offset Function(double x, double y) p) shape;

  @override
  Path getClip(Size size) =>
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), shape(_traced(_danmakuGrid, size)));

  @override
  bool shouldReclip(_Clearance oldClipper) => oldClipper.shape != shape;
}

/// 04's nut, its corners rounded, with a dot at its centre.
class _NutPainter extends CustomPainter {
  const _NutPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = _traced(_danmakuGrid, size);
    final dot = p(_nutCentre.dx, _nutCentre.dy);
    canvas
      ..drawPath(_hexagon(p, _nutRadius, round: 0.8), _line(BiliColors.onVideo))
      ..drawCircle(dot, p(1.25, 0).dx, Paint()..color = BiliColors.onVideo);
  }

  @override
  bool shouldRepaint(_NutPainter oldDelegate) => false;
}

class _TickPainter extends CustomPainter {
  const _TickPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = _traced(_danmakuGrid, size);
    canvas.drawPath(
      Path()
        ..moveToPoint(p(13.8, 16.4))
        ..lineToPoint(p(17.1, 18.6))
        ..lineToPoint(p(21.8, 14.5)),
      _line(BiliColors.pink),
    );
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) => false;
}

/// The circle with its slash from top left to bottom right.
class _NoEntryPainter extends CustomPainter {
  const _NoEntryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = _traced(_danmakuGrid, size);
    final centre = p(_noEntryCentre.dx, _noEntryCentre.dy);
    final reach = _noEntryRadius * math.sqrt1_2;
    canvas.drawPath(
      Path()
        ..addOval(Rect.fromCircle(center: centre, radius: p(_noEntryRadius, 0).dx))
        ..moveToPoint(p(_noEntryCentre.dx - reach, _noEntryCentre.dy - reach))
        ..lineToPoint(p(_noEntryCentre.dx + reach, _noEntryCentre.dy + reach)),
      _line(BiliColors.onVideo),
    );
  }

  @override
  bool shouldRepaint(_NoEntryPainter oldDelegate) => false;
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
