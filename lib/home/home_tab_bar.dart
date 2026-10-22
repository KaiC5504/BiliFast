import 'dart:io';

import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import '../skin/skin.dart';
import 'tab_bar_icons.dart';

/// The bottom bar's five places (01, 02).
enum HomeTab {
  home('首页', 0),
  follow('关注', 1),
  post('发布'),
  messages('消息', 3),
  mine('我的', 4);

  const HomeTab(this.label, [this.skinIcon]);

  final String label;

  /// Which of a 装扮's five icons (main, channel, dynamic, shop, myself) is this place's. The official app drops the
  /// middle one (dynamic) when it has fewer places, so 关注 takes channel and 消息 shop.
  final int? skinIcon;
}

/// The bottom bar under 首页 and 我的 (01, 02): 首页, 关注, the pink +, 消息 and 我的 over the home indicator, [selected]
/// pink. A [skin] that [dresses] it draws its picture, icons and label colours instead (109, 110), once its still
/// pictures have decoded; until then, or for good when one won't, the bar stays stock.
class HomeTabBar extends StatelessWidget {
  const HomeTabBar({super.key, required this.selected, required this.onTap, this.skin});

  final HomeTab selected;
  final ValueChanged<HomeTab> onTap;

  /// The equipped 装扮; null, or one [dresses] refuses, leaves it stock.
  final Skin? skin;

  /// Whether [skin] dresses the bar: its picture, both label colours and all five icons each way. Without any of
  /// them the bar stays stock.
  static bool dresses(Skin? skin) =>
      skin != null &&
      skin.themesBar &&
      skin.tailBg != null &&
      skin.tailIcons.length >= 5 &&
      skin.tailIconsSelected.length >= 5;

  /// The still pictures a dressed bar draws. Animated icons wait on their own decode, over a still fallback.
  static List<File> _stills(Skin skin) => [
    skin.tailBg!,
    for (final icon in [
      for (final tab in HomeTab.values)
        if (tab.skinIcon case final index?) ...[skin.tailIcons[index], skin.tailIconsSelected[index]],
      ?skin.pubButton,
    ])
      if (!icon.animated) icon.file,
  ];

  @override
  Widget build(BuildContext context) {
    final skin = dresses(this.skin) ? this.skin : null;
    return SkinDecodeGate(
      pictures: skin == null ? const [] : _stills(skin),
      builder: (context, decoded) => skin != null && decoded ? _dressed(context, skin) : _stock(context),
    );
  }

  Widget _row(BuildContext context, Skin? skin) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
    child: SizedBox(
      height: HomeTabBarTheme.height,
      child: Row(
        children: [
          for (final tab in HomeTab.values)
            Expanded(
              child: _Slot(tab: tab, selected: tab == selected, skin: skin, onTap: () => onTap(tab)),
            ),
        ],
      ),
    ),
  );

  Widget _stock(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: HomeTabBarTheme.bar,
      border: Border(
        top: BorderSide(color: HomeTabBarTheme.hairline, width: HomeTabBarTheme.hairlineWidth),
      ),
    ),
    child: _row(context, null),
  );

  /// The picture's own shape sets how far it rises over the row; one too flat to reach the row's top is cropped at
  /// the sides to cover it. Above the row the bar takes taps only over the icons' tops: the rest of a rising picture
  /// leaves them to the page under it.
  Widget _dressed(BuildContext context, Skin skin) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: HomeTabBarTheme.skinIconOverhang,
          child: Row(
            children: [
              for (final tab in HomeTab.values)
                Expanded(
                  child: tab.skinIcon == null
                      ? const SizedBox.shrink()
                      : Center(
                          child: GestureDetector(
                            key: ValueKey('home-tab-${tab.name}-rise'),
                            behavior: HitTestBehavior.opaque,
                            excludeFromSemantics: true,
                            onTap: () => onTap(tab),
                            child: const SizedBox(
                              width: HomeTabBarTheme.skinIconWidth,
                              height: HomeTabBarTheme.skinIconOverhang,
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ConstrainedBox(
                key: const ValueKey('home-tab-art'),
                constraints: BoxConstraints(minHeight: HomeTabBarTheme.height + bottom),
                child: SkinDecodeGate.image(skin.tailBg!, alignment: Alignment.bottomCenter),
              ),
            ),
            _row(context, skin),
          ],
        ),
      ],
    );
  }
}

/// A glyph over its label, or the + alone, centred in the bar. Dressed, the 装扮's picture rises over the bar's top.
class _Slot extends StatelessWidget {
  const _Slot({required this.tab, required this.selected, required this.onTap, this.skin});

  final HomeTab tab;
  final bool selected;
  final VoidCallback onTap;
  final Skin? skin;

  @override
  Widget build(BuildContext context) {
    final post = tab == HomeTab.post;
    final centre = post ? HomeTabBarTheme.postCentre : HomeTabBarTheme.iconCentre;
    final skin = this.skin;
    final pub = skin?.pubButton;
    final labelColour = skin == null
        ? (selected ? HomeTabBarTheme.selected : HomeTabBarTheme.label)
        : (selected ? skin.tailColorSelected! : skin.tailColor!);
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
            clipBehavior: skin == null ? Clip.hardEdge : Clip.none,
            children: [
              if (skin == null || (post && pub == null))
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: centre * 2,
                  child: Center(child: HomeTabIcon(tab, selected: selected)),
                )
              else if (pub != null && post)
                _box(
                  centre: HomeTabBarTheme.skinPostCentre,
                  width: HomeTabBarTheme.skinPostSize,
                  height: HomeTabBarTheme.skinPostSize,
                  child: SkinPicture(pub),
                )
              else if (tab.skinIcon case final index?)
                _box(
                  centre: HomeTabBarTheme.skinIconCentre,
                  width: HomeTabBarTheme.skinIconWidth,
                  height: HomeTabBarTheme.skinIconHeight,
                  child: SkinTabIcon(
                    icon: skin.tailIcons[index],
                    selectedIcon: skin.tailIconsSelected[index],
                    selected: selected,
                    loop: skin.equip.colors.tailIconCycle,
                    rise: skin.equip.colors.tailIconAnimated,
                  ),
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
                    style: TextStyle(fontSize: HomeTabBarTheme.labelText, color: labelColour),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A dressed picture's box, centred on the slot's column [centre] pt under the bar's top.
  Widget _box({required double centre, required double width, required double height, required Widget child}) =>
      Positioned(
        key: ValueKey('home-tab-${tab.name}-skin'),
        top: centre - height / 2,
        left: 0,
        right: 0,
        height: height,
        child: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      );
}
