import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'tab_bar_icons.dart';

/// The bottom bar's five places (01, 02).
enum HomeTab {
  home('首页'),
  follow('关注'),
  post('发布'),
  messages('消息'),
  mine('我的');

  const HomeTab(this.label);

  final String label;
}

/// 首页's bottom bar (01): 首页 selected, 关注, the pink +, 消息 and 我的, over the home indicator.
class HomeTabBar extends StatelessWidget {
  const HomeTabBar({super.key, required this.onTap});

  final ValueChanged<HomeTab> onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: HomeTabBarTheme.bar,
      border: Border(
        top: BorderSide(color: HomeTabBarTheme.hairline, width: HomeTabBarTheme.hairlineWidth),
      ),
    ),
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: HomeTabBarTheme.height,
        child: Row(
          children: [
            for (final tab in HomeTab.values)
              Expanded(
                child: _Slot(tab: tab, selected: tab == HomeTab.home, onTap: () => onTap(tab)),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A glyph over its label, or the + alone, centred in the bar.
class _Slot extends StatelessWidget {
  const _Slot({required this.tab, required this.selected, required this.onTap});

  final HomeTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final post = tab == HomeTab.post;
    final centre = post ? HomeTabBarTheme.postCentre : HomeTabBarTheme.iconCentre;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        key: ValueKey('home-tab-${tab.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: centre * 2,
                child: Center(child: HomeTabIcon(tab, selected: selected)),
              ),
              if (!post)
                Positioned(
                  top: HomeTabBarTheme.labelTop,
                  left: 0,
                  right: 0,
                  child: Text(
                    tab.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: HomeTabBarTheme.labelText,
                      color: selected ? HomeTabBarTheme.selected : HomeTabBarTheme.label,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
