import 'dart:math' as math;

import 'package:bili_core/api.dart' show UploaderCard, VideoDetail;
import 'package:bili_core/logic.dart' show CountFormat, TimeFormat;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../player/bili_player.dart' show PlayerStatus;
import '../shared/action_glyphs.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../video/actions/video_actions.dart';
import '../video/page_details.dart';
import 'landscape_chrome.dart';
import 'panels/panel_controller.dart';
import 'player_ui.dart';
import 'portrait_controls.dart';
import 'seek_bar.dart';
import 'seek_preview.dart';

/// 竖屏's controls, filling the screen (BiliNative `VerticalChrome.swift`, measured on 09): back, N人正在看 and ⋮ at
/// the top, the action column down the right, the uploader with 粉丝 and 关注, the title and its plays over the bar,
/// then the 发弹幕 field with the 弹 toggle, 详情页 and 横屏全屏 (drawn as 16's phone and half screen for an upright
/// video, still turning to landscape: what the official one does there isn't known). The search button and the search
/// row have their room kept so nothing else moves when they come; so does whatever the page details haven't brought
/// yet. As in the official app they stay up, hiding only for a panel or an action overlay; paused, the bar carries the
/// TV and 118's ▶ and the time sit over the video. While the bar is dragged everything but the bar fades for the seek
/// preview (19, 20).
class VerticalChrome extends StatelessWidget {
  const VerticalChrome({super.key, required this.ui});

  final PlayerUi ui;

  static const _titleStyle = TextStyle(
    color: BiliColors.onVideo,
    fontSize: BiliMetrics.verticalTitleText,
    height: BiliMetrics.verticalTitleLeading,
  );

