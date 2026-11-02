import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/cupertino.dart';

import '../dynamic/following/following_page.dart' show followingStyle;
import '../search/results/user_row.dart' show VerifiedBoltPainter;
import '../shared/loading_tv.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import 'friends_glyphs.dart';
import 'friends_model.dart';
import 'friends_route.dart';

/// One line of [text] in [style], its line box centred where it is placed.
Widget friendsLine(String text, TextStyle style, {Key? key, TextAlign align = TextAlign.left}) => Text(
  text,
  key: key,
  style: style,
  strutStyle: BiliFonts.strut(style),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  textAlign: align,
);

/// What a row's pill says: grey with ≡ while the account follows the person, pink to follow (again, or back).
enum RelationPillKind {
  followed('已关注'),
  mutual('已互粉'),
  follow('关注'),
  followBack('回关');

  const RelationPillKind(this.label);

  final String label;

  bool get grey => this == followed || this == mutual;

  /// [user]'s pill in [tab], [following] being what the row shows now.
  static RelationPillKind of(RelationUser user, {required FriendsTab tab, required bool following}) => switch (tab) {
    FriendsTab.following when following => user.mutual ? mutual : followed,
    FriendsTab.following => follow,
    FriendsTab.fans => following ? mutual : followBack,
  };
}

/// A list on the page: the TV while its first page loads, its failure with 重试, the empty picture, or the rows with
/// the footer's spinner or 加载失败，点击重试. [emptyTop] places the picture as 165 does under the tab row.
class FriendsLane extends StatelessWidget {
  const FriendsLane({
    super.key,
    required this.lane,
    required this.tab,
    required this.model,
    required this.scroll,
    required this.emptyTop,
    required this.onRetry,
    required this.onOpen,
    required this.onPill,
  });

  final RelationLane lane;
  final FriendsTab tab;
  final FriendsModel model;
  final ScrollController scroll;
  final double emptyTop;
  final VoidCallback onRetry;
  final ValueChanged<RelationUser> onOpen;
  final ValueChanged<RelationUser> onPill;

  @override
  Widget build(BuildContext context) {
    if (!lane.loaded) {
      final error = lane.error;
      if (error == null) return const Center(child: LoadingTvState());
      return FriendsMessage(
        key: ValueKey('friends-failed-${tab.name}'),
        message: error,
        action: '重试',
        actionKey: ValueKey('friends-retry-${tab.name}'),
        onAction: onRetry,
      );
    }
    if (lane.users.isEmpty) return FriendsEmpty(key: ValueKey('friends-empty-${tab.name}'), top: emptyTop);
    final media = MediaQuery.of(context);
    final bottom = math.max(media.viewInsets.bottom, media.padding.bottom);
    final users = lane.users;
    return ListView.builder(
      controller: scroll,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: bottom),
      itemCount: users.length + 1,
      itemBuilder: (context, index) {
        if (index == users.length) {
          return _Footer(tab: tab, loading: lane.loading, error: lane.error, onRetry: onRetry);
        }
        final user = users[index];
        return FriendsRow(
          user: user,
          pill: RelationPillKind.of(user, tab: tab, following: model.isFollowing(user)),
          busy: model.isBusy(user),
          onTap: () => onOpen(user),
          onPill: () => onPill(user),
        );
      },
    );
  }
}

/// A person (163): face, name, sign and the pill. The row and the pill are separate buttons to accessibility, so
/// VoiceOver reaches the pill's ≡ 已关注 / 回关 as well as the space.
class FriendsRow extends StatelessWidget {
  const FriendsRow({
    super.key,
    required this.user,
    required this.pill,
    required this.busy,
    required this.onTap,
    required this.onPill,
  });

  final RelationUser user;
  final RelationPillKind pill;

  /// A 关注 change is out: the pill shows it and takes no taps.
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onPill;

