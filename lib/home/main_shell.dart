import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../me/me_page.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../skin/skin.dart';
import '../skin/skin_model.dart';
import 'home_page.dart';
import 'home_tab_bar.dart';

/// The bottom bar's places: 首页 and 我的 kept alive side by side, the bar under both (01, 02). A bar dressed by the
/// equipped 装扮 lies over the pages' bottom instead, so they show behind its picture (109, 110).
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.developerPage, this.initialLink, @visibleForTesting this.skin});

  final WidgetBuilder? developerPage;

  /// Passed to 首页 (`--play=` on the PC).
  final String? initialLink;

  /// The equipped 装扮 in place of [AppServices.skin], for 首页, the bar and 我的 alike.
  final SkinModel? skin;

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
  Widget build(BuildContext context) => ValueListenableBuilder<Skin?>(
    valueListenable: widget.skin ?? AppScope.of(context).skin,
    builder: (context, skin, _) => _build(context, skin),
  );

  Widget _build(BuildContext context, Skin? skin) {
    final mine = _tab == HomeTab.mine;
    final media = MediaQuery.of(context);
    final dressed = HomeTabBar.dresses(skin);
    final bar = HomeTabBarTheme.height + media.padding.bottom;
    // Under a dressed bar the pages run to the screen's bottom, inset by the stock bar, so lists end above its row
    // and scroll on behind its picture.
    final pages = dressed
        ? media.copyWith(
            padding: media.padding.copyWith(bottom: bar),
            viewPadding: media.viewPadding.copyWith(bottom: bar),
          )
        : media.removePadding(removeBottom: true);
    return Material(
      color: HomeTabBarTheme.bar,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: dressed ? 0 : bar,
            child: MediaQuery(
              data: pages,
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
                      skin: skin,
                    ),
                  ),
                  _Place(
                    shown: mine,
                    child: AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle.dark,
                      // A seam handed to a seam: only a test sets the shell's skin.
                      // ignore: invalid_use_of_visible_for_testing_member
                      child: MePage(active: mine, developerPage: widget.developerPage, skin: widget.skin),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: HomeTabBar(selected: _tab, onTap: _tapped, skin: skin),
          ),
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
