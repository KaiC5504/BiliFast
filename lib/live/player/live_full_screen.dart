import 'dart:async';

import 'package:bili_core/logic.dart' show CountFormat;
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../player_ui/chrome_state.dart';
import '../../player_ui/landscape_chrome.dart' show LockPainter, fullScreenStrut, fullScreenText;
import '../../player_ui/portrait_controls.dart' show BackGlyph, ChromeTap, MoreDots;
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../danmaku/live_danmaku_layer.dart';
import '../live_badges.dart';
import '../room/live_overlays.dart';
import '../room/live_room_model.dart';
import 'live_player_controller.dart';
import 'live_player_view.dart';

/// Where the picture sits in full screen: the whole [screen], or with a panel on the right ([side]) 16:9 in the room
/// left of it, centred down the screen (210, 222, 232).
Rect livePictureRect(Size screen, {required bool side}) {
  if (!side) return Offset.zero & screen;
  final room = Rect.fromLTRB(
    LivePlayerTheme.sidePictureLeft,
    0,
    screen.width - LivePlayerTheme.sideWidth - LivePlayerTheme.sidePictureGap,
    screen.height,
  );
  var width = room.width;
  var height = width * 9 / 16;
  if (height > room.height) {
    height = room.height;
    width = height * 16 / 9;
  }
  return Rect.fromCenter(center: room.center, width: width, height: height);
}

/// 209: the picture over the whole screen, the danmaku over it, and the controls. A tap shows or hides them; they
/// hide 5 s after the last touch while it plays. Locked (🔓), only the lock shows. A double tap is 点赞.
class LiveFullScreen extends StatefulWidget {
  const LiveFullScreen({
    super.key,
    required this.controller,
    required this.room,
    required this.overlays,
    required this.onBack,
  });

  final LivePlayerController controller;
  final LiveRoomModel room;
  final LiveOverlays overlays;
  final VoidCallback onBack;

  @override
  State<LiveFullScreen> createState() => _LiveFullScreenState();
}

class _LiveFullScreenState extends State<LiveFullScreen> {
  final _chrome = ChromeState(hideDelay: LivePlayerTheme.chromeHide);

  @override
  void initState() {
    super.initState();
    _listen();
    _follow();
  }

