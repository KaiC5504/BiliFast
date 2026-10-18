import 'package:bili_core/api.dart' show OfficialKind, StaffMember, UploaderCard, VideoDetail;
import 'package:bili_core/logic.dart';
import 'package:flutter/widgets.dart';

import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../actions/video_actions.dart';

/// The uploader (03): avatar with its verification badge, the name (pink for 大会员), 粉丝 and 视频, and the 关注 pill;
/// a 联合投稿 shows its staff instead.
class UploaderRow extends StatelessWidget {
  const UploaderRow({super.key, required this.detail, this.card, this.actions});

  final VideoDetail detail;

  /// The uploader's card (fans, videos, 大会员), null until it arrives.
  final UploaderCard? card;

  /// 关注 belongs to the actions; before they exist the pill shows the card's state.
  final VideoActions? actions;

  @override
  Widget build(BuildContext context) {
    final follow = _FollowListener(actions: actions, cardFollowing: card?.following ?? false);
    // Swift shows the staff only for more than one member; a lone member is just the uploader.
    final body = detail.staff.length > 1 ? _StaffRow(staff: detail.staff, follow: follow) : _single(follow);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1,
      child: Padding(
        padding: const EdgeInsets.only(
          left: BiliMetrics.gutter,
          right: BiliMetrics.gutter,
          top: IntroTheme.uploaderTop,
        ),
        child: body,
      ),
    );
  }

  Widget _single(Widget follow) {
    final card = this.card;
    return SizedBox(
      height: IntroTheme.avatar,
      child: Row(
        children: [
          _Avatar(face: _or(card?.face, detail.owner.face), official: card?.official ?? OfficialKind.none),
          const SizedBox(width: IntroTheme.avatarGap),
          Expanded(
            child: _NameAndCounts(name: _or(card?.name, detail.owner.name), card: card),
          ),
          const SizedBox(width: IntroTheme.avatarGap),
          follow,
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.face, required this.official});

  final String face;
  final OfficialKind official;

  @override
  Widget build(BuildContext context) {
    final badge = switch (official) {
      OfficialKind.person => IntroTheme.badgePerson,
      OfficialKind.organisation => IntroTheme.badgeOrganisation,
      OfficialKind.none => null,
    };
    return SizedBox.square(
      dimension: IntroTheme.avatar,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: ClipOval(child: RemoteImage(face))),
          if (badge != null)
            Positioned(
              right: -IntroTheme.badgeRing,
              bottom: -IntroTheme.badgeRing,
              child: ExcludeSemantics(child: VerifiedBadge(color: badge)),
            ),
        ],
      ),
    );
  }
}

/// The bolt disc on a verified uploader's avatar, ringed in the page's white so it reads over any face.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: IntroTheme.badge + IntroTheme.badgeRing * 2,
    height: IntroTheme.badge + IntroTheme.badgeRing * 2,
    padding: const EdgeInsets.all(IntroTheme.badgeRing),
    decoration: const BoxDecoration(color: BiliColors.card, shape: BoxShape.circle),
    child: CustomPaint(painter: _BoltPainter(color)),
  );
}

class _BoltPainter extends CustomPainter {
  const _BoltPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.drawCircle(size.center(Offset.zero), side / 2, Paint()..color = color);
    // Traced on 03 at 10×, as fractions of the disc.
    Offset p(double x, double y) => Offset(x * side, y * side);
    final bolt = Path()
      ..addPolygon([p(0.6, 0.19), p(0.25, 0.53), p(0.47, 0.53), p(0.42, 0.81), p(0.77, 0.46), p(0.55, 0.46)], true);
    canvas.drawPath(bolt, Paint()..color = IntroTheme.badgeBolt);
  }

  @override
  bool shouldRepaint(_BoltPainter oldDelegate) => oldDelegate.color != color;
}

/// The name and the counts sit on fixed lines, so the counts arriving later fade in without moving the name.
class _NameAndCounts extends StatelessWidget {
  const _NameAndCounts({required this.name, required this.card});

  final String name;
  final UploaderCard? card;

