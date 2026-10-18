import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app/app_environment.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';

/// The account's avatar; a grey head until the account has a face.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.face, required this.size});

  final String? face;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = face;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url != null && url.isNotEmpty
            ? RemoteImage(url)
            : ColoredBox(
                color: BiliColors.pageGrey,
                child: Icon(Icons.person, size: size * 0.55, color: BiliColors.divider),
              ),
      ),
    );
  }
}

enum AvatarMenuItem { history, recents, developer }

/// What the avatar opens (port of AvatarMenu.swift): the account, then 历史记录, 最近打开 and, in dev builds, 开发者.
/// The official app keeps these on 我的 (02); with no tab bar they drop down from the avatar instead. 历史记录 waits
/// for slice 8, and logging in and out with it.
class AvatarMenu extends StatelessWidget {
  const AvatarMenu({super.key, required this.environment, required this.developer, required this.onSelect});

  final AppEnvironment environment;

  /// Whether to offer 开发者 (dev builds).
  final bool developer;
  final void Function(AvatarMenuItem item) onSelect;

  @override
  Widget build(BuildContext context) => GlassPanel(
    key: const ValueKey('avatar-menu'),
    width: BiliMetrics.menuWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: _Account(environment: environment),
        ),
        const Divider(height: 0.5, thickness: 0.5, color: BiliColors.divider),
        const MenuRow(title: '历史记录', icon: Icons.history, onTap: null, note: '即将推出'),
        MenuRow(title: '最近打开', icon: Icons.video_library_outlined, onTap: () => onSelect(AvatarMenuItem.recents)),
        if (developer)
          MenuRow(title: '开发者', icon: Icons.build_outlined, onTap: () => onSelect(AvatarMenuItem.developer)),
        const SizedBox(height: 4),
      ],
    ),
  );
}

class _Account extends StatelessWidget {
  const _Account({required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    const name = TextStyle(fontSize: BiliMetrics.bodyText + 1, fontWeight: FontWeight.w500, color: BiliColors.text);
    final account = environment.account;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: BiliMetrics.menuAvatar),
      child: Row(
        children: [
          AccountAvatar(face: environment.face, size: BiliMetrics.menuAvatar),
          const SizedBox(width: 10),
          Expanded(
            child: switch (account) {
              AccountUnknown() when environment.accountCheckFailed => CupertinoButton(
                onPressed: environment.refreshAccount,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, BiliMetrics.menuAvatar),
                alignment: Alignment.centerLeft,
                child: const Text(
                  '无法获取账号信息，点按重试',
                  style: TextStyle(fontSize: BiliMetrics.smallText + 1, color: BiliColors.reason),
                ),
              ),
              AccountUnknown() => const Align(
                alignment: Alignment.centerLeft,
                child: CupertinoActivityIndicator(radius: BiliMetrics.menuSpinnerRadius),
              ),
              LoggedOut() => const Text('未登录', style: name),
              LoginExpired() => const Text('登录已过期', style: name),
              LoggedIn(name: final userName, :final vip) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    userName.isEmpty ? '已登录' : userName,
                    key: const ValueKey('menu-account-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: name.copyWith(color: vip ? BiliColors.pink : BiliColors.text),
                  ),
                  if (vip) ...[
                    const SizedBox(height: 4),
                    Container(
                      height: BiliMetrics.vipBadgeHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: const ShapeDecoration(color: BiliColors.pink, shape: StadiumBorder()),
                      child: const Text(
                        '大会员',
                        style: TextStyle(
                          fontSize: BiliMetrics.vipBadgeText,
                          fontWeight: FontWeight.w600,
                          color: BiliColors.card,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// Frosted glass under a menu: the page behind shows blurred through a light fill, inside a hairline rim.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(BiliMetrics.menuRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: BiliMetrics.glassShadow,
            blurRadius: BiliMetrics.glassShadowBlur,
            offset: Offset(0, BiliMetrics.glassShadowDrop),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: BiliMetrics.glassBlur, sigmaY: BiliMetrics.glassBlur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: BiliMetrics.glassFill,
              borderRadius: radius,
              border: Border.all(color: BiliMetrics.glassBorder, width: BiliMetrics.glassHairline),
            ),
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }
}

/// A menu row: icon and title, greyed and disabled without [onTap].
class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.title, required this.icon, required this.onTap, this.note});

  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  /// Shown at the right of a row that does nothing yet.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? BiliColors.secondaryText : BiliColors.text;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: onTap != null,
        child: PressHighlight(
          onTap: onTap,
          child: SizedBox(
            height: BiliMetrics.menuRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: BiliMetrics.menuIconBox,
                    child: Icon(icon, size: BiliMetrics.menuIcon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: BiliMetrics.bodyText, color: color),
                    ),
                  ),
                  if (note case final note?)
                    Text(
                      note,
                      style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.secondaryText),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Darkens [child] while a finger is on it, as iOS rows answer a touch, in place of Material's ripple.
class PressHighlight extends StatefulWidget {
  const PressHighlight({super.key, required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<PressHighlight> createState() => _PressHighlightState();
}

class _PressHighlightState extends State<PressHighlight> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _press(true) : null,
      onTapUp: enabled ? (_) => _press(false) : null,
      onTapCancel: enabled ? () => _press(false) : null,
      onTap: widget.onTap,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(color: _pressed ? BiliMetrics.pressedFill : null),
        child: widget.child,
      ),
    );
  }
}
