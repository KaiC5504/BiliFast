import 'package:bili_core/api.dart';
import 'package:bili_core/logic.dart' show CountFormat;
import 'package:flutter/widgets.dart';

import '../../search/results/user_row.dart' show VerifiedBoltPainter;
import '../../shared/theme.dart';
import '../live_badges.dart';
import 'live_overlays.dart';
import 'live_room_model.dart';
import 'room_actions.dart';
import 'room_glyphs.dart';

/// 207's top row: ‹, the anchor's capsule with 关注, and 高能榜's three faces with the online count. It fills the
/// capsule's 36 pt row.
class RoomHeader extends StatelessWidget {
  const RoomHeader({super.key, required this.room, required this.overlays, required this.onBack});

  final LiveRoomModel room;
  final LiveOverlays overlays;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: room,
    builder: (context, _) {
      final info = room.info;
      final entry = room.entry;
      // An answer without the anchor (or a failed one) keeps the card's.
      final face = info?.anchorFace ?? '';
      final name = info?.anchorName ?? '';
      return Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: LiveRoomTheme.backTarget,
            child: Semantics(
              button: true,
              label: '返回',
              onTap: onBack,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('live-room-back'),
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: const CustomPaint(painter: RoomBackPainter()),
              ),
            ),
          ),
          Positioned(
            left: LiveRoomTheme.capsuleLeft,
            top: 0,
            height: LiveRoomTheme.capsuleHeight,
            child: _AnchorCapsule(
              face: face.isEmpty ? entry.anchorFace : face,
              frame: info?.anchorFrame ?? '',
              verify: info?.verify ?? LiveVerify.none,
              name: name.isEmpty ? entry.anchorName : name,
              likes: room.likeCount,
              following: room.following,
              onFollow: () => roomWrite(context, () => room.setFollowing(true)),
            ),
          ),
          Positioned(
            right: LiveRoomTheme.countRight,
            top: 0,
            bottom: 0,
            child: Center(
              child: _TopFaces(
                faces: room.topFaces,
                count: room.onlineCount,
                onTap: () => overlays.open(LiveOverlay.rank),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _AnchorCapsule extends StatelessWidget {
  const _AnchorCapsule({
    required this.face,
    required this.frame,
    required this.verify,
    required this.name,
    required this.likes,
    required this.following,
    required this.onFollow,
  });

  final String face;
  final String frame;
  final LiveVerify verify;
  final String name;
  final int likes;
  final bool following;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    const half = LiveRoomTheme.capsuleHeight / 2;
    final badge = switch (verify) {
      LiveVerify.personal => LiveRoomTheme.verifyPerson,
      LiveVerify.organization => LiveRoomTheme.verifyOrganisation,
      LiveVerify.none => null,
    };
    const disc = LiveRoomTheme.verifyDisc + LiveRoomTheme.verifyRing * 2;
    return Container(
      key: const ValueKey('live-anchor'),
      height: LiveRoomTheme.capsuleHeight,
      decoration: BoxDecoration(color: LiveRoomTheme.glass, borderRadius: BorderRadius.circular(half)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: LiveRoomTheme.faceInset),
          SizedBox.square(
            dimension: LiveRoomTheme.face,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                LiveFace(url: face, size: LiveRoomTheme.face, frame: frame),
                if (badge != null)
                  Positioned(
                    right: -0.33,
                    bottom: -0.33,
                    width: disc,
                    height: disc,
                    child: Container(
                      key: const ValueKey('live-anchor-verified'),
                      padding: const EdgeInsets.all(LiveRoomTheme.verifyRing),
                      decoration: const BoxDecoration(color: LiveRoomTheme.verifyRingInk, shape: BoxShape.circle),
                      child: CustomPaint(painter: VerifiedBoltPainter(badge)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: LiveRoomTheme.nameGap),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: LiveRoomTheme.nameMax),
            child: Padding(
              padding: const EdgeInsets.only(top: half + LiveRoomTheme.nameCentre - LiveRoomTheme.nameLine / 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: liveStyle(LiveRoomTheme.nameText, LiveRoomTheme.ink, line: LiveRoomTheme.nameLine),
                  ),
                  const SizedBox(
                    height:
                        LiveRoomTheme.likesCentre -
                        LiveRoomTheme.likesLine / 2 -
                        LiveRoomTheme.nameCentre -
                        LiveRoomTheme.nameLine / 2,
                  ),
                  Text(
                    '${CountFormat.short(likes)}点赞',
                    key: const ValueKey('live-anchor-likes'),
                    maxLines: 1,
                    style: liveStyle(LiveRoomTheme.likesText, LiveRoomTheme.likesInk, line: LiveRoomTheme.likesLine),
                  ),
                ],
              ),
            ),
          ),
          if (following)
            const SizedBox(width: LiveRoomTheme.capsuleEndBare)
          else ...[
            const SizedBox(width: LiveRoomTheme.followGap),
            Semantics(
              button: true,
              label: '关注',
              onTap: onFollow,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('live-follow'),
                behavior: HitTestBehavior.opaque,
                onTap: onFollow,
                child: Container(
                  width: LiveRoomTheme.followWidth,
                  height: LiveRoomTheme.followHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: LiveRoomTheme.pink,
                    borderRadius: BorderRadius.circular(LiveRoomTheme.followHeight / 2),
                  ),
                  child: Text('关注', maxLines: 1, style: liveStyle(LiveRoomTheme.followText, LiveRoomTheme.ink)),
                ),
              ),
            ),
            const SizedBox(width: LiveRoomTheme.capsuleEnd),
          ],
        ],
      ),
    );
  }
}

