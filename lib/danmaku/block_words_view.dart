import 'package:flutter/widgets.dart';

import '../player_ui/player_ui.dart';

/// 添加屏蔽词 (30): the field with 添加 and 同步, the tabs 关键词 / 正则 / 举报屏蔽用户, and each rule as a chip with ✕, over
/// the whole landscape screen.
// Contracts stub: slice 5's block-words agent writes it.
class BlockWordsView extends StatelessWidget {
  const BlockWordsView({
    super.key,
    required this.ui,
    required this.toast,
    required this.back,
    required this.close,
  });

  final PlayerUi ui;
  final ValueChanged<String> toast;

  /// Back to 弹幕设置.
  final VoidCallback back;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
