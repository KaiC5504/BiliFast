import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../live_badges.dart';
import 'room_glyphs.dart';

/// 221's share targets, in its order; the row runs on past QQ空间 off the screen, which 221 shows no further.
enum RoomShareTarget {
  facebook('Facebook'),
  x('X'),
  whatsApp('WhatsApp'),
  weChat('微信'),
  moments('朋友圈'),
  qq('QQ'),
  qzone('QQ空间');

  const RoomShareTarget(this.label);

  final String label;
}

/// 221's second row, in its order (the plan's for the part off the screen).
enum RoomMoreItem {
  pictureInPicture('小窗播放'),
  playSettings('播放设置'),
  boost('助TA必火'),
  danmakuSettings('弹幕设置'),
  quality('画质'),
  spending('消费管理'),
  effects('隐藏特效'),
  cast('投屏'),
  report('举报'),
  feedback('反馈'),
  audioOnly('仅播声音'),
  colourVision('色觉优化'),
  desktop('添至桌面');

  const RoomMoreItem(this.label);

  final String label;
}

/// ⋯'s sheet (221): 分享's targets, a rule, then the room's settings, each row scrolling sideways. It has no dim; a tap
/// above it closes it.
class RoomMoreSheet extends StatelessWidget {
  const RoomMoreSheet({super.key, required this.onShare, required this.onItem, required this.onClose});

  final ValueChanged<RoomShareTarget> onShare;
  final ValueChanged<RoomMoreItem> onItem;
  final VoidCallback onClose;

  static Widget _shareIcon(RoomShareTarget target) {
    final asset = switch (target) {
      RoomShareTarget.weChat => 'assets/images/home/hot_share_wechat.png',
      RoomShareTarget.moments => 'assets/images/home/hot_share_moments.png',
      RoomShareTarget.qq => 'assets/images/home/hot_share_qq.png',
      RoomShareTarget.qzone => 'assets/images/live/room_share_qzone.png',
      RoomShareTarget.facebook || RoomShareTarget.x || RoomShareTarget.whatsApp => null,
    };
    if (asset != null) {
      return Image.asset(
        asset,
        width: LiveRoomTheme.sheetCircle,
        height: LiveRoomTheme.sheetCircle,
        excludeFromSemantics: true,
      );
    }
    final brand = switch (target) {
      RoomShareTarget.facebook => RoomBrand.facebook,
      RoomShareTarget.x => RoomBrand.x,
      _ => RoomBrand.whatsApp,
    };
    return SizedBox.square(
      dimension: LiveRoomTheme.sheetCircle,
      child: CustomPaint(painter: RoomBrandPainter(brand)),
    );
  }

