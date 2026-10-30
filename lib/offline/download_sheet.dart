import 'package:flutter/widgets.dart';

import '../player_ui/player_ui.dart';

/// 缓存 (141, 144, 153, 154): 画质 with its picker (142), the part or the 合集's videos with each one's state, 缓存全部,
/// 查看缓存 and the space line.
class DownloadSheet extends StatelessWidget {
  const DownloadSheet({super.key, required this.ui, required this.toast, required this.close});

  final PlayerUi ui;
  final void Function(String message) toast;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
