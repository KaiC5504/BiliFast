import 'package:flutter/widgets.dart';

import '../../live/live_api.dart';

/// 首页's 直播 page (205): the carousel, 我的关注's strip, the area tabs and their cards. [active] while it holds the
/// screen and 首页 is shown (the carousel plays only then); [scrollOffset] folds the header as 推荐's does; [reloads]
/// fires on 首页's tap.
class LiveTab extends StatefulWidget {
  const LiveTab({super.key, required this.active, required this.scrollOffset, this.reloads, this.api});

  final bool active;
  final ValueNotifier<double> scrollOffset;
  final Listenable? reloads;

  /// Tests' calls; the app's otherwise.
  final LiveApi? api;

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
