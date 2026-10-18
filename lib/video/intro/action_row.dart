import 'package:flutter/widgets.dart';

import '../actions/video_actions.dart';

/// 点赞 不喜欢 投币 收藏 分享 under the title (03). Holding 点赞 fills rings around 点赞, 投币 and 收藏 and does 三连.
class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.actions});

  final VideoActions actions;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
