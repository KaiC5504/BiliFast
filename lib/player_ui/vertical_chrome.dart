import 'dart:math' as math;

import 'package:bili_core/api.dart' show UploaderCard, VideoDetail;
import 'package:bili_core/logic.dart' show CountFormat, TimeFormat;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart' show BoxHitTestResult, RenderProxyBox;
import 'package:flutter/widgets.dart';

import '../player/bili_player.dart' show PlayerStatus;
import '../shared/action_glyphs.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../space/uploader_tap.dart';
import '../video/actions/video_actions.dart';
import '../video/page_details.dart';
import '../video/player_session.dart';
import '../video/story/story_drag.dart';
import '../video/story/story_feed.dart';
import 'landscape_chrome.dart';
import 'panels/panel_controller.dart';
import 'player_gestures.dart';
import 'player_ui.dart';
import 'portrait_controls.dart';
import 'seek_bar.dart';
import 'seek_preview.dart';
import 'speed_lock.dart';

/// 竖屏's controls, filling the screen (BiliNative `VerticalChrome.swift`, measured on 09): back, N人正在看 and ⋮ at
/// the top, the action column down the right, the uploader with 粉丝 and 关注, the title and its plays over the bar,
/// then the 发弹幕 field with the 弹 toggle, 详情页 and the last button by the video's shape: 横屏全屏 for a wide video
/// (09, 184), 清屏 for an upright or square one (16, 180). The search button and the search row have their room kept
/// so nothing else moves when they come; so does whatever the page details haven't brought yet. As in the official app
/// they stay up, hiding only for a panel or an action overlay; paused, the bar carries the TV and 118's ▶ and the time
/// sit over the video. While the bar is dragged everything but the bar fades for the seek preview (19, 20), and while
/// 2× is held everything but the progress line gives way to the lock's hint (182, 183). 清屏 keeps only 人正在看, the
/// danmaku, the progress line, the bottom row and a play button with the time (180, 186). While the page moves under
/// the finger everything but the top row moves with it, faint (185). The rows under the top row start inside the left
/// edge's strip and leave it to the edge swipe: a touch landing there goes back or does nothing, as anywhere on that
/// edge.
class VerticalChrome extends StatelessWidget {
  const VerticalChrome({super.key, required this.ui});

  final PlayerUi ui;

  /// The video the last bottom button is 清屏 for: upright as the picture's band lays it out, or square.
  static bool uprightShape(PlayerSession session) {
    if (session.layoutVertical) return true;
    final shape = session.videoShape;
    return shape != null && shape.width > 0 && shape.height == shape.width;
  }

  @override
  Widget build(BuildContext context) {
    final story = ui.story;
    if (story == null) return _chrome(context, null);
    return ValueListenableBuilder(valueListenable: story, builder: (context, feed, _) => _chrome(context, feed));
  }

