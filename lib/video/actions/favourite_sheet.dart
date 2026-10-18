import 'package:flutter/widgets.dart';

import 'video_actions.dart';

/// 收藏: the account's folders with ticks, 新建收藏夹 and 完成. A light sheet from the bottom in portrait, a dark panel
/// from the right in landscape ([dark]).
class FavouriteSheet extends StatelessWidget {
  const FavouriteSheet({super.key, required this.folders, required this.dark, required this.onClose});

  final FavouriteFolders folders;
  final bool dark;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
