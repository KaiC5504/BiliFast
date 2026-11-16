import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// 首页's 热门 (204): the website's popular list, pulled to refresh and loaded on as it nears the end.
class HotList extends StatefulWidget {
  const HotList({super.key, required this.active, required this.scrollOffset, this.reloads});

  /// The page is on screen: the list loads the first time it is.
  final bool active;

  /// How far the list is scrolled, which folds 首页's header as 推荐's does.
  final ValueNotifier<double> scrollOffset;

  /// 首页 tapped again while 热门 shows: back to the top and refreshed.
  final Listenable? reloads;

  @override
  State<HotList> createState() => _HotListState();
}

class _HotListState extends State<HotList> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: HotListTheme.page);
}