  Widget _chrome(BuildContext context, StoryFeed? feed) {
    final insets = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        ui.chrome,
        ui.panels,
        ui.session,
        ui.session.readout.status,
        ui.danmaku,
        ui.replyCount,
        ui.overlay,
        feed,
        ui.clean,
        ui.speedLock,
      ]),
      builder: (context, _) {
        final shown = ui.panels.value == null && ui.overlay?.value == null;
        final held = ui.chrome.barHeld;
        final barOnly = held || _lockHeld;
        final aside = shown && !barOnly;
        final clean = ui.clean?.value ?? false;
        final paused = ui.session.readout.status.value == PlayerStatus.paused && !ui.session.opening;
        final pending = _pending(feed);
        final details = ui.details;
        final openUploader = UploaderTap.maybeOf(context);
        return IgnorePointer(
          key: const ValueKey('vertical-chrome'),
          ignoring: !shown,
          child: DefaultTextStyle(
            style: fullScreenText,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _Moving(
                    drag: ui.storyDrag,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (!clean) _PausedPlay(ui: ui, paused: paused, shown: shown, held: barOnly),
                        _PageLayout(
                          block: ChromeSlide(
                            shown: shown,
                            from: const Offset(0, BiliMetrics.chromeSlide / 2),
                            child: _EdgeGap(
                              child: _bottom(
                                paused: paused,
                                barOnly: barOnly,
                                clean: clean,
                                pending: pending,
                                upright: pending?.upright ?? uprightShape(ui.session),
                                openUploader: openUploader,
                              ),
                            ),
                          ),
                          column: pending != null || details != null
                              ? _GiveWay(
                                  shown: aside && !clean,
                                  from: const Offset(BiliMetrics.chromeSlide, 0),
                                  child: switch (pending) {
                                    final entry? => IgnorePointer(child: _entryColumn(entry, 'vertical')),
                                    null => _ActionColumn(details: details!, ui: ui, touch: _touch),
                                  },
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: math.max(insets.top - BiliMetrics.verticalTopLift, 0),
                  child: _GiveWay(
                    shown: aside,
                    from: const Offset(0, -BiliMetrics.chromeSlide),
                    child: _topRow(context, clean: clean),
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

  /// 2× is held, or armed to lock: the lock's hint takes the place of all but the progress line (182, 183).
  bool get _lockHeld => switch (ui.speedLock?.value) {
    SpeedLockPhase.holding || SpeedLockPhase.armed => true,
    _ => false,
  };

  /// The feed's video when the page's details are still the last one's, just after a swipe.
  StoryEntry? _pending(StoryFeed? feed) {
    final entry = feed?.current;
    if (entry == null || entry.bvid == ui.session.detail?.bvid) return null;
    return entry;
  }

  VoidCallback _touch(VoidCallback action) => () {
    ui.chrome.show();
    action();
  };

  /// The uploader row's tap, the page deciding what it opens; none without the page's [UploaderTap].
  VoidCallback? _uploaderTap(void Function(UploaderRef)? open, UploaderRef uploader) =>
      open == null || uploader.mid <= 0 ? null : _touch(() => open(uploader));

  /// In 清屏 only N人正在看 stays, dimmed and moved to the left edge (180).
  Widget _topRow(BuildContext context, {required bool clean}) {
    final motion = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220);
    return Row(
      children: [
        AnimatedContainer(
          duration: motion,
          curve: Curves.easeOutCubic,
          width: clean ? VerticalCleanTheme.backRoom : BiliMetrics.chromeButton,
          height: BiliMetrics.chromeButton,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: BiliMetrics.chromeButton,
            maxWidth: BiliMetrics.chromeButton,
            child: _GiveWay(
              shown: !clean,
              child: ChromeTap(
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
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: switch (ui.details) {
              final details? => AnimatedOpacity(
                opacity: clean ? VerticalCleanTheme.onlineOpacity : 1,
                duration: motion,
                child: _Online(online: details.online, clean: clean),
              ),
              null => null,
            },
          ),
        ),
        _GiveWay(
          shown: !clean,
          child: ChromeTap(
            key: const ValueKey('vertical-more'),
            label: '更多',
            onTap: _touch(() => ui.panels.open(PlayerPanel.more)),
            child: const MoreDots(color: BiliColors.chromeFaint, shadow: false),
          ),
        ),
      ],
    );
  }

  /// [barOnly] keeps only the bar; [clean] the bar, the bottom row and the play button with the time.
  Widget _bottom({
    required bool paused,
    required bool barOnly,
    required bool clean,
    required StoryEntry? pending,
    required bool upright,
    required void Function(UploaderRef)? openUploader,
  }) {
    final session = ui.session;
    final detail = session.detail;
    final info = !barOnly && !clean;
    return _Block(
      uploader: _GiveWay(
        shown: info,
        child: switch (pending) {
          final entry? => _entryUploader(
            entry,
            'vertical',
            onOpen: _uploaderTap(
              openUploader,
              UploaderRef(mid: entry.ownerMid, name: entry.ownerName, face: entry.ownerFace),
            ),
          ),
          null when detail != null => _Uploader(
            detail: detail,
            details: ui.details,
            touch: _touch,
            onOpen: _uploaderTap(
              openUploader,
              UploaderRef(mid: detail.owner.mid, name: detail.owner.name, face: detail.owner.face),
            ),
          ),
          null => const SizedBox.shrink(),
        },
      ),
      title: _GiveWay(
        shown: info,
        child: switch (pending) {
          final entry? => _entryTitle(entry, const ValueKey('vertical-title')),
          null => _titleText(
            key: const ValueKey('vertical-title'),
            title: session.title,
            views: detail?.stat.view,
            episode: _collectionEpisode(),
          ),
        },
      ),
      room: clean ? _GiveWay(shown: !barOnly, child: _CleanPlay(ui: ui, touch: _touch)) : null,
      bar: FullScreenSeekBar(
        key: const ValueKey('vertical-bar'),
        ui: ui,
        repaint: FullScreenSeekBar.repaintOf(ui),
        style: paused ? SeekBarStyle.pausedDot : SeekBarStyle.dot,
        preview: true,
      ),
      row: _GiveWay(
        shown: !barOnly,
        child: _BottomRow(
          field: _field(),
          detail: ChromeTap(
            key: const ValueKey('vertical-detail'),
            label: '详情页',
            onTap: _touch(ui.orientation.exitToInline),
            child: const _DetailGlyph(),
          ),
          last: _lastButton(upright: upright, clean: clean),
        ),
      ),
    );
  }

  /// 横屏全屏 for a wide video; for an upright one the APK's screen mode, switching 清屏 (180).
  Widget _lastButton({required bool upright, required bool clean}) {
    final toggle = ui.clean;
    return ChromeTap(
      key: const ValueKey('vertical-landscape'),
      label: !upright ? '横屏全屏' : (clean ? '退出清屏' : '清屏'),
      onTap: _touch(switch (toggle) {
        final toggle? when upright => () => toggle.value = !toggle.value,
        _ => ui.orientation.enterLandscape,
      }),
      child: _ScreenModeGlyph(upright: upright, clean: clean, imageKey: const ValueKey('vertical-screen-mode')),
    );
  }

  /// The playing video's place in its 合集 (from 1), when it is in one; null for parts or a video on its own.
  int? _collectionEpisode() {
    final session = ui.session;
    if (session.detail?.season == null || session.episodesAreParts) return null;
    final index = session.episodes.indexWhere((episode) => episode.current);
    return index < 0 ? null : index + 1;
  }

  /// The dark capsule of 09's 发弹幕 field, with the 弹 toggle at its right end. With danmaku off it reads 已关闭弹幕
  /// (35), with the uploader's closed UP主已关闭弹幕, and either way opens nothing.
  Widget _field() {
    final session = ui.session;
    final closed = ui.danmaku?.closed ?? false;
    final send = switch (ui.danmaku) {
      final danmaku? when session.danmakuOn && !closed => _touch(danmaku.openSend),
      _ => null,
    };
    return _Field(
      text: closed ? 'UP主已关闭弹幕' : (session.danmakuOn ? '发弹幕' : '已关闭弹幕'),
      danmakuOn: session.danmakuOn,
      onSend: send,
      onTap: send ?? ui.chrome.show,
      onToggle: _touch(() => session.setDanmakuOn(!session.danmakuOn)),
    );
  }
}

/// A neighbour page's controls in 竖屏, drawn still from its [entry] while the page under the finger moves: all but the
/// top bar, which stays where it is. The same pieces as [VerticalChrome]'s, laid out the same; the pager dims and
/// places it. It takes no touches and says nothing to VoiceOver.
class VerticalChromePreview extends StatelessWidget {
  const VerticalChromePreview({super.key, required this.entry, this.danmakuOn = true});

  final StoryEntry entry;

  /// The page's 弹 setting, which the neighbour opens with.
  final bool danmakuOn;

  static const _prefix = 'vertical-preview';

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: DefaultTextStyle(
        style: fullScreenText,
        child: _PageLayout(
          block: _Block(
            uploader: _entryUploader(entry, _prefix),
            title: _entryTitle(entry, const ValueKey('$_prefix-title')),
            bar: SeekBar(
              key: const ValueKey('$_prefix-bar'),
              position: () => 0,
              duration: () => math.max(entry.duration, 1).toDouble(),
              buffered: () => 0,
              repaint: const AlwaysStoppedAnimation(0),
              onScrub: _ignore,
              onCommit: _ignore,
              onCancel: _nothing,
              style: SeekBarStyle.dot,
            ),
            row: _BottomRow(
              field: _Field(
                text: danmakuOn ? '发弹幕' : '已关闭弹幕',
                danmakuOn: danmakuOn,
                onTap: _nothing,
                onToggle: _nothing,
                keyed: false,
              ),
              detail: const SizedBox.square(dimension: BiliMetrics.chromeButton, child: Center(child: _DetailGlyph())),
              last: SizedBox.square(
                dimension: BiliMetrics.chromeButton,
                child: Center(
                  child: _ScreenModeGlyph(upright: entry.upright, imageKey: const ValueKey('$_prefix-screen-mode')),
                ),
              ),
            ),
          ),
          column: _entryColumn(entry, _prefix),
        ),
      ),
    ),
  );
}

void _nothing() {}

void _ignore(double _) {}

Widget _entryUploader(StoryEntry entry, String prefix, {VoidCallback? onOpen}) => _UploaderRow(
  prefix: prefix,
  face: entry.ownerFace,
  name: entry.ownerName,
  fans: entry.ownerFans > 0 ? entry.ownerFans : null,
  following: entry.following ? null : false,
  onOpen: onOpen,
);

Widget _entryTitle(StoryEntry entry, Key key) => _titleText(
  key: key,
  title: entry.title,
  views: entry.views > 0 ? entry.views : null,
  episode: entry.seasonTitle == null ? null : entry.seasonIndex,
);

Widget _entryColumn(StoryEntry entry, String prefix) => _columnItems(
  prefix: prefix,
  likes: entry.likes,
  replies: entry.replies,
  coins: entry.coins,
  favourites: entry.favourites,
  shares: entry.shares,
);

const _titleStyle = TextStyle(
  color: BiliColors.onVideo,
  fontSize: BiliMetrics.verticalTitleText,
  height: BiliMetrics.verticalTitleLeading,
);

/// The title with its plays and ⌄ once [views] is known, after 118's 合集 · 第N集 when [episode] is.
Widget _titleText({required Key key, required String title, int? views, int? episode}) => Text.rich(
  TextSpan(
    children: [
      if (episode != null) ..._collection(episode),
      TextSpan(text: title),
      if (views != null) ...[
        const WidgetSpan(child: SizedBox(width: BiliMetrics.verticalViewsGap)),
        TextSpan(
          text: '${CountFormat.short(views)}播放',
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
  key: key,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  style: _titleStyle,
  strutStyle: fullScreenStrut(_titleStyle),
);

/// 118's 合集 · 第N集 and the bar before the title.
List<InlineSpan> _collection(int episode) => [
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

/// Where a page's controls sit: the [block] of rows on the bottom, the [column] down the right above it.
class _PageLayout extends StatelessWidget {
  const _PageLayout({required this.block, this.column});

  final Widget block;
  final Widget? column;

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(MediaQuery.paddingOf(context).bottom - BiliMetrics.verticalBottomDrop, 0.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(left: 0, right: 0, bottom: bottom, child: block),
        if (column case final column?)
          Positioned(
            right: VerticalActionTheme.columnTrailing,
            bottom: bottom + VerticalActionTheme.columnLift,
            width: VerticalActionTheme.columnWidth,
            child: column,
          ),
      ],
    );
  }
}

/// The rows from the uploader down: the uploader, the title, the search row's room (清屏's play and time sit in it),
/// the bar and the bottom row.
class _Block extends StatelessWidget {
  const _Block({required this.uploader, required this.title, required this.bar, required this.row, this.room});

  final Widget uploader;
  final Widget title;
  final Widget bar;
  final Widget row;
  final Widget? room;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(height: BiliMetrics.verticalAvatar, child: uploader),
      const SizedBox(height: BiliMetrics.verticalUploaderGap),
      Padding(
        padding: const EdgeInsets.only(left: BiliMetrics.verticalInfoInset, right: BiliMetrics.verticalColumnRoom),
        child: title,
      ),
      // Kept for the search row; 清屏's play and time sit in it.
      SizedBox(
        height: BiliMetrics.verticalSearchRoom,
        child: switch (room) {
          final room? => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: VerticalCleanTheme.rowAboveBar - BiliMetrics.chromeButton / 2,
                height: BiliMetrics.chromeButton,
                child: room,
              ),
            ],
          ),
          null => null,
        },
      ),
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
              child: bar,
            ),
          ),
        ),
      ),
      SizedBox(height: BiliMetrics.chromeButton, child: row),
    ],
  );
}