  static const _fieldStyle = TextStyle(
    color: VerticalActionTheme.fieldInk,
    fontSize: VerticalActionTheme.fieldText,
    height: 1,
  );

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final bottom = math.max(insets.bottom - BiliMetrics.verticalBottomDrop, 0.0);
    return ListenableBuilder(
      listenable: Listenable.merge([
        ui.chrome,
        ui.panels,
        ui.session,
        ui.session.readout.status,
        ui.danmaku,
        ui.replyCount,
        ui.overlay,
      ]),
      builder: (context, _) {
        final shown = ui.panels.value == null && ui.overlay?.value == null;
        final held = ui.chrome.barHeld;
        final aside = shown && !held;
        final paused = ui.session.readout.status.value == PlayerStatus.paused && !ui.session.opening;
        return IgnorePointer(
          key: const ValueKey('vertical-chrome'),
          ignoring: !shown,
          child: DefaultTextStyle(
            style: fullScreenText,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _PausedPlay(ui: ui, paused: paused, shown: shown, held: held),
                Positioned(
                  left: 0,
                  right: 0,
                  top: math.max(insets.top - BiliMetrics.verticalTopLift, 0),
                  child: _GiveWay(shown: aside, from: const Offset(0, -BiliMetrics.chromeSlide), child: _topRow()),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottom,
                  child: ChromeSlide(
                    shown: shown,
                    from: const Offset(0, BiliMetrics.chromeSlide / 2),
                    child: _bottom(paused: paused, held: held),
                  ),
                ),
                if (ui.details case final details?)
                  Positioned(
                    right: VerticalActionTheme.columnTrailing,
                    bottom: bottom + VerticalActionTheme.columnLift,
                    width: VerticalActionTheme.columnWidth,
                    child: _GiveWay(
                      shown: aside,
                      from: const Offset(BiliMetrics.chromeSlide, 0),
                      child: _ActionColumn(details: details, ui: ui, touch: _touch),
                    ),
                  ),
                Positioned.fill(child: SeekPreview(session: ui.session, shown: shown && held, upright: true)),
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
        child: const BackGlyph(
          width: BiliMetrics.verticalBackWidth,
          height: BiliMetrics.verticalBackHeight,
          color: BiliColors.chromeFaint,
          shadow: false,
        ),
      ),
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: switch (ui.details) {
            final details? => _Online(online: details.online),
            null => null,
          },
        ),
      ),
      ChromeTap(
        key: const ValueKey('vertical-more'),
        label: '更多',
        onTap: _touch(() => ui.panels.open(PlayerPanel.more)),
        child: const MoreDots(color: BiliColors.chromeFaint, shadow: false),
      ),
    ],
  );

  /// [held] keeps only the bar.
  Widget _bottom({required bool paused, required bool held}) {
    final session = ui.session;
    final detail = session.detail;
    final episode = _collectionEpisode();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GiveWay(
          shown: !held,
          child: SizedBox(
            height: BiliMetrics.verticalAvatar,
            child: detail == null ? null : _Uploader(detail: detail, details: ui.details, touch: _touch),
          ),
        ),
        const SizedBox(height: BiliMetrics.verticalUploaderGap),
        _GiveWay(
          shown: !held,
          child: Padding(
            padding: const EdgeInsets.only(left: BiliMetrics.verticalInfoInset, right: BiliMetrics.verticalColumnRoom),
            child: _title(detail, episode),
          ),
        ),
        // The search suggestion row will sit between the title and the bar.
        const SizedBox(height: BiliMetrics.verticalSearchRoom),
        // The row overlaps the bar's touch area by [verticalRowLift], as on 09.
        SizedBox(
          height: BiliMetrics.barTouchHeight - BiliMetrics.verticalRowLift,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: BiliMetrics.barTouchHeight,
            child: Transform.translate(
              offset: const Offset(0, -BiliMetrics.verticalBarLift),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.verticalInfoInset),
                child: FullScreenSeekBar(
                  key: const ValueKey('vertical-bar'),
                  ui: ui,
                  repaint: FullScreenSeekBar.repaintOf(ui),
                  style: paused ? SeekBarStyle.pausedDot : SeekBarStyle.dot,
                  preview: true,
                ),
              ),
            ),
          ),
        ),
        _GiveWay(
          shown: !held,
          child: SizedBox(
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
                  child: session.isVertical
                      ? Image.asset(
                          VerticalActionTheme.screenModeAsset,
                          key: const ValueKey('vertical-screen-mode'),
                          width: VerticalActionTheme.screenModeGlyph,
                          height: VerticalActionTheme.screenModeGlyph,
                        )
                      : const CustomPaint(
                          size: Size.square(BiliMetrics.fullScreenGlyph),
                          painter: FullScreenPainter(),
                        ),
                ),
                const SizedBox(width: BiliMetrics.landscapeEdge),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _title(VideoDetail? detail, int? episode) => Text.rich(
    TextSpan(
      children: [
        if (episode != null) ..._collection(episode),
        TextSpan(text: ui.session.title),
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
    style: _titleStyle,
    strutStyle: fullScreenStrut(_titleStyle),
  );

  /// The playing video's place in its 合集 (from 1), when it is in one; null for parts or a video on its own.
  int? _collectionEpisode() {
    final session = ui.session;
    if (session.detail?.season == null || session.episodesAreParts) return null;
    final index = session.episodes.indexWhere((episode) => episode.current);
    return index < 0 ? null : index + 1;
  }

  /// 118's 合集 · 第N集 and the bar before the title.
  static List<InlineSpan> _collection(int episode) => [
    const WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: EdgeInsets.only(
          left: VerticalActionTheme.collectionGlyphLead,
          right: VerticalActionTheme.collectionGlyphGap,
        ),
        child: CustomPaint(
          size: Size.square(VerticalActionTheme.collectionGlyph),
          painter: _LayersPainter(),
        ),
      ),
    ),
    const TextSpan(text: '合集', style: TextStyle(fontWeight: FontWeight.w600)),
    const WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox(
        width: VerticalActionTheme.collectionDotRoom,
        child: Center(
          child: SizedBox.square(
            dimension: VerticalActionTheme.collectionDot,
            child: DecoratedBox(decoration: ShapeDecoration(color: BiliColors.onVideo, shape: CircleBorder())),
          ),
        ),
      ),
    ),
    TextSpan(text: '第$episode集', style: const TextStyle(fontWeight: FontWeight.w600)),
    const WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: EdgeInsets.only(
          left: VerticalActionTheme.collectionBarLead,
          right: VerticalActionTheme.collectionBarTrail,
        ),
        child: SizedBox(
          width: VerticalActionTheme.collectionBarWidth,
          height: VerticalActionTheme.collectionBarHeight,
          child: ColoredBox(color: BiliColors.onVideo),
        ),
      ),
    ),
  ];

  /// The dark capsule of 09's 发弹幕 field, with the 弹 toggle at its right end. With danmaku off it reads 已关闭弹幕
  /// (35), with the uploader's closed UP主已关闭弹幕, and either way opens nothing.
  Widget _field() {
    final session = ui.session;
    final closed = ui.danmaku?.closed ?? false;
    final send = switch (ui.danmaku) {
      final danmaku? when session.danmakuOn && !closed => _touch(danmaku.openSend),
      _ => null,
    };
    final text = closed ? 'UP主已关闭弹幕' : (session.danmakuOn ? '发弹幕' : '已关闭弹幕');
    return Container(
      height: BiliMetrics.verticalFieldHeight,
      decoration: const ShapeDecoration(color: BiliColors.chromeDarkField, shape: StadiumBorder()),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              key: const ValueKey('vertical-danmaku-field'),
              button: send != null,
              label: text,
              onTap: send,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: send ?? ui.chrome.show,
                child: Padding(
                  padding: const EdgeInsets.only(left: VerticalActionTheme.fieldInset),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.translate(
                      offset: Offset(0, VerticalActionTheme.fieldDrop),
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
          ),
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

/// The uploader's avatar, the name (pink for 大会员) with 粉丝 under it, and + 关注 beside it, each once known.
class _Uploader extends StatelessWidget {
  const _Uploader({required this.detail, required this.details, required this.touch});

  final VideoDetail detail;
  final PageDetails? details;
  final VoidCallback Function(VoidCallback) touch;

  @override
  Widget build(BuildContext context) {
    final details = this.details;
    if (details == null) return _row(null, null);
    return ListenableBuilder(
      listenable: details,
      builder: (context, _) => switch (details.actions) {
        final actions? => ListenableBuilder(
          listenable: actions,
          builder: (context, _) => _row(details.uploader, actions),
        ),
        null => _row(details.uploader, null),
      },
    );
  }

  static const _fansStyle = TextStyle(
    color: VerticalActionTheme.fans,
    fontSize: VerticalActionTheme.fansText,
    height: 1,
  );

  static TextStyle _nameStyle(UploaderCard? uploader) => fullScreenText.merge(
    TextStyle(
      color: uploader?.isVip ?? false ? BiliColors.pink : BiliColors.onVideo,
      fontSize: BiliMetrics.verticalNameText,
      fontWeight: FontWeight.w500,
      height: 1,
    ),
  );

  Widget _row(UploaderCard? uploader, VideoActions? actions) => Row(
    key: const ValueKey('vertical-uploader'),
    children: [
      const SizedBox(width: BiliMetrics.verticalAvatarInset),
      Container(
        key: const ValueKey('vertical-avatar'),
        width: BiliMetrics.verticalAvatar,
        height: BiliMetrics.verticalAvatar,
        foregroundDecoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: BiliColors.onVideo, width: BiliMetrics.verticalAvatarRing),
        ),
        child: ClipOval(
          child: RemoteImage.avatar(detail.owner.face, size: const Size.square(BiliMetrics.verticalAvatar)),
        ),
      ),
      const SizedBox(width: BiliMetrics.verticalAvatarGap),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: VerticalActionTheme.nameLine,
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Transform.translate(
                  offset: Offset(0, VerticalActionTheme.nameDrop),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: _nameStyle(uploader),
                    child: Text(
                      detail.owner.name,
                      key: const ValueKey('vertical-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      strutStyle: BiliFonts.strut(_nameStyle(uploader)),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: VerticalActionTheme.fansLine,
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: _FadeIn(
                  child: uploader == null
                      ? null
                      : Transform.translate(
                          offset: Offset(0, VerticalActionTheme.fansDrop),
                          child: Text(
                            '${CountFormat.short(uploader.fans)}粉丝',
                            key: const ValueKey('vertical-fans'),
                            maxLines: 1,
                            style: _fansStyle,
                            strutStyle: fullScreenStrut(_fansStyle),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      _FadeIn(
        child: actions == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: VerticalActionTheme.followGap),
                child: _FollowPill(following: actions.following, onTap: touch(actions.tapFollow)),
              ),
      ),
      const SizedBox(width: BiliMetrics.verticalColumnRoom),
    ],
  );
}

/// [ChromeSlide] that takes no touches while out of sight, for the parts that give way to the held bar.
class _GiveWay extends StatelessWidget {
  const _GiveWay({required this.shown, required this.child, this.from = Offset.zero});

  final bool shown;
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !shown,
    child: ChromeSlide(shown: shown, from: from, child: child),
  );
}

/// Fades a part in when it arrives and out when it goes, taking no room while absent.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    layoutBuilder: (current, previous) => current == null && previous.isEmpty
        ? const SizedBox.shrink()
        : Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
    child: child,
  );
}

/// + 关注 in pink; 已关注 dims to a grey glass pill.
class _FollowPill extends StatelessWidget {
  const _FollowPill({required this.following, required this.onTap});

  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ChromeTap(
      key: const ValueKey('vertical-follow'),
      label: following ? '已关注' : '关注',
      square: false,
      onTap: onTap,
      child: AnimatedContainer(
        duration: still ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: VerticalActionTheme.followHeight,
        padding: const EdgeInsets.only(
          left: VerticalActionTheme.followLead,
          right: VerticalActionTheme.followTrailing,
        ),
        decoration: ShapeDecoration(
          color: following ? VerticalActionTheme.followingFill : BiliColors.pink,
          shape: const StadiumBorder(),
        ),
        child: AnimatedSize(
          duration: still ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
            duration: still ? Duration.zero : const Duration(milliseconds: 180),
            child: Row(
              key: ValueKey(following),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!following) ...[
                  const CustomPaint(
                    size: Size.square(VerticalActionTheme.followPlus),
                    painter: _PlusPainter(),
                  ),
                  const SizedBox(width: VerticalActionTheme.followPlusGap),
                ],
                Transform.translate(
                  offset: Offset(0, VerticalActionTheme.followTextDrop),
                  child: Text(
                    following ? '已关注' : '关注',
                    style: TextStyle(
                      color: following ? VerticalActionTheme.followingText : BiliColors.onPink,
                      fontSize: VerticalActionTheme.followText,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlusPainter extends CustomPainter {
  const _PlusPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _stroke(VerticalActionTheme.followPlusStroke)..color = BiliColors.onPink;
    const inset = VerticalActionTheme.followPlusStroke / 2;
    canvas
      ..drawLine(Offset(inset, size.height / 2), Offset(size.width - inset, size.height / 2), paint)
      ..drawLine(Offset(size.width / 2, inset), Offset(size.width / 2, size.height - inset), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter oldDelegate) => false;
}

/// The viewers mark and N人正在看, from the page's poll; nothing until it answers.
class _Online extends StatelessWidget {
  const _Online({required this.online});

  final ValueListenable<String?> online;

  static const _style = TextStyle(
    color: VerticalActionTheme.online,
    fontSize: VerticalActionTheme.onlineText,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: online,
    builder: (context, count, _) => _FadeIn(
      child: count == null
          ? null
          : Padding(
              key: const ValueKey('vertical-online'),
              padding: const EdgeInsets.only(left: VerticalActionTheme.onlineLead),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CustomPaint(
                    size: Size(VerticalActionTheme.onlineIconWidth, VerticalActionTheme.onlineIconHeight),
                    painter: _ViewersPainter(),
                  ),
                  const SizedBox(width: VerticalActionTheme.onlineGap),
                  Text('$count人正在看', maxLines: 1, style: _style, strutStyle: fullScreenStrut(_style)),
                ],
              ),
            ),
    ),
  );
}

/// Two outlined heads and shoulders, the nearer one whole, as 09 draws them before N人正在看.
class _ViewersPainter extends CustomPainter {
  const _ViewersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _stroke(VerticalActionTheme.onlineIconStroke)..color = VerticalActionTheme.online;
    final w = size.width, h = size.height;
    const inset = VerticalActionTheme.onlineIconStroke / 2;
    final r = h * 0.29;
    final head = Offset(r + inset, r + inset);
    // The head opens at the bottom into the shoulders.
    final front = Path()
      ..moveTo(inset, h - inset)
      ..lineTo(head.dx - r * 0.55, head.dy + r * 0.83)
      ..arcTo(Rect.fromCircle(center: head, radius: r), math.pi * 0.69, math.pi * 1.62, false)
      ..lineTo(head.dx * 2 - inset, h - inset);
    final backHead = Offset(w - r - inset, head.dy);
    final back = Path()
      ..addArc(Rect.fromCircle(center: backHead, radius: r), -math.pi * 0.62, math.pi * 1.26)
      ..moveTo(backHead.dx + r * 0.3, backHead.dy + r * 0.96)
      ..lineTo(w - inset, h - inset);
    canvas
      ..drawPath(front, paint)
      ..drawPath(back, paint);
  }

  @override
  bool shouldRepaint(_ViewersPainter oldDelegate) => false;
}

/// 点赞 评论 投币 收藏 分享 down the right, solid white with their counts, pink once given; once the actions exist.
class _ActionColumn extends StatelessWidget {
  const _ActionColumn({required this.details, required this.ui, required this.touch});

  final PageDetails details;
  final PlayerUi ui;
  final VoidCallback Function(VoidCallback) touch;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: details,
    builder: (context, _) {
      final actions = details.actions;
      final detail = ui.session.detail;
      return AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        child: actions == null || detail == null
            ? const SizedBox(width: VerticalActionTheme.columnWidth)
            : ListenableBuilder(
                key: ObjectKey(actions),
                listenable: actions,
                builder: (context, _) => _items(actions, ui.replies ?? detail.stat.reply),
              ),
      );
    },
  );

  Widget _items(VideoActions actions, int replies) => Column(
    key: const ValueKey('vertical-actions'),
    mainAxisSize: MainAxisSize.min,
    spacing: VerticalActionTheme.itemSpacing,
    children: [
      _ColumnItem(
        key: const ValueKey('vertical-like'),
        label: '点赞',
        glyph: ActionGlyph.like,
        size: VerticalActionTheme.likeIcon,
        count: actions.likeCount,
        active: actions.liked,
        onTap: touch(actions.toggleLike),
      ),
      _ColumnItem(
        key: const ValueKey('vertical-comment'),
        label: '评论',
        glyph: ActionGlyph.comment,
        size: VerticalActionTheme.commentIcon,
        count: replies,
        active: false,
        onTap: touch(() => ui.onComments?.call()),
      ),
      _ColumnItem(
        key: const ValueKey('vertical-coin'),
        label: '投币',
        glyph: ActionGlyph.coin,
        size: VerticalActionTheme.coinIcon,
        count: actions.coinCount,
        active: actions.coins > 0,
        onTap: touch(() => actions.ask(ActionPrompt.coin)),
      ),
      _ColumnItem(
        key: const ValueKey('vertical-favourite'),
        label: '收藏',
        glyph: ActionGlyph.favourite,
        size: VerticalActionTheme.favouriteIcon,
        count: actions.favCount,
        active: actions.favorited,
        onTap: touch(() => actions.ask(ActionPrompt.favourites)),
      ),
      _ColumnItem(
        key: const ValueKey('vertical-share'),
        label: '分享',
        glyph: ActionGlyph.share,
        size: VerticalActionTheme.shareIcon,
        count: actions.shareCount,
        active: false,
        onTap: touch(() => actions.ask(ActionPrompt.share)),
      ),
    ],
  );
}

class _ColumnItem extends StatelessWidget {
  const _ColumnItem({
    super.key,
    required this.label,
    required this.glyph,
    required this.size,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final ActionGlyph glyph;
  final double size;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final text = CountFormat.short(count);
    return ChromeTap(
      label: label,
      square: false,
      onTap: onTap,
      child: SizedBox(
        width: VerticalActionTheme.columnWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: VerticalActionTheme.iconBox,
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: _Pop(
                  active: active,
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: active ? BiliColors.pink : VerticalActionTheme.icon),
                    duration: still ? Duration.zero : const Duration(milliseconds: 200),
                    builder: (context, color, _) =>
                        ActionIcon(glyph, solid: true, size: size, color: color ?? VerticalActionTheme.icon),
                  ),
                ),
              ),
            ),
            const SizedBox(height: VerticalActionTheme.countGap),
            SizedBox(
              height: VerticalActionTheme.countLine,
              child: AnimatedSwitcher(
                duration: still ? Duration.zero : const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: Offset(0, child.key == ValueKey(text) ? 0.5 : -0.5),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  text,
                  key: ValueKey(text),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: VerticalActionTheme.count,
                    fontSize: VerticalActionTheme.countText,
                    fontWeight: FontWeight.w600,
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
}

/// Swells and settles once when [active] turns on, as the official icons do when tapped.
class _Pop extends StatefulWidget {
  const _Pop({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: VerticalActionTheme.popScale).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: VerticalActionTheme.popScale, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(_Pop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale, child: widget.child);
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
        painter: CornersPainter(inward: true),
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

Paint _stroke(double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = BiliColors.onVideo;

/// 118's ▶ over the paused video with the time under it among the controls, at one place on the screen whatever the
/// video's shape (16). A tap on it plays, as one anywhere on the video does.
class _PausedPlay extends StatelessWidget {
  const _PausedPlay({required this.ui, required this.paused, required this.shown, required this.held});

  final PlayerUi ui;
  final bool paused;
  final bool shown;

  /// The bar is held: both give way to the seek preview (19).
  final bool held;

  static TextStyle get _timeStyle => fullScreenText.merge(
    const TextStyle(
      color: BiliColors.onVideo,
      fontSize: VerticalActionTheme.pausedTimeText,
      fontWeight: FontWeight.w600,
      height: 1,
      fontFeatures: [FontFeature.tabularFigures()],
      shadows: [Shadow(color: BiliColors.chromeShade, blurRadius: VerticalActionTheme.pausedTimeShadowBlur)],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!paused) return const SizedBox.shrink();
    final session = ui.session;
    return LayoutBuilder(
      builder: (context, constraints) {
        final top = constraints.maxHeight * BiliMetrics.verticalVideoCentre;
        return Stack(
          children: [
            Positioned(
              top: top,
              left: (constraints.maxWidth - VerticalActionTheme.pausedPlayWidth) / 2,
              child: _GiveWay(
                shown: !held,
                child: Semantics(
                  key: const ValueKey('vertical-paused-play'),
                  button: true,
                  label: '播放',
                  onTap: session.togglePlay,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: session.togglePlay,
                    child: Image.asset(
                      VerticalActionTheme.pausedPlayAsset,
                      width: VerticalActionTheme.pausedPlayWidth,
                      height: VerticalActionTheme.pausedPlayHeight,
                      opacity: const AlwaysStoppedAnimation(VerticalActionTheme.pausedPlayOpacity),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: top + VerticalActionTheme.pausedTimeTop,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: ChromeSlide(
                  shown: shown && !held,
                  from: Offset.zero,
                  child: ListenableBuilder(
                    listenable: FullScreenSeekBar.repaintOf(ui),
                    builder: (context, _) => Text(
                      '${TimeFormat.clock(session.position)} / ${TimeFormat.clock(session.duration.value)}',
                      key: const ValueKey('vertical-paused-time'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: _timeStyle,
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
}

/// 118's 合集 glyph: a diamond with two more layers under it, each a chevron.
class _LayersPainter extends CustomPainter {
  const _LayersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = VerticalActionTheme.collectionGlyphStroke / 2;
    final w = size.width, h = size.height;
    final paint = _stroke(VerticalActionTheme.collectionGlyphStroke);
    final mid = w / 2;
    // Traced off 118 at 3x: the diamond from 0 to 0.47 with its sides at 0.24, the layers 0.25 and 0.45 lower.
    final top = inset, side = h * 0.24, bottom = h * 0.47;
    canvas.drawPath(
      Path()
        ..moveTo(mid, top)
        ..lineTo(w - inset, side)
        ..lineTo(mid, bottom)
        ..lineTo(inset, side)
        ..close(),
      paint,
    );
    for (final drop in [h * 0.25, h * 0.45]) {
      canvas.drawPath(
        Path()
          ..moveTo(inset, side + drop)
          ..lineTo(mid, math.min(bottom + drop, h - inset))
          ..lineTo(w - inset, side + drop),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LayersPainter oldDelegate) => false;
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
      _stroke(BiliMetrics.verticalChevronStroke),
    );
  }

  @override
  bool shouldRepaint(_ChevronDownPainter oldDelegate) => false;
}
