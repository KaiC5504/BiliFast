import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../shared/theme.dart';
import '../live_badges.dart';
import '../live_login.dart';
import 'live_overlays.dart';
import 'room_actions.dart';
import 'room_glyphs.dart';

/// 207's bottom bar: ⋯ (221), the 弹幕 input with its emote button, the gift and the + capsule with the viewer's face.
/// The input opens the 弹幕 input once logged in; the gift and + aren't built.
class RoomBottomBar extends StatelessWidget {
  const RoomBottomBar({super.key, required this.overlays, required this.ownFace});

  final LiveOverlays overlays;

  /// The viewer's face for the + capsule; empty for the default one.
  final String ownFace;

  Future<void> _openSend(BuildContext context) async {
    if (roomLoggedOut(AppScope.of(context))) {
      await requestLiveLogin(context);
      return;
    }
    overlays.open(LiveOverlay.send);
  }

  @override
  Widget build(BuildContext context) {
    const circle = LiveRoomTheme.barCircle;
    const inputFromRight = 440 - LiveRoomTheme.inputRight;
    const giftFromRight = 440 - LiveRoomTheme.giftLeft - circle;
    Widget button(String label, Key key, VoidCallback onTap, Widget child) => Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(key: key, behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
    );
    return Stack(
      children: [
        Positioned(
          left: LiveRoomTheme.barLeft,
          top: 0,
          width: circle,
          height: circle,
          child: button(
            '更多',
            const ValueKey('live-bar-more'),
            () => overlays.open(LiveOverlay.more),
            const DecoratedBox(
              decoration: BoxDecoration(color: LiveRoomTheme.barCircleFill, shape: BoxShape.circle),
              child: CustomPaint(painter: RoomDotsPainter()),
            ),
          ),
        ),
        Positioned(
          left: LiveRoomTheme.inputLeft,
          right: inputFromRight,
          top: 0,
          height: circle,
          child: button(
            '弹幕支持下～',
            const ValueKey('live-bar-input'),
            () => _openSend(context),
            Container(
              padding: const EdgeInsets.only(left: LiveRoomTheme.inputPad, right: LiveRoomTheme.emoteFaceEnd),
              decoration: BoxDecoration(
                color: LiveRoomTheme.inputFill,
                borderRadius: BorderRadius.circular(circle / 2),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '弹幕支持下～',
                      maxLines: 1,
                      style: liveStyle(LiveRoomTheme.inputText, LiveRoomTheme.inputInk),
                    ),
                  ),
                  button(
                    '表情',
                    const ValueKey('live-bar-emote'),
                    () => _openSend(context),
                    const SizedBox.square(
                      dimension: LiveRoomTheme.emoteFace,
                      child: CustomPaint(painter: RoomWinkPainter()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: giftFromRight,
          top: 0,
          width: circle,
          height: circle,
          child: button(
            '礼物',
            const ValueKey('live-bar-gift'),
            () => toastNotYet(context),
            DecoratedBox(
              decoration: const BoxDecoration(color: LiveRoomTheme.barCircleFill, shape: BoxShape.circle),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/live/room_gift.png',
                      width: LiveRoomTheme.giftArt,
                      height: LiveRoomTheme.giftArt,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const Positioned(
                    right: 0,
                    top: LiveRoomTheme.giftDotTop,
                    width: LiveRoomTheme.giftDot,
                    height: LiveRoomTheme.giftDot,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: LiveRoomTheme.giftDotInk, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: LiveRoomTheme.plusRight,
          top: 0,
          width: LiveRoomTheme.plusWidth,
          height: circle,
          child: button(
            '加号',
            const ValueKey('live-bar-plus'),
            () => toastNotYet(context),
            DecoratedBox(
              decoration: BoxDecoration(color: LiveRoomTheme.plusFill, borderRadius: BorderRadius.circular(circle / 2)),
              child: Stack(
                children: [
                  Positioned(
                    left: LiveRoomTheme.plusFaceInset,
                    top: (circle - LiveRoomTheme.plusFace) / 2,
                    child: LiveFace(url: ownFace, size: LiveRoomTheme.plusFace),
                  ),
                  const Positioned(
                    left: LiveRoomTheme.plusCentre - circle / 2,
                    top: 0,
                    width: circle,
                    height: circle,
                    child: CustomPaint(painter: RoomPlusPainter()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