/// 发弹幕 with 弹, then 详情页 and the last button.
class _BottomRow extends StatelessWidget {
  const _BottomRow({required this.field, required this.detail, required this.last});

  final Widget field;
  final Widget detail;
  final Widget last;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(width: BiliMetrics.verticalInfoInset),
      Expanded(child: field),
      const SizedBox(width: BiliMetrics.verticalDetailGap),
      detail,
      const SizedBox(width: BiliMetrics.verticalLandscapeGap),
      last,
      const SizedBox(width: BiliMetrics.landscapeEdge),
    ],
  );
}

/// 09's corners for a wide video; for an upright one the APK's `bili_story_ctrl_normal` at its own 24 pt (16), and
/// `bili_story_ctrl_clean` while 清屏 is on (180).
class _ScreenModeGlyph extends StatelessWidget {
  const _ScreenModeGlyph({required this.upright, this.clean = false, this.imageKey});

  final bool upright;
  final bool clean;
  final Key? imageKey;

  @override
  Widget build(BuildContext context) => upright
      ? Image.asset(
          clean ? VerticalCleanTheme.screenModeCleanAsset : VerticalActionTheme.screenModeAsset,
          key: imageKey,
          width: VerticalActionTheme.screenModeGlyph,
          height: VerticalActionTheme.screenModeGlyph,
          gaplessPlayback: true,
        )
      : const CustomPaint(size: Size.square(BiliMetrics.fullScreenGlyph), painter: FullScreenPainter());
}

