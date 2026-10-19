import 'package:flutter/widgets.dart';

import 'danmaku_send_model.dart';

/// 弹幕字号, 弹幕类型 and 弹幕颜色 in the keyboard's place (23, 38).
// Contracts stub: slice 5's send agent writes it.
class DanmakuStylePanel extends StatelessWidget {
  const DanmakuStylePanel({super.key, required this.model, required this.dark, required this.offerBottom});

  final DanmakuSendModel model;
  final bool dark;

  /// 置底 is offered in landscape only; 竖屏's panel has 滚动 and 置顶 (38).
  final bool offerBottom;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
