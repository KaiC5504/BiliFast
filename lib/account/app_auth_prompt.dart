import 'package:flutter/widgets.dart';

import '../settings/settings_confirm.dart';
import '../shared/theme.dart';

/// The app token's confirm: 设置's alert (51) over whatever is showing, completing with whether 授权 was pressed.
/// A pop from elsewhere (a page under it closing itself with true) is no 授权.
Future<bool> showAppAuthPrompt(BuildContext context) async {
  final route = AppAuthPromptRoute(reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false);
  await Navigator.of(context, rootNavigator: true).push(route);
  return route.authorized;
}

/// A popup rather than a page, so the page under it doesn't count as covered and its video plays on.
class AppAuthPromptRoute extends PopupRoute<bool> {
  AppAuthPromptRoute({required this.reduceMotion});

  static const title = '授权官方接口';
  static const message = '将打开哔哩哔哩客户端，点确认登录后返回本应用即可。登录设备中会多出一台设备';
  static const action = '授权';

  final bool reduceMotion;

  /// 授权 was pressed.
  bool get authorized => _authorized;
  bool _authorized = false;

  CurvedAnimation? _motion;

  // The alert draws its own dim, whose tap is 取消.
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => reduceMotion ? Duration.zero : AppAuthTheme.promptIn;

  @override
  Duration get reverseTransitionDuration => reduceMotion ? Duration.zero : AppAuthTheme.promptOut;

  void _answer(bool authorize) {
    if (!isCurrent) return;
    _authorized = authorize;
    navigator?.pop(authorize);
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      SettingsConfirm(
        key: const ValueKey('app-auth-prompt'),
        title: title,
        message: message,
        action: action,
        motion: _motion ??= CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        onConfirm: () => _answer(true),
        onCancel: () => _answer(false),
      );

  @override
  void dispose() {
    _motion?.dispose();
    super.dispose();
  }
}
