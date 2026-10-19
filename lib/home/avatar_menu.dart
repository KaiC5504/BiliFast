import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app/app_environment.dart';
import '../shared/menu.dart';
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
            ? RemoteImage.avatar(url)
            : ColoredBox(
                color: BiliColors.pageGrey,
                child: Icon(Icons.person, size: size * 0.55, color: BiliColors.divider),
              ),
      ),
    );
  }
}

enum AvatarMenuItem { login, history, recents, settings, developer }

/// What the avatar opens (port of AvatarMenu.swift): the account, then 历史记录, 最近打开, 设置 and, in dev builds, 开发者.
/// The official app keeps these on 我的 (02); with no tab bar they drop down from the avatar instead. Logged out or
/// expired, the account row's pill is the way to the login page; 退出登录 is at the bottom of 设置, as in the official
/// app, so the row has no 退出.
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
          child: _Account(environment: environment, onLogin: () => onSelect(AvatarMenuItem.login)),
        ),
        const Divider(height: 0.5, thickness: 0.5, color: BiliColors.divider),
        MenuRow(title: '历史记录', icon: Icons.history, onTap: () => onSelect(AvatarMenuItem.history)),
        MenuRow(title: '最近打开', icon: Icons.video_library_outlined, onTap: () => onSelect(AvatarMenuItem.recents)),
        MenuRow(title: '设置', icon: Icons.settings_outlined, onTap: () => onSelect(AvatarMenuItem.settings)),
        if (developer)
          MenuRow(title: '开发者', icon: Icons.build_outlined, onTap: () => onSelect(AvatarMenuItem.developer)),
        const SizedBox(height: 4),
      ],
    ),
  );
}

class _Account extends StatelessWidget {
  const _Account({required this.environment, required this.onLogin});

  final AppEnvironment environment;
  final VoidCallback onLogin;

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
              LoggedOut() => _SignedOut(label: '未登录', style: name, pill: '登录', onLogin: onLogin),
              LoginExpired() => _SignedOut(
                label: '登录已过期',
                style: name.copyWith(fontSize: BiliMetrics.bodyText),
                pill: '重新登录',
                onLogin: onLogin,
              ),
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

/// 未登录 or 登录已过期, with the pink pill that opens the login page.
class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.label, required this.style, required this.pill, required this.onLogin});

  final String label;
  final TextStyle style;
  final String pill;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      ),
      const SizedBox(width: BiliMetrics.menuPillGap),
      CupertinoButton(
        key: const ValueKey('menu-login'),
        onPressed: onLogin,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, BiliMetrics.menuAvatar),
        child: Container(
          height: BiliMetrics.menuPillHeight,
          padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.menuPillPadding),
          alignment: Alignment.center,
          decoration: const ShapeDecoration(color: BiliColors.pink, shape: StadiumBorder()),
          child: Text(
            pill,
            maxLines: 1,
            style: const TextStyle(
              fontSize: BiliMetrics.menuPillText,
              fontWeight: FontWeight.w500,
              color: BiliColors.onPink,
            ),
          ),
        ),
      ),
    ],
  );
}