  @override
  Widget build(BuildContext context) {
    final person = user.user;
    final name = followingStyle(
      FriendsTheme.nameText,
      person.vipPink ? FriendsTheme.vipName : FriendsTheme.name,
      line: FriendsTheme.nameLine,
    );
    final sign = followingStyle(FriendsTheme.signText, FriendsTheme.sign, line: FriendsTheme.signLine);
    const textRight = FriendsTheme.pillRight + FriendsTheme.pillWidth + FriendsTheme.textGap;
    final nameCentre = person.sign.isEmpty ? FriendsTheme.row / 2 : FriendsTheme.nameCentre;
    final body = Semantics(
      button: true,
      label: person.name,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('friends-row-${user.mid}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: FriendsTheme.row,
          child: Stack(
            children: [
              Positioned(
                left: FriendsTheme.faceInset,
                top: (FriendsTheme.row - FriendsTheme.face) / 2,
                width: FriendsTheme.face,
                height: FriendsTheme.face,
                child: _Face(user: person, collectible: user.collectibleFace),
              ),
              Positioned(
                left: FriendsTheme.textLeft,
                right: textRight,
                top: nameCentre - FriendsTheme.nameLine / 2,
                height: FriendsTheme.nameLine,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: friendsLine(person.name, name, key: ValueKey('friends-name-${user.mid}')),
                ),
              ),
              if (person.sign.isNotEmpty)
                Positioned(
                  left: FriendsTheme.textLeft,
                  right: textRight,
                  top: FriendsTheme.signCentre - FriendsTheme.signLine / 2,
                  height: FriendsTheme.signLine,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: friendsLine(person.sign, sign, key: ValueKey('friends-sign-${user.mid}')),
                  ),
                ),
              const Positioned(
                left: FriendsTheme.textLeft,
                right: 0,
                bottom: FriendsTheme.rowRule,
                height: FriendsTheme.rowRule,
                child: ColoredBox(color: FriendsTheme.rowRuleInk),
              ),
            ],
          ),
        ),
      ),
    );
    return SizedBox(
      height: FriendsTheme.row,
      child: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            right: FriendsTheme.pillRight,
            top: FriendsTheme.pillTop,
            width: FriendsTheme.pillWidth,
            height: FriendsTheme.pillHeight,
            child: RelationPill(
              key: ValueKey('friends-pill-${user.mid}'),
              kind: pill,
              onTap: busy ? null : onPill,
            ),
          ),
        ],
      ),
    );
  }
}

/// ≡ 已关注 / ≡ 已互粉 on grey, or 关注 / 回关 on pink.
class RelationPill extends StatelessWidget {
  const RelationPill({super.key, required this.kind, required this.onTap});

  final RelationPillKind kind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final grey = kind.grey;
    final style = followingStyle(
      FriendsTheme.pillText,
      grey ? FriendsTheme.pillInk : FriendsTheme.pillActionInk,
      line: FriendsTheme.pillLine,
    );
    final words = friendsLine(kind.label, style, key: const ValueKey('friends-pill-label'));
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: kind.label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: grey ? FriendsTheme.pillFill : FriendsTheme.pillActionFill,
            shape: const StadiumBorder(),
          ),
          child: grey
              ? Stack(
                  children: [
                    Positioned(
                      left: FriendsTheme.pillGlyphLeft,
                      top: (FriendsTheme.pillHeight - FriendsTheme.pillGlyphHeight) / 2 + 1,
                      width: FriendsTheme.pillGlyphWidth,
                      height: FriendsTheme.pillGlyphHeight,
                      child: const CustomPaint(painter: PillMenuPainter(color: FriendsTheme.pillInk)),
                    ),
                    Positioned(
                      left: FriendsTheme.pillTextLeft,
                      right: 0,
                      top: 0.5,
                      bottom: 0,
                      child: Align(alignment: Alignment.centerLeft, child: words),
                    ),
                  ],
                )
              : Center(child: words),
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.user, required this.collectible});

  final FollowingUser user;

  /// A 数字藏品 face: the APK's ◇ disc left of the bolt's place.
  final bool collectible;

  @override
  Widget build(BuildContext context) {
    final badge = switch (user.verify) {
      DynamicVerify.personal => FriendsTheme.badgePerson,
      DynamicVerify.organisation => FriendsTheme.badgeOrganisation,
      DynamicVerify.none => null,
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: ClipOval(child: RemoteImage.avatar(user.face))),
        if (collectible)
          Positioned(
            right: FriendsTheme.collectibleRight - FriendsTheme.badgeRing,
            bottom: -FriendsTheme.badgeRing,
            child: Container(
              key: ValueKey('friends-collectible-${user.mid}'),
              width: FriendsTheme.badge + FriendsTheme.badgeRing * 2,
              height: FriendsTheme.badge + FriendsTheme.badgeRing * 2,
              padding: const EdgeInsets.all(FriendsTheme.badgeRing),
              decoration: const BoxDecoration(color: FriendsTheme.page, shape: BoxShape.circle),
              child: Image.asset('assets/images/friends/face_collectible.png'),
            ),
          ),
        if (badge != null)
          Positioned(
            right: -FriendsTheme.badgeRing,
            bottom: -FriendsTheme.badgeRing,
            child: Container(
              key: ValueKey('friends-verified-${user.mid}'),
              width: FriendsTheme.badge + FriendsTheme.badgeRing * 2,
              height: FriendsTheme.badge + FriendsTheme.badgeRing * 2,
              padding: const EdgeInsets.all(FriendsTheme.badgeRing),
              decoration: const BoxDecoration(color: FriendsTheme.page, shape: BoxShape.circle),
              child: CustomPaint(painter: VerifiedBoltPainter(badge)),
            ),
          ),
      ],
    );
  }
}

