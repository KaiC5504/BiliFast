import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../../shared/theme.dart';
import '../../live_badges.dart';
import '../room_glyphs.dart';

/// 醒目留言's strip under the video (224, 228): a pill per 醒目留言 still showing, newest first, its colour lit for the
/// time it has left. With [selected] set (its card open over the dimmed page), the other pills are dimmed too.
class RoomSuperChatStrip extends StatefulWidget {
  const RoomSuperChatStrip({
    super.key,
    required this.superChats,
    required this.now,
    required this.onOpen,
    this.selected,
  });

  final List<LiveSuperChat> superChats;
  final DateTime Function() now;
  final ValueChanged<int> onOpen;
  final int? selected;

  @override
  State<RoomSuperChatStrip> createState() => _RoomSuperChatStripState();
}

class _RoomSuperChatStripState extends State<RoomSuperChatStrip> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now();
    return ListView.separated(
      key: const ValueKey('live-sc-strip'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: LiveRoomTheme.chatLeft),
      itemCount: widget.superChats.length,
      separatorBuilder: (_, _) => const SizedBox(width: LiveRoomTheme.pillGap),
      itemBuilder: (context, index) {
        final sc = widget.superChats[index];
        return Center(
          child: _Pill(
            superChat: sc,
            left: _left(sc, now),
            dimmed: widget.selected != null && widget.selected != sc.id,
            onTap: () => widget.onOpen(sc.id),
          ),
        );
      },
    );
  }

  static double _left(LiveSuperChat sc, DateTime now) {
    final total = sc.end.difference(sc.start).inMilliseconds;
    if (total <= 0) return 0;
    return (sc.end.difference(now).inMilliseconds / total).clamp(0.0, 1.0);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.superChat, required this.left, required this.dimmed, required this.onTap});

  final LiveSuperChat superChat;

  /// The share of its time still to run, lit from the left.
  final double left;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = liveColor(superChat.backgroundBottom, LiveRoomTheme.superChatFallback);
    const radius = BorderRadius.all(Radius.circular(LiveRoomTheme.stripHeight / 2));
    return Semantics(
      button: true,
      label: '醒目留言 ${superChat.batteries}',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('live-sc-pill-${superChat.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Color.lerp(colour, const Color(0xFF000000), LiveRoomTheme.pillSpent)!),
              ),
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: left,
                  child: ColoredBox(color: colour),
                ),
              ),
              SizedBox(
                height: LiveRoomTheme.stripHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: LiveRoomTheme.pillFaceInset),
                    LiveFace(url: superChat.user.face, size: LiveRoomTheme.pillFace),
                    const SizedBox(width: LiveRoomTheme.pillBatteryGap),
                    const SizedBox(
                      width: LiveRoomTheme.pillBatteryWidth,
                      height: LiveRoomTheme.pillBatteryHeight,
                      child: CustomPaint(painter: RoomBatteryPainter()),
                    ),
                    const SizedBox(width: LiveRoomTheme.pillAmountGap),
                    Text(
                      '${superChat.batteries}',
                      maxLines: 1,
                      style: liveStyle(LiveRoomTheme.pillAmountText, LiveRoomTheme.ink, weight: FontWeight.w500),
                    ),
                    const SizedBox(width: LiveRoomTheme.pillPadRight),
                  ],
                ),
              ),
              if (dimmed) const Positioned.fill(child: ColoredBox(color: LiveRoomTheme.dim)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 醒目留言's card over the chat (228): the sender in their frame, the 电池, ⋮ and the message.
class RoomSuperChatCard extends StatelessWidget {
  const RoomSuperChatCard({super.key, required this.superChat, required this.onMore});

  final LiveSuperChat superChat;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final sc = superChat;
    final header = liveColor(sc.background, LiveRoomTheme.superChatHeaderFallback);
    final body = liveColor(sc.backgroundBottom, LiveRoomTheme.superChatFallback);
    const shape = BorderRadius.all(Radius.circular(LiveRoomTheme.cardCorner));
    Widget line(String text, Color colour, double centre, {Key? key}) => Positioned(
      left: LiveRoomTheme.cardNameX - LiveRoomTheme.cardSide,
      right: LiveRoomTheme.cardMoreRight + LiveRoomTheme.cardMore,
      top: centre - LiveRoomTheme.rowLine / 2,
      height: LiveRoomTheme.rowLine,
      child: Text(
        text,
        key: key,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: liveStyle(LiveRoomTheme.rowText, colour, line: LiveRoomTheme.rowLine),
      ),
    );
    // Each band carries its own translucency, so the header isn't laid over the body's colour too.
    return Container(
      key: ValueKey('live-sc-card-${sc.id}'),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(borderRadius: shape),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: body, width: LiveRoomTheme.scRowBorder),
        borderRadius: shape,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: LiveRoomTheme.cardHeader,
            color: header.withValues(alpha: LiveRoomTheme.cardAlpha),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: LiveRoomTheme.cardFaceX - LiveRoomTheme.cardFace / 2,
                  top: LiveRoomTheme.cardFaceY - LiveRoomTheme.cardFace / 2,
                  child: LiveFace(
                    url: sc.user.face,
                    size: LiveRoomTheme.cardFace,
                    guardLevel: sc.user.guardLevel,
                    frame: sc.user.faceFrame,
                  ),
                ),
                line(
                  sc.user.name,
                  liveColor(sc.user.nameColor, LiveRoomTheme.scHeaderInk),
                  LiveRoomTheme.cardNameCentre,
                ),
                line(
                  '${sc.batteries} 电池',
                  LiveRoomTheme.scHeaderInk,
                  LiveRoomTheme.cardPriceCentre,
                  key: const ValueKey('live-sc-card-price'),
                ),
                Positioned(
                  right: LiveRoomTheme.cardMoreRight - LiveRoomTheme.cardMore / 2,
                  top: LiveRoomTheme.cardMoreCentre - LiveRoomTheme.cardMore / 2,
                  width: LiveRoomTheme.cardMore,
                  height: LiveRoomTheme.cardMore,
                  child: Semantics(
                    button: true,
                    label: '更多',
                    onTap: onMore,
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: const ValueKey('live-sc-card-more'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onMore,
                      child: const CustomPaint(painter: RoomCardMorePainter()),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ColoredBox(
            color: body.withValues(alpha: LiveRoomTheme.cardAlpha),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: LiveRoomTheme.cardBody),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LiveRoomTheme.cardBodyPad,
                  vertical: (LiveRoomTheme.cardBody - LiveRoomTheme.rowLine) / 2,
                ),
                child: Text(
                  sc.message,
                  style: liveStyle(LiveRoomTheme.rowText, LiveRoomTheme.ink, line: LiveRoomTheme.rowLine),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 229: the card's ⋮ sheet over a further dim: 管理本条醒目留言 and 举报 (neither built), then 取消.
class RoomSuperChatActions extends StatelessWidget {
  const RoomSuperChatActions({super.key, required this.onManage, required this.onReport, required this.onCancel});

  final VoidCallback onManage;
  final VoidCallback onReport;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget row(String label, VoidCallback onTap, TextStyle style, {required Key key, bool centred = false}) =>
        Semantics(
          button: true,
          label: label,
          onTap: onTap,
          excludeSemantics: true,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: centred ? LiveRoomTheme.actionCancel : LiveRoomTheme.actionRow,
              padding: centred ? null : const EdgeInsets.only(left: LiveRoomTheme.actionLeft),
              alignment: centred ? Alignment.center : Alignment.centerLeft,
              child: Text(label, maxLines: 1, style: style),
            ),
          ),
        );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('live-sc-actions-dim'),
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: const ColoredBox(color: LiveRoomTheme.dim),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            key: const ValueKey('live-sc-actions'),
            decoration: const BoxDecoration(
              color: LiveRoomTheme.actionFill,
              borderRadius: BorderRadius.vertical(top: Radius.circular(LiveRoomTheme.actionRadius)),
            ),
            padding: EdgeInsets.only(bottom: bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row(
                  '管理本条醒目留言',
                  onManage,
                  liveStyle(LiveRoomTheme.actionManageText, LiveRoomTheme.actionManageInk),
                  key: const ValueKey('live-sc-manage'),
                ),
                row(
                  '举报',
                  onReport,
                  liveStyle(LiveRoomTheme.actionText, LiveRoomTheme.ink),
                  key: const ValueKey('live-sc-report'),
                ),
                const SizedBox(
                  height: LiveRoomTheme.actionBandHeight,
                  child: ColoredBox(color: LiveRoomTheme.actionBand),
                ),
                row(
                  '取消',
                  onCancel,
                  liveStyle(LiveRoomTheme.actionCancelText, LiveRoomTheme.ink),
                  key: const ValueKey('live-sc-cancel'),
                  centred: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
