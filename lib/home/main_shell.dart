import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../me/me_page.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import 'home_page.dart';
import 'home_tab_bar.dart';

/// The bottom bar's places: 首页 and 我的 kept alive side by side, the bar under both (01, 02).
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.developerPage, this.initialLink});

  final WidgetBuilder? developerPage;

  /// Passed to 首页 (`--play=` on the PC).
  final String? initialLink;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _reloads = _Reloads();
  HomeTab _tab = HomeTab.home;

  @override
  void dispose() {
    _reloads.dispose();
    super.dispose();
  }

  /// 首页 again on 首页 refreshes 推荐; coming back from 我的 it only shows it, where it was.
  void _tapped(HomeTab tab) {
    switch (tab) {
      case HomeTab.home when _tab == HomeTab.home:
        _reloads.request();
      case HomeTab.home || HomeTab.mine:
        if (tab != _tab) setState(() => _tab = tab);
      case HomeTab.follow || HomeTab.post || HomeTab.messages:
        showToast(context, '暂未开放');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = _tab == HomeTab.mine;
    return Material(
      color: HomeTabBarTheme.bar,
      child: Column(
        children: [
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: IndexedStack(
                index: mine ? 1 : 0,
                sizing: StackFit.expand,
                children: [
                  _Place(
                    shown: !mine,
                    child: HomePage(
                      developerPage: widget.developerPage,
                      initialLink: widget.initialLink,
                      reloads: _reloads,
                    ),
                  ),
                  _Place(
                    shown: mine,
                    child: AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle.dark,
                      child: MePage(active: mine, developerPage: widget.developerPage),
                    ),
                  ),
                ],
              ),
            ),
          ),
          HomeTabBar(selected: _tab, onTap: _tapped),
        ],
      ),
    );
  }
}

/// A place kept alive while hidden: still, and out of Hero flights, which an [IndexedStack] doesn't stop. Otherwise a
/// hidden 推荐 cover flies over 我的 to or from a pushed page holding the same tag (a space row's `cover-<bvid>`).
class _Place extends StatelessWidget {
  const _Place({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: shown,
    child: HeroMode(enabled: shown, child: child),
  );
}

class _Reloads extends ChangeNotifier {
  void request() => notifyListeners();
}