  static Widget _itemIcon(RoomMoreItem item) {
    final asset = switch (item) {
      RoomMoreItem.pictureInPicture => 'room_more_pip',
      RoomMoreItem.playSettings => 'room_more_player',
      RoomMoreItem.danmakuSettings => 'room_more_danmaku',
      RoomMoreItem.quality => 'room_more_quality',
      RoomMoreItem.effects => 'room_more_effects',
      RoomMoreItem.cast => 'room_more_cast',
      RoomMoreItem.report => 'room_more_report',
      RoomMoreItem.feedback => 'room_more_feedback',
      RoomMoreItem.audioOnly => 'room_more_audio',
      RoomMoreItem.desktop => 'room_more_desktop',
      RoomMoreItem.boost || RoomMoreItem.spending || RoomMoreItem.colourVision => null,
    };
    final Widget glyph = switch (item) {
      _ when asset != null => Image.asset(
        'assets/images/live/$asset.png',
        width: LiveRoomTheme.sheetCircle,
        height: LiveRoomTheme.sheetCircle,
        excludeFromSemantics: true,
      ),
      RoomMoreItem.boost => Image.asset(
        'assets/images/live/room_more_boost.png',
        width: LiveRoomTheme.boostIconWidth,
        height: LiveRoomTheme.boostIconHeight,
        excludeFromSemantics: true,
      ),
      RoomMoreItem.spending => const CustomPaint(painter: RoomLineIconPainter.spending()),
      _ => const CustomPaint(painter: RoomLineIconPainter.colour()),
    };
    return Container(
      width: LiveRoomTheme.sheetCircle,
      height: LiveRoomTheme.sheetCircle,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: LiveRoomTheme.sheetMoreFill, shape: BoxShape.circle),
      child: SizedBox.square(
        dimension: LiveRoomTheme.sheetCircle,
        child: Center(child: glyph),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    const height = LiveRoomTheme.sheetHeight - 34;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('live-more-outside'),
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: height + bottom,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: ColoredBox(
              key: const ValueKey('live-more-sheet'),
              color: LiveRoomTheme.sheetFill,
              child: Stack(
                children: [
                  Positioned(
                    left: LiveRoomTheme.sheetTitleLeft,
                    top: LiveRoomTheme.sheetTitleCentre - LiveRoomTheme.sheetLabelLine / 2,
                    height: LiveRoomTheme.sheetLabelLine,
                    child: Text(
                      '分享',
                      maxLines: 1,
                      style: liveStyle(
                        LiveRoomTheme.sheetTitleText,
                        LiveRoomTheme.ink,
                        line: LiveRoomTheme.sheetLabelLine,
                      ),
                    ),
                  ),
                  _row(
                    top: LiveRoomTheme.sheetShareCentre - LiveRoomTheme.sheetCircle / 2,
                    labelBelow: LiveRoomTheme.sheetShareLabel - LiveRoomTheme.sheetShareCentre,
                    children: [
                      for (final target in RoomShareTarget.values)
                        _Slot(
                          key: ValueKey('live-share-${target.name}'),
                          label: target.label,
                          icon: _shareIcon(target),
                          labelBelow: LiveRoomTheme.sheetShareLabel - LiveRoomTheme.sheetShareCentre,
                          onTap: () => onShare(target),
                        ),
                    ],
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: LiveRoomTheme.sheetRuleTop,
                    height: LiveRoomTheme.sheetRule,
                    child: ColoredBox(color: LiveRoomTheme.sheetRuleInk),
                  ),
                  _row(
                    top: LiveRoomTheme.sheetMoreCentre - LiveRoomTheme.sheetCircle / 2,
                    labelBelow: LiveRoomTheme.sheetMoreLabel - LiveRoomTheme.sheetMoreCentre,
                    children: [
                      for (final item in RoomMoreItem.values)
                        _Slot(
                          key: ValueKey('live-more-${item.name}'),
                          label: item.label,
                          icon: _itemIcon(item),
                          labelBelow: LiveRoomTheme.sheetMoreLabel - LiveRoomTheme.sheetMoreCentre,
                          dot: item == RoomMoreItem.boost,
                          onTap: () => onItem(item),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Widget _row({required double top, required double labelBelow, required List<Widget> children}) => Positioned(
    left: 0,
    right: 0,
    top: top,
    height: LiveRoomTheme.sheetCircle / 2 + labelBelow + LiveRoomTheme.sheetLabelLine / 2,
    child: ListView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: LiveRoomTheme.sheetSlotsLeft),
      children: children,
    ),
  );
}

/// A slot: its 44 circle at the top of a 64 wide slot, its name centred [labelBelow] under the circle's middle.
class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.label,
    required this.icon,
    required this.labelBelow,
    required this.onTap,
    this.dot = false,
  });

  final String label;
  final Widget icon;
  final double labelBelow;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const circle = LiveRoomTheme.sheetCircle;
    const line = LiveRoomTheme.sheetLabelLine;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: LiveRoomTheme.sheetSlot,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: (LiveRoomTheme.sheetSlot - circle) / 2,
                top: 0,
                width: circle,
                height: circle,
                child: icon,
              ),
              if (dot)
                const Positioned(
                  left: (LiveRoomTheme.sheetSlot + circle) / 2 - LiveRoomTheme.sheetDot,
                  top: 0,
                  width: LiveRoomTheme.sheetDot,
                  height: LiveRoomTheme.sheetDot,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: LiveRoomTheme.sheetDotInk, shape: BoxShape.circle),
                  ),
                ),
              Positioned(
                left: -LiveRoomTheme.sheetSlotsLeft,
                right: -LiveRoomTheme.sheetSlotsLeft,
                top: circle / 2 + labelBelow - line / 2,
                height: line,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: liveStyle(LiveRoomTheme.sheetLabelText, LiveRoomTheme.sheetLabelInk, line: line),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
