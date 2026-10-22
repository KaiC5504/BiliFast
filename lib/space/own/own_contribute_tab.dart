import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

/// 投稿: the space's video list, or with no videos 108's empty page (发布第一个视频，领新人福利, 我要投稿, 去创作中心领奖).
class OwnContributeSliver extends StatelessWidget {
  const OwnContributeSliver({super.key, required this.profile});

  final SpaceProfile profile;

  @override
  Widget build(BuildContext context) => const SliverToBoxAdapter();
}
