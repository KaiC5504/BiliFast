import 'package:flutter/widgets.dart';

import 'video_actions.dart';

/// 投币 (15): the one- and two-coin crates, 22娘, the balance and 同时点赞内容, over the whole page.
class CoinDialog extends StatelessWidget {
  const CoinDialog({super.key, required this.actions, required this.onClose});

  final VideoActions actions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