/// 高能榜's first three faces, the leftmost on top, over the count's capsule; a tap opens 高能榜.
class _TopFaces extends StatelessWidget {
  const _TopFaces({required this.faces, required this.count, required this.onTap});

  final List<String> faces;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shown = faces.take(3).toList();
    const face = LiveRoomTheme.topFace;
    const step = LiveRoomTheme.topFaceStep;
    final facesWidth = shown.isEmpty ? 0.0 : (shown.length - 1) * step + face;
    final capsuleLeft = shown.isEmpty ? 0.0 : facesWidth - face / 2;
    return Semantics(
      button: true,
      label: '高能榜',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('live-top-faces'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Positioned(
              left: capsuleLeft,
              right: 0,
              top: (face - LiveRoomTheme.countHeight) / 2,
              height: LiveRoomTheme.countHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: LiveRoomTheme.glass,
                  borderRadius: BorderRadius.circular(LiveRoomTheme.countHeight / 2),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: facesWidth,
                  height: face,
                  child: Stack(
                    children: [
                      // Drawn last to first, so the leftmost lies on top.
                      for (var i = shown.length - 1; i >= 0; i--)
                        Positioned(
                          left: i * step,
                          top: 0,
                          width: face,
                          height: face,
                          child: Container(
                            key: ValueKey('live-top-face-$i'),
                            padding: const EdgeInsets.all(LiveRoomTheme.topFaceRing),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: LiveRoomTheme.topFaceRings[i]),
                            child: LiveFace(url: shown[i], size: face - LiveRoomTheme.topFaceRing * 2),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: shown.isEmpty ? LiveRoomTheme.countPadRight : LiveRoomTheme.countGap),
                SizedBox(
                  height: face,
                  child: Center(
                    child: Text(
                      count > 0 ? roomOnlineCount(count) : '',
                      key: const ValueKey('live-online-count'),
                      maxLines: 1,
                      style: liveStyle(LiveRoomTheme.countText, LiveRoomTheme.ink),
                    ),
                  ),
                ),
                const SizedBox(width: LiveRoomTheme.countPadRight),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The chips under the header: the room's ranks (热门榜, 网游人气第 28), and 更多直播 › at the right. None is built:
/// each toasts.
class RoomChips extends StatelessWidget {
  const RoomChips({super.key, required this.room});

  final LiveRoomModel room;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: room,
    builder: (context, _) {
      final chips = room.info?.rankChips ?? const <String>[];
      return Stack(
        children: [
          Positioned(
            left: LiveRoomTheme.chipLeft,
            top: 0,
            bottom: 0,
            right: LiveRoomTheme.countRight + 100,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  for (final (i, chip) in chips.indexed) ...[
                    if (i > 0) const SizedBox(width: LiveRoomTheme.chipGap),
                    _Chip(key: ValueKey('live-chip-$i'), label: chip, onTap: () => toastNotYet(context)),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            right: LiveRoomTheme.countRight,
            top: 0,
            bottom: 0,
            child: _Chip(
              key: const ValueKey('live-more-rooms'),
              label: '更多直播',
              chevron: true,
              onTap: () => toastNotYet(context),
            ),
          ),
        ],
      );
    },
  );
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.onTap, this.chevron = false});

  final String label;
  final bool chevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: LiveRoomTheme.chipHeight,
        padding: const EdgeInsets.symmetric(horizontal: LiveRoomTheme.chipPad),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: LiveRoomTheme.glass,
          borderRadius: BorderRadius.circular(LiveRoomTheme.chipHeight / 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, maxLines: 1, style: liveStyle(LiveRoomTheme.chipText, LiveRoomTheme.ink)),
            if (chevron) ...[
              const SizedBox(width: LiveRoomTheme.chipChevronGap),
              const SizedBox(
                width: LiveRoomTheme.chipChevronWidth,
                height: LiveRoomTheme.chipChevronHeight,
                child: CustomPaint(painter: RoomChevronPainter()),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
