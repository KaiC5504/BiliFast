import 'package:flutter/widgets.dart';

/// The room each tab's scroll view leaves above its content for the shrinking player (BiliNative
/// `CollapsingPlayer`'s reserve). Each tab's list starts with a gap this tall and scrolls with the page's primary
/// scroll controller.
class PlayerReserve extends InheritedWidget {
  const PlayerReserve({super.key, required this.height, required super.child});

  final double height;

  /// 0 outside a video page.
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PlayerReserve>()?.height ?? 0;

  @override
  bool updateShouldNotify(PlayerReserve oldWidget) => oldWidget.height != height;
}
