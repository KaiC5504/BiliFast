import 'package:flutter/widgets.dart';

import '../player_ui/player_ui.dart';

/// 当前弹幕列表 (31, 32): the danmaku shown so far, each with its 👍 and a ⋮ offering 屏蔽弹幕.
// Contracts stub: slice 5's 当前弹幕列表 agent writes it.
class DanmakuListView extends StatelessWidget {
  const DanmakuListView({
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