/// The dark capsule of 09's 发弹幕 field reading [text], with the 弹 toggle at its right end. [keyed] off for a
/// neighbour's still copy.
class _Field extends StatelessWidget {
  const _Field({
    required this.text,
    required this.danmakuOn,
    required this.onTap,
    required this.onToggle,
    this.onSend,
    this.keyed = true,
  });

  final String text;
  final bool danmakuOn;

  /// Opens the send bar; null when it can't.
  final VoidCallback? onSend;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final bool keyed;

  static const _style = TextStyle(
    color: VerticalActionTheme.fieldInk,
    fontSize: VerticalActionTheme.fieldText,
    height: 1,
  );

  @override
  Widget build(BuildContext context) => Container(
    height: BiliMetrics.verticalFieldHeight,
    decoration: const ShapeDecoration(color: BiliColors.chromeDarkField, shape: StadiumBorder()),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            key: keyed ? const ValueKey('vertical-danmaku-field') : null,
            button: onSend != null,
            label: text,
            onTap: onSend,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
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
                      style: _style,
                      strutStyle: fullScreenStrut(_style),
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
          key: keyed ? const ValueKey('vertical-danmaku') : null,
          label: danmakuOn ? '关闭弹幕' : '开启弹幕',
          square: false,
          onTap: onToggle,
          child: SizedBox(
            width: BiliMetrics.verticalToggleWidth,
            height: BiliMetrics.verticalFieldHeight,
            child: Center(child: DanmakuGlyph(on: danmakuOn)),
          ),
        ),
      ],
    ),
  );
}