  @override
  void didUpdateWidget(LiveFullScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller) && identical(oldWidget.overlays, widget.overlays)) return;
    oldWidget.controller.removeListener(_follow);
    oldWidget.overlays.removeListener(_overlayChanged);
    _listen();
    _follow();
  }

  void _listen() {
    widget.controller.addListener(_follow);
    widget.overlays.addListener(_overlayChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_follow);
    widget.overlays.removeListener(_overlayChanged);
    _chrome.dispose();
    super.dispose();
  }

  /// Shown controls hide by themselves only while the stream plays and no layer is up.
  void _follow() {
    _chrome.autoHide = widget.controller.playing && widget.overlays.value == LiveOverlay.none;
  }

  /// A layer coming up takes the controls with it; they stay hidden after it, as the picture comes back alone.
  void _overlayChanged() {
    if (widget.overlays.value != LiveOverlay.none) _chrome.hide();
    _follow();
  }

  bool get _side => switch (widget.overlays.value) {
    LiveOverlay.more || LiveOverlay.quality || LiveOverlay.rank => true,
    _ => false,
  };

  VoidCallback _touch(VoidCallback action) => () {
    _chrome.show();
    action();
  };

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        return ListenableBuilder(
          listenable: Listenable.merge([widget.overlays, _chrome]),
          builder: (context, _) {
            final picture = livePictureRect(screen, side: _side);
            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: BiliColors.videoBackground),
                AnimatedPositioned.fromRect(
                  key: const ValueKey('live-picture'),
                  rect: picture,
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : LivePlayerTheme.sideSlide,
                  curve: Curves.easeOutCubic,
                  child: LivePicture(controller: controller, room: widget.room, danmaku: false),
                ),
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => IgnorePointer(
                    child: LiveDanmakuLayer(room: widget.room, on: controller.danmakuOn),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('live-full-gestures'),
                    behavior: HitTestBehavior.translucent,
                    onTap: _chrome.toggle,
                    onDoubleTap: () => likeRoom(context, widget.room),
                  ),
                ),
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([controller, widget.room]),
                    builder: (context, _) => _controls(context),
                  ),
                ),
                Positioned.fill(child: _Notes(notices: controller.notices)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _controls(BuildContext context) {
    final shown = _chrome.visible && widget.overlays.value == LiveOverlay.none;
    final locked = widget.controller.locked;
    final insets = MediaQuery.paddingOf(context);
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : LivePlayerTheme.chromeFade;
    Widget fade(bool visible, Widget child) => IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(opacity: visible ? 1 : 0, duration: duration, curve: Curves.easeOut, child: child),
    );
    return DefaultTextStyle(
      style: fullScreenText,
      child: Stack(
        fit: StackFit.expand,
        children: [
          fade(shown && !locked, _unlocked(context, insets)),
          fade(
            shown,
            Stack(
              children: [
                Positioned(
                  left: insets.left + LivePlayerTheme.lockCentre - LivePlayerTheme.lockBox / 2,
                  top: 0,
                  bottom: 0,
                  child: Center(child: _lock()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lock() {
    final controller = widget.controller;
    final locked = controller.locked;
    return ChromeTap(
      key: const ValueKey('live-lock'),
      label: locked ? '解锁' : '锁定',
      square: false,
      onTap: _touch(() => controller.setLocked(!locked)),
      child: Container(
        width: LivePlayerTheme.lockBox,
        height: LivePlayerTheme.lockBox,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: LivePlayerTheme.lockFill,
          borderRadius: BorderRadius.circular(LivePlayerTheme.lockRadius),
        ),
        child: CustomPaint(
          size: const Size(BiliMetrics.chromeLockWidth, BiliMetrics.chromeLockHeight),
          painter: LockPainter(locked: locked),
        ),
      ),
    );
  }

  Widget _unlocked(BuildContext context, EdgeInsets insets) {
    final controller = widget.controller;
    final room = widget.room;
    final overlays = widget.overlays;
    const target = BiliMetrics.chromeButton;
    const half = target / 2;
    void toast() => showToast(context, '暂未开放');
    return Stack(
      children: [
        Positioned(
          left: insets.left + LivePlayerTheme.backCentre - half,
          top: LivePlayerTheme.topRowCentre - half,
          child: ChromeTap(
            key: const ValueKey('live-back'),
            label: '返回',
            onTap: widget.onBack,
            child: const BackGlyph(width: LivePlayerTheme.backWidth, height: LivePlayerTheme.backHeight),
          ),
        ),
        Positioned(
          left: insets.left + LivePlayerTheme.anchorLeft,
          top: LivePlayerTheme.topRowCentre - LivePlayerTheme.anchorHeight / 2,
          child: _AnchorCapsule(room: room, touch: _touch),
        ),
        Positioned(
          right: insets.right + LivePlayerTheme.countRight,
          top: LivePlayerTheme.topRowCentre - LivePlayerTheme.countHeight / 2,
          child: _RankFaces(room: room, onTap: _touch(() => overlays.open(LiveOverlay.rank))),
        ),
        Positioned(
          right: insets.right + LivePlayerTheme.shareCentre - half,
          top: LivePlayerTheme.topRowCentre - half,
          child: ChromeTap(
            key: const ValueKey('live-share'),
            label: '分享',
            onTap: _touch(() => unawaited(controller.share(context))),
            child: Image.asset(
              LivePlayerAssets.share,
              width: LivePlayerTheme.shareIcon,
              height: LivePlayerTheme.shareIcon,
            ),
          ),
        ),
        Positioned(
          right: insets.right + LivePlayerTheme.moreCentre - half,
          top: LivePlayerTheme.topRowCentre - half,
          child: ChromeTap(
            key: const ValueKey('live-more'),
            label: '更多',
            onTap: _touch(() => overlays.open(LiveOverlay.more)),
            child: const MoreDots(dot: LivePlayerTheme.moreDot, gap: LivePlayerTheme.moreDotGap),
          ),
        ),
        Positioned(
          left: insets.left + LivePlayerTheme.chipLeft,
          top: LivePlayerTheme.chipCentre - LivePlayerTheme.chipHeight / 2,
          child: Row(
            spacing: LivePlayerTheme.chipGap,
            children: [
              for (final (index, chip) in (room.info?.rankChips ?? const <String>[]).indexed)
                _Chip(key: ValueKey('live-rank-chip-$index'), text: chip, onTap: _touch(toast)),
            ],
          ),
        ),
        Positioned(
          right: insets.right,
          top: LivePlayerTheme.chipCentre - LivePlayerTheme.chipHeight / 2,
          child: _Chip(key: const ValueKey('live-more-live'), text: '更多直播', chevron: true, onTap: _touch(toast)),
        ),
        Positioned(
          left: insets.left,
          bottom: LivePlayerTheme.bottomRowCentre - half,
          child: _BottomRow(controller: controller, overlays: overlays, touch: _touch, toast: toast),
        ),
        Positioned(
          right: insets.right,
          bottom: LivePlayerTheme.giftRowCentre - LivePlayerTheme.giftDisc / 2,
          child: _GiftAndPlus(room: room, onTap: _touch(toast)),
        ),
      ],
    );
  }
}

TextStyle _style(double size, {FontWeight weight = FontWeight.w400}) =>
    fullScreenText.merge(TextStyle(fontSize: size, fontWeight: weight, height: 1));

Widget _label(String text, double size, {Key? key, FontWeight weight = FontWeight.w400}) {
  final style = _style(size, weight: weight);
  return Text(
    text,
    key: key,
    style: style,
    strutStyle: fullScreenStrut(style),
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
  );
}

/// The anchor's face, name and 点赞, with 关注 until the room is followed.
class _AnchorCapsule extends StatelessWidget {
  const _AnchorCapsule({required this.room, required this.touch});

  final LiveRoomModel room;
  final VoidCallback Function(VoidCallback action) touch;

  @override
  Widget build(BuildContext context) {
    final info = room.info;
    final entry = room.entry;
    final name = (info?.anchorName ?? '').isEmpty ? entry.anchorName : info!.anchorName;
    final face = (info?.anchorFace ?? '').isEmpty ? entry.anchorFace : info!.anchorFace;
    return Container(
      key: const ValueKey('live-anchor'),
      height: LivePlayerTheme.anchorHeight,
      padding: EdgeInsets.only(
        left: LivePlayerTheme.anchorFaceInset,
        right: room.following ? LivePlayerTheme.anchorFollowedEnd : LivePlayerTheme.followEnd,
      ),
      decoration: BoxDecoration(
        color: LivePlayerTheme.capsuleFill,
        borderRadius: BorderRadius.circular(LivePlayerTheme.anchorHeight / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiveFace(url: face, size: LivePlayerTheme.anchorFace, frame: info?.anchorFrame ?? ''),
          const SizedBox(width: LivePlayerTheme.anchorTextGap),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: LivePlayerTheme.anchorTextMax),
            child: Stack(
              children: [
                _line(name, LivePlayerTheme.anchorName, LivePlayerTheme.anchorNameCentre, 'live-anchor-name'),
                _line(
                  '${CountFormat.short(room.likeCount)}点赞',
                  LivePlayerTheme.anchorLikes,
                  LivePlayerTheme.anchorLikesCentre,
                  'live-anchor-likes',
                ),
              ],
            ),
          ),
          if (!room.following) ...[
            const SizedBox(width: LivePlayerTheme.followGap),
            ChromeTap(
              key: const ValueKey('live-follow'),
              label: '关注',
              square: false,
              onTap: touch(() => unawaited(followRoom(context, room))),
              child: Container(
                width: LivePlayerTheme.followWidth,
                height: LivePlayerTheme.followHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BiliColors.pink,
                  borderRadius: BorderRadius.circular(LivePlayerTheme.followHeight / 2),
                ),
                child: _label('关注', LivePlayerTheme.followText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A line of the capsule, its em box's middle [centre] down it: the room as wide as the line, as tall as the capsule.
Widget _line(String text, double size, double centre, String key) => Padding(
  padding: EdgeInsets.only(top: centre - size / 2, bottom: LivePlayerTheme.anchorHeight - centre - size / 2),
  child: SizedBox(
    height: size,
    child: OverflowBox(
      fit: OverflowBoxFit.deferToChild,
      maxHeight: size * 2,
      child: _label(text, size, key: ValueKey(key)),
    ),
  ),
);

/// 关注 in the header, through the login page when logged out.
Future<void> followRoom(BuildContext context, LiveRoomModel room) async {
  final services = AppScope.of(context);
  if (!room.loggedIn()) {
    unawaited(services.loginGate.request(context));
    return;
  }
  try {
    await room.setFollowing(true);
  } catch (_) {
    if (context.mounted) showToast(context, '关注失败，请稍后重试');
  }
}

/// The 在线榜's first three faces and the count after them, which open 高能榜.
class _RankFaces extends StatelessWidget {
  const _RankFaces({required this.room, required this.onTap});

  final LiveRoomModel room;
  final VoidCallback onTap;

  static String count(int n) => n < 10000 ? '$n' : '${n ~/ 10000}万+';

  @override
  Widget build(BuildContext context) {
    final faces = room.topFaces.take(3).toList();
    const size = LivePlayerTheme.rankFace;
    const step = LivePlayerTheme.rankFaceStep;
    final facesWidth = faces.isEmpty ? 0.0 : size + step * (faces.length - 1);
    final capsuleStart = faces.isEmpty ? 0.0 : facesWidth - size / 2;
    return ChromeTap(
      key: const ValueKey('live-rank'),
      label: '高能榜',
      square: false,
      onTap: onTap,
      child: SizedBox(
        height: LivePlayerTheme.countHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsets.only(left: capsuleStart),
              child: Container(
                height: LivePlayerTheme.countHeight,
                padding: EdgeInsets.only(
                  left: faces.isEmpty ? LivePlayerTheme.countTrail : size / 2 + LivePlayerTheme.countLead,
                  right: LivePlayerTheme.countTrail,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: LivePlayerTheme.capsuleFill,
                  borderRadius: BorderRadius.circular(LivePlayerTheme.countHeight / 2),
                ),
                child: _label(count(room.onlineCount), LivePlayerTheme.countText, key: const ValueKey('live-count')),
              ),
            ),
            // The first face over the second, the second over the third.
            for (final (index, face) in faces.indexed.toList().reversed)
              Positioned(
                left: step * index,
                top: (LivePlayerTheme.countHeight - size) / 2,
                child: Container(
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(LivePlayerTheme.rankFaceRing),
                  decoration: BoxDecoration(color: LivePlayerTheme.rankFaceRings[index], shape: BoxShape.circle),
                  child: LiveFace(url: face, size: size - LivePlayerTheme.rankFaceRing * 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A rank chip under the anchor, or 更多直播 › on the right.
class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.text, required this.onTap, this.chevron = false});

  final String text;
  final VoidCallback onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) => ChromeTap(
    label: text,
    square: false,
    onTap: onTap,
    child: Container(
      height: LivePlayerTheme.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: LivePlayerTheme.chipInset),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: LivePlayerTheme.capsuleFill,
        borderRadius: BorderRadius.circular(LivePlayerTheme.chipHeight / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: LivePlayerTheme.moreLiveChevronGap,
        children: [
          _label(text, LivePlayerTheme.chipText),
          if (chevron)
            const RotatedBox(
              quarterTurns: 2,
              child: BackGlyph(
                width: LivePlayerTheme.moreLiveChevronWidth,
                height: LivePlayerTheme.moreLiveChevronHeight,
                shadow: false,
              ),
            ),
        ],
      ),
    ),
  );
}

/// ⏸ ⟳ 弹, the quality's name and 209's last icon (the APK's watch_movies, which toasts).
class _BottomRow extends StatelessWidget {
  const _BottomRow({required this.controller, required this.overlays, required this.touch, required this.toast});

  final LivePlayerController controller;
  final LiveOverlays overlays;
  final VoidCallback Function(VoidCallback action) touch;
  final VoidCallback toast;

  @override
  Widget build(BuildContext context) {
    const half = BiliMetrics.chromeButton / 2;
    Widget icon(String asset) =>
        Image.asset(asset, width: LivePlayerTheme.bottomIcon, height: LivePlayerTheme.bottomIcon);
    Widget at(double centre, Widget child) => Positioned(left: centre - half, top: 0, child: child);
    final quality = controller.quality;
    return SizedBox(
      width: LivePlayerTheme.watchCentre + half,
      height: BiliMetrics.chromeButton,
      child: Stack(
        children: [
          at(
            LivePlayerTheme.playCentre,
            ChromeTap(
              key: const ValueKey('live-play'),
              label: controller.playing ? '暂停' : '播放',
              onTap: touch(() => unawaited(controller.togglePlay())),
              child: icon(controller.playing ? LivePlayerAssets.pause : LivePlayerAssets.play),
            ),
          ),
          at(
            LivePlayerTheme.refreshCentre,
            ChromeTap(
              key: const ValueKey('live-refresh'),
              label: '刷新',
              onTap: touch(() => unawaited(controller.refreshStream())),
              child: icon(LivePlayerAssets.refresh),
            ),
          ),
          at(
            LivePlayerTheme.danmakuCentre,
            ChromeTap(
              key: const ValueKey('live-danmaku'),
              label: controller.danmakuOn ? '关闭弹幕' : '开启弹幕',
              onTap: touch(() => controller.setDanmakuOn(!controller.danmakuOn)),
              child: icon(controller.danmakuOn ? LivePlayerAssets.danmakuOn : LivePlayerAssets.danmakuOff),
            ),
          ),
          Positioned(
            left: LivePlayerTheme.qualityLeft,
            top: 0,
            bottom: 0,
            child: ChromeTap(
              key: const ValueKey('live-quality'),
              label: '画质',
              square: false,
              onTap: touch(() => overlays.open(LiveOverlay.quality)),
              child: Center(child: _label(quality?.name.split(' ').first ?? '画质', LivePlayerTheme.qualityText)),
            ),
          ),
          at(
            LivePlayerTheme.watchCentre,
            ChromeTap(
              key: const ValueKey('live-watch'),
              label: '观影模式',
              onTap: touch(toast),
              child: icon(LivePlayerAssets.watchMovies),
            ),
          ),
        ],
      ),
    );
  }
}

/// The gift and the anchor's pink + at the bottom right; both toast 暂未开放.
class _GiftAndPlus extends StatelessWidget {
  const _GiftAndPlus({required this.room, required this.onTap});

  final LiveRoomModel room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = room.info;
    final face = (info?.anchorFace ?? '').isEmpty ? room.entry.anchorFace : info!.anchorFace;
    const gap = LivePlayerTheme.giftCentre - LivePlayerTheme.giftDisc / 2 - LivePlayerTheme.plusWidth;
    return SizedBox(
      height: LivePlayerTheme.giftDisc,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChromeTap(
            key: const ValueKey('live-gift'),
            label: '礼物',
            square: false,
            onTap: onTap,
            child: Container(
              width: LivePlayerTheme.giftDisc,
              height: LivePlayerTheme.giftDisc,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: LivePlayerTheme.giftFill, shape: BoxShape.circle),
              child: Image.asset(
                LivePlayerAssets.gift,
                width: LivePlayerTheme.giftIcon,
                height: LivePlayerTheme.giftIcon,
              ),
            ),
          ),
          const SizedBox(width: gap),
          ChromeTap(
            key: const ValueKey('live-plus'),
            label: '投喂',
            square: false,
            onTap: onTap,
            child: Container(
              width: LivePlayerTheme.plusWidth,
              height: LivePlayerTheme.plusHeight,
              padding: const EdgeInsets.only(left: (LivePlayerTheme.plusHeight - LivePlayerTheme.plusFace) / 2),
              decoration: BoxDecoration(
                color: BiliColors.pink,
                borderRadius: BorderRadius.circular(LivePlayerTheme.plusHeight / 2),
              ),
              child: Row(
                children: [
                  LiveFace(url: face, size: LivePlayerTheme.plusFace),
                  const Expanded(
                    child: Center(
                      child: CustomPaint(size: Size.square(LivePlayerTheme.plusArm * 2), painter: _PlusPainter()),
                    ),
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

class _PlusPainter extends CustomPainter {
  const _PlusPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BiliColors.onVideo
      ..strokeWidth = LivePlayerTheme.plusStroke
      ..strokeCap = StrokeCap.round;
    final centre = size.center(Offset.zero);
    canvas
      ..drawLine(centre.translate(-size.width / 2, 0), centre.translate(size.width / 2, 0), paint)
      ..drawLine(centre.translate(0, -size.height / 2), centre.translate(0, size.height / 2), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter oldDelegate) => false;
}

/// 210's notes at the bottom left, the newest lowest.
class _Notes extends StatelessWidget {
  const _Notes({required this.notices});

  final LivePlayerNotices notices;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: notices,
        builder: (context, _) => Stack(
          children: [
            Positioned(
              left: insets.left + LivePlayerTheme.noteLeft,
              bottom: LivePlayerTheme.noteBottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: LivePlayerTheme.noteGap,
                children: [
                  for (final notice in notices.shown)
                    Container(
                      key: ValueKey('live-note-${notice.id}'),
                      height: LivePlayerTheme.noteHeight,
                      padding: const EdgeInsets.symmetric(horizontal: LivePlayerTheme.noteInset),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: LivePlayerTheme.noteFill,
                        borderRadius: BorderRadius.circular(LivePlayerTheme.noteRadius),
                      ),
                      child: _label(notice.text, LivePlayerTheme.noteText),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