/// 165: the APK's empty picture, [top] under where the list starts, and 这里还什么都没有呢～ under it.
class FriendsEmpty extends StatelessWidget {
  const FriendsEmpty({super.key, required this.top});

  final double top;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/friends/page_status_empty.png',
            width: FriendsTheme.emptyPicture,
            height: FriendsTheme.emptyPicture,
          ),
          const SizedBox(height: FriendsTheme.emptyTextCentre - FriendsTheme.emptyLine / 2),
          SizedBox(
            height: FriendsTheme.emptyLine,
            child: friendsLine(
              '这里还什么都没有呢～',
              followingStyle(FriendsTheme.emptyText, FriendsTheme.emptyInk, line: FriendsTheme.emptyLine),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Words over a pink-ringed button, centred: a failed first page with 重试, or the account's state.
class FriendsMessage extends StatelessWidget {
  const FriendsMessage({
    required super.key,
    required this.message,
    required this.action,
    required this.actionKey,
    required this.onAction,
  });

  final String message;
  final String action;
  final Key actionKey;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        friendsLine(message, followingStyle(FollowingListTheme.stateText, FollowingListTheme.stateInk)),
        const SizedBox(height: FollowingListTheme.stateGap),
        Semantics(
          button: true,
          label: action,
          onTap: onAction,
          excludeSemantics: true,
          child: GestureDetector(
            key: actionKey,
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Container(
              height: FollowingListTheme.retryHeight,
              padding: const EdgeInsets.symmetric(horizontal: FollowingListTheme.retryPadX),
              alignment: Alignment.center,
              decoration: const ShapeDecoration(
                shape: StadiumBorder(
                  side: BorderSide(color: BiliColors.pink, width: FollowingListTheme.retryRim),
                ),
              ),
              child: Text(action, style: followingStyle(FollowingListTheme.retryText, BiliColors.pink)),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Under the rows: the small spinner while the next page loads, or 加载失败，点击重试.
class _Footer extends StatelessWidget {
  const _Footer({required this.tab, required this.loading, required this.error, required this.onRetry});

  final FriendsTab tab;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.symmetric(vertical: FollowingListTheme.footerPad);
    if (loading) {
      return Padding(
        padding: padding,
        child: CupertinoActivityIndicator(
          key: ValueKey('friends-more-spinner-${tab.name}'),
          radius: FollowingListTheme.spinnerRadius,
        ),
      );
    }
    if (error == null) return const SizedBox.shrink();
    final style = followingStyle(FollowingListTheme.footerText, FollowingListTheme.footerInk);
    return Semantics(
      button: true,
      label: '加载失败，点击重试',
      onTap: onRetry,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('friends-footer-retry-${tab.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onRetry,
        child: Padding(
          padding: padding,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '加载失败，', style: style),
                TextSpan(
                  text: '点击重试',
                  style: style.copyWith(color: BiliColors.link),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