/// 清屏's play or pause at the bottom left with the time after it (180, 186); a tap plays or pauses.
class _CleanPlay extends StatelessWidget {
  const _CleanPlay({required this.ui, required this.touch});

  final PlayerUi ui;
  final VoidCallback Function(VoidCallback) touch;

  static TextStyle get _timeStyle => fullScreenText.merge(
    const TextStyle(
      color: BiliColors.onVideo,
      fontSize: VerticalCleanTheme.timeText,
      fontWeight: FontWeight.w500,
      height: 1,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = ui.session;
    final playing = session.readout.wantsPlay && !session.ended;
    return Stack(
      children: [
        Positioned(
          left: VerticalCleanTheme.playLeft + VerticalCleanTheme.playWidth / 2 - BiliMetrics.chromeButton / 2,
          top: 0,
          bottom: 0,
          width: BiliMetrics.chromeButton,
          child: ChromeTap(
            key: const ValueKey('vertical-clean-play'),
            label: playing ? '暂停' : '播放',
            onTap: touch(session.togglePlay),
            child: CustomPaint(
              size: const Size(VerticalCleanTheme.playWidth, VerticalCleanTheme.playHeight),
              painter: _CleanPlayPainter(playing: playing),
            ),
          ),
        ),
        Positioned(
          left: VerticalCleanTheme.timeLeft,
          top: VerticalCleanTheme.timeDrop * 2,
          bottom: 0,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: ListenableBuilder(
                listenable: FullScreenSeekBar.repaintOf(ui),
                builder: (context, _) => Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: TimeFormat.clock(session.position)),
                      TextSpan(
                        text: ' / ${TimeFormat.clock(session.duration.value)}',
                        style: const TextStyle(color: VerticalCleanTheme.timeTotal),
                      ),
                    ],
                  ),
                  key: const ValueKey('vertical-clean-time'),
                  maxLines: 1,
                  softWrap: false,
                  style: _timeStyle,
                  strutStyle: BiliFonts.strut(_timeStyle),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 180's rounded ▶, or 186's two round-ended bars, filling the size.
class _CleanPlayPainter extends CustomPainter {
  const _CleanPlayPainter({required this.playing});

  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = BiliColors.onVideo;
    if (playing) {
      const bar = VerticalCleanTheme.pauseBar, gap = VerticalCleanTheme.pauseGap;
      final left = (size.width - bar * 2 - gap) / 2;
      for (final x in [left, left + bar + gap]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, bar, size.height), const Radius.circular(bar / 2)),
          paint,
        );
      }
      return;
    }
    // A triangle inset by the corner, filled and stroked twice the corner wide, fills the size with round corners.
    const r = VerticalCleanTheme.playCorner;
    final path = Path()
      ..moveTo(r, r)
      ..lineTo(size.width - r, size.height / 2)
      ..lineTo(r, size.height - r)
      ..close();
    canvas
      ..drawPath(path, paint)
      ..drawPath(
        path,
        Paint()
          ..color = BiliColors.onVideo
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 2
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_CleanPlayPainter oldDelegate) => oldDelegate.playing != playing;
}

/// 竖屏's page under the finger: its controls move with it, at [VerticalCleanTheme.movingOpacity] until it lands.
class _Moving extends StatelessWidget {
  const _Moving({required this.drag, required this.child});

