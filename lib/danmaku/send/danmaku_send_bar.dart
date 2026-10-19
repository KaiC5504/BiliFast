import 'package:flutter/widgets.dart';

import 'danmaku_send_model.dart';

/// A (with its red dot until first pressed), the field and the send arrow: dark in landscape (22), white in portrait
/// and 竖屏 (36, 37, 39).
// Contracts stub: slice 5's send agent writes it.
class DanmakuSendBar extends StatelessWidget {
  const DanmakuSendBar({super.key, required this.model, required this.dark});

  final DanmakuSendModel model;
  final bool dark;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
