import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

/// 主页 (114, 115): 收藏, 追番, 最近投币的视频, 最近点赞的视频 and 拥有的个性装扮, each with its count and 更多 ›, from the
/// own space's answer. [onMore] switches to 收藏's or 追番's tab.
class OwnHomeSliver extends StatelessWidget {
  const OwnHomeSliver({super.key, required this.profile, required this.onMore});

  final SpaceProfile profile;
  final ValueChanged<SpaceTabKind> onMore;

  @override
  Widget build(BuildContext context) => const SliverToBoxAdapter();
}