  final StoryDrag? drag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final drag = this.drag;
    if (drag == null) return child;
    return ListenableBuilder(
      listenable: drag,
      child: child,
      builder: (context, child) {
        final moving = drag.moving;
        return Transform.translate(
          offset: Offset(0, moving ? drag.offset : 0),
          child: Opacity(opacity: moving ? VerticalCleanTheme.movingOpacity : 1, child: child),
        );
      },
    );
  }
}

/// The uploader's avatar, the name (pink for 大会员) with 粉丝 under it, and + 关注 beside it, each once known.
class _Uploader extends StatelessWidget {
  const _Uploader({required this.detail, required this.details, required this.touch, this.onOpen});

  final VideoDetail detail;
  final PageDetails? details;
  final VoidCallback Function(VoidCallback) touch;
  final VoidCallback? onOpen;

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

  Widget _row(UploaderCard? uploader, VideoActions? actions) => _UploaderRow(
    prefix: 'vertical',
    face: detail.owner.face,
    name: detail.owner.name,
    vip: uploader?.isVip ?? false,
    fans: uploader?.fans,
    following: actions?.following,
    onFollow: actions == null ? null : touch(actions.tapFollow),
    onOpen: onOpen,
  );
}

/// The avatar, the name with [fans] under it once known, and the follow pill once [following] is. The avatar, name
/// and 粉丝 are one target, [onOpen], as the official row is.
class _UploaderRow extends StatelessWidget {
  const _UploaderRow({
    required this.prefix,
    required this.face,
    required this.name,
    this.vip = false,
    this.fans,
    this.following,
    this.onFollow,
    this.onOpen,
  });