  @override
  Widget build(BuildContext context) {
    final card = this.card;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final counts = card == null ? '' : '${CountFormat.short(card.fans)}粉丝  ${CountFormat.short(card.videos)}视频';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: IntroTheme.nameCentre - IntroTheme.nameLine / 2,
          height: IntroTheme.nameLine,
          child: AnimatedDefaultTextStyle(
            duration: animate ? const Duration(milliseconds: 200) : Duration.zero,
            style: TextStyle(
              fontFamily: BiliFonts.family,
              fontSize: IntroTheme.nameText,
              height: IntroTheme.nameLine / IntroTheme.nameText,
              leadingDistribution: TextLeadingDistribution.even,
              letterSpacing: IntroTheme.nameSpacing,
              color: card?.isVip == true ? BiliColors.pink : IntroTheme.name,
            ),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: IntroTheme.fansCentre + IntroTheme.fansDrop - IntroTheme.fansLine / 2,
          height: IntroTheme.fansLine,
          child: AnimatedOpacity(
            opacity: card == null ? 0 : 1,
            duration: animate ? const Duration(milliseconds: 220) : Duration.zero,
            curve: Curves.easeOut,
            child: Text(
              counts,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: BiliFonts.family,
                fontSize: IntroTheme.fansText,
                height: IntroTheme.fansLine / IntroTheme.fansText,
                leadingDistribution: TextLeadingDistribution.even,
                letterSpacing: IntroTheme.fansSpacing,
                color: BiliColors.secondaryText,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 联合投稿: the members side by side, each avatar over the name and the role, scrolling when they don't fit.
class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.staff, required this.follow});

  final List<StaffMember> staff;
  final Widget follow;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: BiliFonts.family, leadingDistribution: TextLeadingDistribution.even);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: IntroTheme.staffSpacing,
              children: [
                for (final member in staff)
                  Semantics(
                    container: true,
                    label: '${member.name}，${member.title}',
                    excludeSemantics: true,
                    child: SizedBox(
                      width: IntroTheme.staffWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: IntroTheme.staffAvatar,
                            child: ClipOval(child: RemoteImage(member.face)),
                          ),
                          const SizedBox(height: IntroTheme.staffNameTop),
                          Text(
                            member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(
                              fontSize: IntroTheme.staffNameText,
                              height: IntroTheme.staffLine / IntroTheme.staffNameText,
                              color: IntroTheme.name,
                            ),
                          ),
                          Text(
                            member.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(
                              fontSize: IntroTheme.staffRoleText,
                              height: IntroTheme.staffRoleLine / IntroTheme.staffRoleText,
                              color: BiliColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: IntroTheme.avatarGap),
        // Level with the avatars, where the single row has it.
        SizedBox(
          height: IntroTheme.staffAvatar,
          child: Center(child: follow),
        ),
      ],
    );
  }
}

class _FollowListener extends StatelessWidget {
  const _FollowListener({required this.actions, required this.cardFollowing});

  final VideoActions? actions;
  final bool cardFollowing;

  @override
  Widget build(BuildContext context) {
    final actions = this.actions;
    if (actions == null) return FollowPill(following: cardFollowing, onTap: null);
    return ListenableBuilder(
      listenable: actions,
      builder: (context, _) => FollowPill(following: actions.following, onTap: actions.tapFollow),
    );
  }
}

/// 03's pink "+ 关注", or the grey 已关注; the change cross-fades.
class FollowPill extends StatefulWidget {
  const FollowPill({super.key, required this.following, required this.onTap});

  final bool following;

  /// Null before the actions exist: the pill shows, but a tap does nothing.
  final VoidCallback? onTap;

  @override
  State<FollowPill> createState() => _FollowPillState();
}

class _FollowPillState extends State<FollowPill> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed && widget.onTap != null) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final following = widget.following;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final duration = animate ? const Duration(milliseconds: 220) : Duration.zero;
    final ink = following ? IntroTheme.followedText : BiliColors.onPink;
    final label = Text(
      following ? '已关注' : '关注',
      style: TextStyle(fontFamily: BiliFonts.family, fontSize: IntroTheme.followText, height: 1, color: ink),
    );
    return Semantics(
      button: true,
      label: following ? '已关注' : '关注',
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? IntroTheme.followPressedScale : 1,
          duration: animate ? const Duration(milliseconds: 120) : Duration.zero,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            width: IntroTheme.followWidth,
            height: IntroTheme.followHeight,
            decoration: BoxDecoration(
              color: following ? IntroTheme.followedFill : BiliColors.pink,
              borderRadius: BorderRadius.circular(IntroTheme.followHeight / 2),
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: duration,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(animation), child: child),
              ),
              child: following
                  ? KeyedSubtree(key: const ValueKey('followed'), child: label)
                  : Row(
                      key: const ValueKey('follow'),
                      mainAxisSize: MainAxisSize.min,
                      spacing: IntroTheme.followPlusGap,
                      children: [
                        CustomPaint(size: const Size.square(IntroTheme.followPlus), painter: _PlusPainter(ink)),
                        label,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlusPainter extends CustomPainter {
  const _PlusPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = IntroTheme.followPlusStroke;
    final centre = size.center(Offset.zero);
    canvas
      ..drawLine(Offset(0, centre.dy), Offset(size.width, centre.dy), line)
      ..drawLine(Offset(centre.dx, 0), Offset(centre.dx, size.height), line);
  }

  @override
  bool shouldRepaint(_PlusPainter oldDelegate) => oldDelegate.color != color;
}

/// A card can come back with an empty name or face; the view's owner then stands in.
String _or(String? fromCard, String fromView) => fromCard == null || fromCard.isEmpty ? fromView : fromCard;
