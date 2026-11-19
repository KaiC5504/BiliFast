import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../live/live_entry.dart';
import '../../live/live_routes.dart';
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../../video/intro/collection_row.dart' show Chevron;
import 'follow_parts.dart';

/// 全部 / 视频 (127, 128): two grey halves, the chosen one's word pink.
class FollowSwitch extends StatelessWidget {
  const FollowSwitch({super.key, required this.type, required this.onSelect});

  final DynamicFeedType type;
  final ValueChanged<DynamicFeedType> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: DynamicFeedTheme.switchHeight,
    child: Row(
      children: [
        Expanded(child: _half(DynamicFeedType.all, '全部')),
        const SizedBox(width: DynamicFeedTheme.switchGap),
        Expanded(child: _half(DynamicFeedType.video, '视频')),
      ],
    ),
  );

  Widget _half(DynamicFeedType kind, String label) {
    final on = kind == type;
    return FollowTap(
      key: ValueKey('follow-switch-${kind.rawValue}'),
      label: label,
      selected: on,
      onTap: () => onSelect(kind),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DynamicFeedTheme.switchFill,
          borderRadius: BorderRadius.circular(DynamicFeedTheme.switchRadius),
        ),
        child: Center(
          child: Text(
            label,
            style: followStyle(
              DynamicFeedTheme.switchText,
              on ? DynamicFeedTheme.switchOn : DynamicFeedTheme.switchOff,
              weight: on ? DynamicFeedTheme.switchOnWeight : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// A section's title at its left, and 更多 › or 全部 › at its right when [more] is given, after [lead] and a dot when
/// that is given too.
class FollowSectionTitle extends StatelessWidget {
  FollowSectionTitle({
    super.key,
    required this.title,
    this.more,
    this.moreKey,
    this.moreText = DynamicFeedTheme.moreText,
    Color? moreInk,
    this.moreGap = DynamicFeedTheme.moreGap,
    this.lead,
    this.onMore,
  }) : moreInk = moreInk ?? DynamicFeedTheme.moreInk;

  final String title;
  final String? more;
  final Key? moreKey;
  final double moreText;
  final Color moreInk;
  final double moreGap;

  /// 最常访问's `N人直播中` (263).
  final String? lead;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final style = followStyle(
      DynamicFeedTheme.sectionText,
      DynamicFeedTheme.sectionInk,
      weight: DynamicFeedTheme.sectionWeight,
      height: DynamicFeedTheme.sectionLine / DynamicFeedTheme.sectionText,
    );
    final more = this.more;
    final lead = this.lead;
    final onMore = this.onMore;
    return SizedBox(
      height: DynamicFeedTheme.sectionLine,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: DynamicFeedTheme.gutter,
            top: 0,
            child: Semantics(
              header: true,
              child: Text(title, style: style, strutStyle: BiliFonts.strutOf(context, style)),
            ),
          ),
          if (more != null && onMore != null)
            Positioned(
              right: 0,
              top: (DynamicFeedTheme.sectionLine - DynamicFeedTheme.moreTarget) / 2,
              height: DynamicFeedTheme.moreTarget,
              child: FollowTap(
                key: moreKey,
                label: lead == null ? more : '$lead · $more',
                onTap: onMore,
                child: Padding(
                  padding: const EdgeInsets.only(left: DynamicFeedTheme.gutter, right: DynamicFeedTheme.chevronRight),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (lead != null) ...[
                        Text(
                          lead,
                          key: const ValueKey('follow-faces-live-count'),
                          style: followStyle(moreText, moreInk),
                        ),
                        SizedBox(
                          width: DynamicFeedTheme.liveLeadGap,
                          child: Center(
                            child: SizedBox.square(
                              dimension: DynamicFeedTheme.liveLeadDot,
                              child: DecoratedBox(
                                decoration: ShapeDecoration(color: moreInk, shape: const CircleBorder()),
                              ),
                            ),
                          ),
                        ),
                      ],
                      Text(more, style: followStyle(moreText, moreInk)),
                      SizedBox(width: moreGap),
                      Chevron(
                        size: const Size(DynamicFeedTheme.chevronWidth, DynamicFeedTheme.chevronHeight),
                        stroke: DynamicFeedTheme.chevronStroke,
                        color: DynamicFeedTheme.chevronInk,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One 最常访问 face: the round face in its ring, the pink dot while it has news, the name under it on up to two lines.
class FollowFace extends StatelessWidget {
  const FollowFace({super.key, required this.up, required this.dot, required this.onTap});

  final DynamicUp up;
  final bool dot;
  final VoidCallback onTap;

  /// The faces row's height: the face, then two lines of name.
  static const rowHeight =
      DynamicFeedTheme.face +
      DynamicFeedTheme.nameCentre -
      DynamicFeedTheme.nameLine / 2 +
      DynamicFeedTheme.nameLine * 2;

  @override
  Widget build(BuildContext context) {
    const dotLeft = DynamicFeedTheme.face / 2 + DynamicFeedTheme.dotOffset - DynamicFeedTheme.dotRing / 2;
    return FollowTap(
      label: dot ? '${up.name}，有更新' : up.name,
      onTap: onTap,
      child: _FaceSlot(
        face: up.face,
        name: up.name,
        marks: [
          if (dot)
            Positioned(
              key: ValueKey('follow-dot-${up.mid}'),
              left: dotLeft,
              top: dotLeft,
              width: DynamicFeedTheme.dotRing,
              height: DynamicFeedTheme.dotRing,
              child: DecoratedBox(
                decoration: ShapeDecoration(color: BiliColors.card, shape: const CircleBorder()),
                child: Center(
                  child: SizedBox.square(
                    dimension: DynamicFeedTheme.dot,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(color: DynamicFeedTheme.dotInk, shape: const CircleBorder()),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A face that is live, leading the row (263): its pink ring and 直播中 over the ring's foot, never the dot.
class FollowLiveFace extends StatelessWidget {
  const FollowLiveFace({super.key, required this.up, required this.onTap});

  final DynamicLiveUp up;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ringLeft = (DynamicFeedTheme.face - DynamicFeedTheme.liveRing) / 2;
    const pillWidth = DynamicFeedTheme.livePillWidth + DynamicFeedTheme.livePillRim * 2;
    const pillHeight = DynamicFeedTheme.livePillHeight + DynamicFeedTheme.livePillRim * 2;
    return FollowTap(
      label: '${up.name}，直播中',
      onTap: onTap,
      child: _FaceSlot(
        face: up.face,
        name: up.name,
        marks: [
          Positioned(
            left: ringLeft,
            top: ringLeft,
            width: DynamicFeedTheme.liveRing,
            height: DynamicFeedTheme.liveRing,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: CircleBorder(
                  side: BorderSide(color: DynamicFeedTheme.liveRingInk, width: DynamicFeedTheme.liveRingStroke),
                ),
              ),
            ),
          ),
          Positioned(
            key: ValueKey('follow-live-pill-${up.mid}'),
            left: (DynamicFeedTheme.face - pillWidth) / 2,
            top: DynamicFeedTheme.face / 2 + DynamicFeedTheme.livePillDrop - pillHeight / 2,
            width: pillWidth,
            height: pillHeight,
            child: const _LivePill(),
          ),
        ],
      ),
    );
  }
}

/// The face in its grey ring with [marks] over it, the name under it on up to two lines, in a
/// [DynamicFeedTheme.facePitch] slot.
class _FaceSlot extends StatelessWidget {
  const _FaceSlot({required this.face, required this.name, required this.marks});

  final String face;
  final String name;
  final List<Widget> marks;

  @override
  Widget build(BuildContext context) {
    final style = followStyle(
      DynamicFeedTheme.nameText,
      DynamicFeedTheme.nameInk,
      height: DynamicFeedTheme.nameLine / DynamicFeedTheme.nameText,
    );
    return SizedBox(
      width: DynamicFeedTheme.facePitch,
      child: Column(
        children: [
          SizedBox.square(
            dimension: DynamicFeedTheme.face,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: ClipOval(child: RemoteImage.avatar(face))),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: CircleBorder(
                        side: BorderSide(color: DynamicFeedTheme.faceRingInk, width: DynamicFeedTheme.faceRing),
                      ),
                    ),
                  ),
                ),
                ...marks,
              ],
            ),
          ),
          const SizedBox(height: DynamicFeedTheme.nameCentre - DynamicFeedTheme.nameLine / 2),
          SizedBox(
            width: DynamicFeedTheme.nameWidth,
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style,
              strutStyle: BiliFonts.strutOf(context, style),
            ),
          ),
        ],
      ),
    );
  }
}

/// 直播中 on its pink stadium, the bars moving.
class _LivePill extends StatelessWidget {
  const _LivePill();

  static const _bars = 'assets/images/dynamic/live_ing.gif';

  @override
  Widget build(BuildContext context) {
    final style = followStyle(DynamicFeedTheme.liveText, DynamicFeedTheme.liveInk);
    return DecoratedBox(
      decoration: ShapeDecoration(color: DynamicFeedTheme.livePillRimInk, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.all(DynamicFeedTheme.livePillRim),
        child: DecoratedBox(
          decoration: ShapeDecoration(color: DynamicFeedTheme.livePillFill, shape: const StadiumBorder()),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: DynamicFeedTheme.liveBarsLeft,
                top: DynamicFeedTheme.liveBarsDrop,
                width: DynamicFeedTheme.liveBars,
                height: DynamicFeedTheme.liveBars,
                // Each of the gif's frames repaints only its square, not the row around it.
                child: RepaintBoundary(
                  child: Image.asset(
                    _bars,
                    width: DynamicFeedTheme.liveBars,
                    height: DynamicFeedTheme.liveBars,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              Positioned(
                left: DynamicFeedTheme.liveBarsLeft + DynamicFeedTheme.liveBars,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text('直播中', maxLines: 1, style: style, strutStyle: BiliFonts.strutOf(context, style)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The line between the live faces and the rest.
class _LiveRule extends StatelessWidget {
  const _LiveRule();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: DynamicFeedTheme.liveRuleBefore, right: DynamicFeedTheme.liveRuleAfter),
    child: SizedBox(
      width: DynamicFeedTheme.liveRuleWidth,
      height: DynamicFeedTheme.face,
      child: Center(
        child: SizedBox(
          key: const ValueKey('follow-live-rule'),
          width: DynamicFeedTheme.liveRuleWidth,
          height: DynamicFeedTheme.liveRuleHeight,
          child: ColoredBox(color: DynamicFeedTheme.liveRuleInk),
        ),
      ),
    ),
  );
}

/// The faces side by side, scrolling sideways when there are more than fit; asks for more near its end.
class FollowFacesRow extends StatefulWidget {
  const FollowFacesRow({
    super.key,
    required this.ups,
    this.liveUps = const [],
    required this.dot,
    required this.onOpen,
    this.onNearEnd,
    this.controller,
    this.below,
  });

  final List<DynamicUp> ups;

  /// The followed who are live now, led before [ups] with 直播中 (263).
  final List<DynamicLiveUp> liveUps;
  final bool Function(DynamicUp up) dot;
  final ValueChanged<DynamicUp> onOpen;
  final VoidCallback? onNearEnd;
  final ScrollController? controller;

  /// Drawn under the faces, inside the scrolled content: the face sheet's pointer. Its origin is the first of [shown],
  /// after any live faces.
  final Widget Function(BuildContext context)? below;

  /// [ups] as the row draws them: without anyone already led as live.
  static List<DynamicUp> shown(List<DynamicUp> ups, List<DynamicLiveUp> liveUps) {
    if (liveUps.isEmpty) return ups;
    final live = {for (final up in liveUps) up.mid};
    return [
      for (final up in ups)
        if (!live.contains(up.mid)) up,
    ];
  }

  /// Opens a live face's room; tests put their own here.
  @visibleForTesting
  static Future<void> Function(BuildContext context, LiveRoomEntry entry) openRoom = openLiveRoom;

  @override
  State<FollowFacesRow> createState() => _FollowFacesRowState();
}

class _FollowFacesRowState extends State<FollowFacesRow> {
  bool _scrolled(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth == 0 &&
        metrics.axis == Axis.horizontal &&
        metrics.hasContentDimensions &&
        metrics.extentAfter < DynamicFeedTheme.facesAhead) {
      widget.onNearEnd?.call();
    }
    return false;
  }

  /// A room without its id in the answer opens the face sheet, as any other face does.
  void _openLive(DynamicLiveUp up) {
    if (up.roomId <= 0) {
      widget.onOpen(DynamicUp(mid: up.mid, name: up.name, face: up.face));
      return;
    }
    final entry = LiveRoomEntry(roomId: up.roomId, uid: up.mid, anchorName: up.name, anchorFace: up.face);
    unawaited(FollowFacesRow.openRoom(context, entry));
  }

  @override
  Widget build(BuildContext context) {
    final below = widget.below;
    final live = widget.liveUps;
    final ups = FollowFacesRow.shown(widget.ups, live);
    final faces = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final up in ups)
          FollowFace(
            key: ValueKey('follow-face-${up.mid}'),
            up: up,
            dot: widget.dot(up),
            onTap: () => widget.onOpen(up),
          ),
      ],
    );
    final rest = below == null ? faces : Stack(clipBehavior: Clip.none, children: [faces, below(context)]);
    return NotificationListener<ScrollNotification>(
      onNotification: _scrolled,
      child: SingleChildScrollView(
        controller: widget.controller,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: DynamicFeedTheme.facesInset),
        // The live ring stands 2 pt above the row's box; the row spans the screen, so sideways nothing shows past it.
        clipBehavior: live.isEmpty ? Clip.hardEdge : Clip.none,
        child: live.isEmpty
            ? rest
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final up in live)
                    FollowLiveFace(key: ValueKey('follow-live-${up.mid}'), up: up, onTap: () => _openLive(up)),
                  if (ups.isNotEmpty) ...[const _LiveRule(), rest],
                ],
              ),
      ),
    );
  }
}

/// The white top under the header (127, 128): 全部 / 视频, then 最常访问 with its faces once they have come.
class FollowTop extends StatelessWidget {
  const FollowTop({
    super.key,
    required this.type,
    required this.ups,
    this.liveUps = const [],
    required this.dot,
    required this.onSelect,
    required this.onOpenFace,
    required this.onMore,
    required this.onNearEnd,
    required this.facesController,
    required this.facesKey,
  });

  final DynamicFeedType type;
  final List<DynamicUp> ups;

  /// The followed who are live now, led before [ups] with 直播中 (263).
  final List<DynamicLiveUp> liveUps;
  final bool Function(DynamicUp up) dot;
  final ValueChanged<DynamicFeedType> onSelect;
  final ValueChanged<DynamicUp> onOpenFace;
  final VoidCallback onMore;
  final VoidCallback onNearEnd;
  final ScrollController facesController;

  /// On the faces row's box, so the face sheet can rise from where the row is.
  final GlobalKey facesKey;

  /// Without faces only the switch shows, as much white under it as over it.
  static double heightOf({required bool faces}) =>
      faces ? DynamicFeedTheme.top : DynamicFeedTheme.switchTop * 2 + DynamicFeedTheme.switchHeight;

  @override
  Widget build(BuildContext context) {
    final faces = ups.isNotEmpty || liveUps.isNotEmpty;
    return ColoredBox(
      color: BiliColors.card,
      child: SizedBox(
        height: heightOf(faces: faces),
        child: Stack(
          children: [
            Positioned(
              left: DynamicFeedTheme.gutter,
              right: DynamicFeedTheme.gutter,
              top: DynamicFeedTheme.switchTop,
              child: FollowSwitch(type: type, onSelect: onSelect),
            ),
            if (faces) ...[
              Positioned(
                left: 0,
                right: 0,
                top: DynamicFeedTheme.facesTitleCentre - DynamicFeedTheme.sectionLine / 2,
                child: FollowSectionTitle(
                  title: '最常访问',
                  more: type == DynamicFeedType.all ? '更多' : null,
                  lead: liveUps.isEmpty ? null : '${liveUps.length}人直播中',
                  moreKey: const ValueKey('follow-faces-more'),
                  onMore: onMore,
                ),
              ),
              Positioned(
                key: facesKey,
                left: 0,
                right: 0,
                top: DynamicFeedTheme.facesTop,
                height: FollowFace.rowHeight,
                child: FollowFacesRow(
                  liveUps: liveUps,
                  ups: ups,
                  dot: dot,
                  onOpen: onOpenFace,
                  onNearEnd: onNearEnd,
                  controller: facesController,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 我的追番 · 追剧 (128), on 视频 only: the posters with 全N话 over their foot and the title under each.
class FollowBangumiSection extends StatelessWidget {
  const FollowBangumiSection({super.key, required this.items, required this.onAll, required this.onOpen});

  final List<FollowedBangumi> items;
  final VoidCallback onAll;
  final ValueChanged<FollowedBangumi> onOpen;

  @override
  Widget build(BuildContext context) {
    final titleStyle = followStyle(
      DynamicFeedTheme.posterTitleText,
      DynamicFeedTheme.posterTitleInk,
      height: DynamicFeedTheme.posterTitleLine / DynamicFeedTheme.posterTitleText,
    );
    const rowHeight =
        DynamicFeedTheme.posterHeight + DynamicFeedTheme.posterTitleCentre + DynamicFeedTheme.posterTitleLine / 2;
    return ColoredBox(
      key: const ValueKey('follow-bangumi'),
      color: BiliColors.card,
      child: SizedBox(
        height: DynamicFeedTheme.bangumi,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: DynamicFeedTheme.bangumiTitleCentre - DynamicFeedTheme.sectionLine / 2,
              child: FollowSectionTitle(
                title: '我的追番 · 追剧',
                more: '全部',
                moreKey: const ValueKey('follow-bangumi-all'),
                moreText: DynamicFeedTheme.allText,
                moreInk: DynamicFeedTheme.allInk,
                moreGap: DynamicFeedTheme.allGap,
                onMore: onAll,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: DynamicFeedTheme.posterTop,
              height: rowHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.symmetric(horizontal: DynamicFeedTheme.gutter),
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(width: DynamicFeedTheme.posterGap),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return FollowTap(
                    key: ValueKey('follow-poster-${item.seasonId}'),
                    label: item.title,
                    onTap: () => onOpen(item),
                    child: SizedBox(
                      width: DynamicFeedTheme.posterWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Poster(item: item),
                          const SizedBox(
                            height: DynamicFeedTheme.posterTitleCentre - DynamicFeedTheme.posterTitleLine / 2,
                          ),
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                            strutStyle: BiliFonts.strutOf(context, titleStyle),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.item});

  final FollowedBangumi item;

  @override
  Widget build(BuildContext context) {
    final progress = item.progress;
    return ClipRRect(
      borderRadius: BorderRadius.circular(DynamicFeedTheme.posterRadius),
      child: SizedBox(
        width: DynamicFeedTheme.posterWidth,
        height: DynamicFeedTheme.posterHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RemoteImage(item.cover, cover: true),
            if (progress.isNotEmpty) ...[
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: DynamicFeedTheme.posterShadeHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [DynamicFeedTheme.posterShadeTop, DynamicFeedTheme.posterShade],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: DynamicFeedTheme.progressLeft,
                right: DynamicFeedTheme.progressLeft,
                bottom: DynamicFeedTheme.progressBottom,
                child: Text(
                  progress,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: followStyle(DynamicFeedTheme.progressText, DynamicFeedTheme.progressInk),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