  /// Before each key: the live page's, or a neighbour's still copy.
  final String prefix;
  final String face;
  final String name;
  final bool vip;
  final int? fans;
  final bool? following;

  /// Null leaves the pill taking no touches, as a swiped-to video's is until its page's actions are in.
  final VoidCallback? onFollow;
  final VoidCallback? onOpen;

  static const _fansStyle = TextStyle(
    color: VerticalActionTheme.fans,
    fontSize: VerticalActionTheme.fansText,
    height: 1,
  );

  static TextStyle _nameStyle(bool vip) => fullScreenText.merge(
    TextStyle(
      color: vip ? BiliColors.pink : BiliColors.onVideo,
      fontSize: BiliMetrics.verticalNameText,
      fontWeight: FontWeight.w500,
      height: 1,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final fans = this.fans;
    final following = this.following;
    return Row(
      key: ValueKey('$prefix-uploader'),
      children: [
        const SizedBox(width: BiliMetrics.verticalAvatarInset),
        Flexible(
          child: Semantics(
            button: onOpen != null,
            label: name,
            onTap: onOpen,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    key: ValueKey('$prefix-avatar'),
                    width: BiliMetrics.verticalAvatar,
                    height: BiliMetrics.verticalAvatar,
                    foregroundDecoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: BiliColors.onVideo, width: BiliMetrics.verticalAvatarRing),
                    ),
                    child: ClipOval(
                      child: RemoteImage.avatar(face, size: const Size.square(BiliMetrics.verticalAvatar)),
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
                                style: _nameStyle(vip),
                                child: Text(
                                  name,
                                  key: ValueKey('$prefix-name'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  strutStyle: BiliFonts.strut(_nameStyle(vip)),
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
                              child: fans == null
                                  ? null
                                  : Transform.translate(
                                      offset: Offset(0, VerticalActionTheme.fansDrop),
                                      child: Text(
                                        '${CountFormat.short(fans)}粉丝',
                                        key: ValueKey('$prefix-fans'),
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
                ],
              ),
            ),
          ),
        ),
        _FadeIn(
          child: following == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: VerticalActionTheme.followGap),
                  child: IgnorePointer(
                    ignoring: onFollow == null,
                    child: _FollowPill(
                      key: ValueKey('$prefix-follow'),
                      following: following,
                      onTap: onFollow ?? _nothing,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: BiliMetrics.verticalColumnRoom),
      ],
    );
  }
}

/// Takes no touch landing in [PlayerGestureLayer]'s back-swipe strip, so it reaches the edge swipe under the chrome.
class _EdgeGap extends SingleChildRenderObjectWidget {
  const _EdgeGap({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEdgeGap(PlayerGestureLayer.backEdge(MediaQuery.paddingOf(context)));

  @override
  void updateRenderObject(BuildContext context, _RenderEdgeGap renderObject) =>
      renderObject.edge = PlayerGestureLayer.backEdge(MediaQuery.paddingOf(context));
}

class _RenderEdgeGap extends RenderProxyBox {
  _RenderEdgeGap(this.edge);

  /// From the screen's left, as the gesture layer measures it.
  double edge;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      localToGlobal(position).dx >= edge && super.hitTest(result, position: position);
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
  const _FollowPill({super.key, required this.following, required this.onTap});

  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ChromeTap(
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

/// The viewers mark and N人正在看, from the page's poll; nothing until it answers. Smaller in 清屏 (180).
class _Online extends StatelessWidget {
  const _Online({required this.online, required this.clean});

  final ValueListenable<String?> online;
  final bool clean;

  static TextStyle _style(bool clean) => TextStyle(
    color: VerticalActionTheme.online,
    fontSize: clean ? VerticalCleanTheme.onlineText : VerticalActionTheme.onlineText,
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
                  CustomPaint(
                    size: clean
                        ? const Size(VerticalCleanTheme.onlineIconWidth, VerticalCleanTheme.onlineIconHeight)
                        : const Size(VerticalActionTheme.onlineIconWidth, VerticalActionTheme.onlineIconHeight),
                    painter: const _ViewersPainter(),
                  ),
                  SizedBox(width: clean ? VerticalCleanTheme.onlineGap : VerticalActionTheme.onlineGap),
                  Text(
                    '$count人正在看',
                    maxLines: 1,
                    style: _style(clean),
                    strutStyle: fullScreenStrut(_style(clean)),
                  ),
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

  Widget _items(VideoActions actions, int replies) => _columnItems(
    prefix: 'vertical',
    likes: actions.likeCount,
    replies: replies,
    coins: actions.coinCount,
    favourites: actions.favCount,
    shares: actions.shareCount,
    liked: actions.liked,
    coined: actions.coins > 0,
    favourited: actions.favorited,
    onLike: touch(actions.toggleLike),
    onComment: touch(() => ui.onComments?.call()),
    onCoin: touch(() => actions.ask(ActionPrompt.coin)),
    onFavourite: touch(() => actions.ask(ActionPrompt.favourites)),
    onShare: touch(() => actions.ask(ActionPrompt.share)),
  );
}

Widget _columnItems({
  required String prefix,
  required int likes,
  required int replies,
  required int coins,
  required int favourites,
  required int shares,
  bool liked = false,
  bool coined = false,
  bool favourited = false,
  VoidCallback onLike = _nothing,
  VoidCallback onComment = _nothing,
  VoidCallback onCoin = _nothing,
  VoidCallback onFavourite = _nothing,
  VoidCallback onShare = _nothing,
}) => Column(
  key: ValueKey('$prefix-actions'),
  mainAxisSize: MainAxisSize.min,
  spacing: VerticalActionTheme.itemSpacing,
  children: [
    _ColumnItem(
      key: ValueKey('$prefix-like'),
      label: '点赞',
      glyph: ActionGlyph.like,
      size: VerticalActionTheme.likeIcon,
      count: likes,
      active: liked,
      onTap: onLike,
    ),
    _ColumnItem(
      key: ValueKey('$prefix-comment'),
      label: '评论',
      glyph: ActionGlyph.comment,
      size: VerticalActionTheme.commentIcon,
      count: replies,
      active: false,
      onTap: onComment,
    ),
    _ColumnItem(
      key: ValueKey('$prefix-coin'),
      label: '投币',
      glyph: ActionGlyph.coin,
      size: VerticalActionTheme.coinIcon,
      count: coins,
      active: coined,
      onTap: onCoin,
    ),
    _ColumnItem(
      key: ValueKey('$prefix-favourite'),
      label: '收藏',
      glyph: ActionGlyph.favourite,
      size: VerticalActionTheme.favouriteIcon,
      count: favourites,
      active: favourited,
      onTap: onFavourite,
    ),
    _ColumnItem(
      key: ValueKey('$prefix-share'),
      label: '分享',
      glyph: ActionGlyph.share,
      size: VerticalActionTheme.shareIcon,
      count: shares,
      active: false,
      onTap: onShare,
    ),
  ],
);

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
