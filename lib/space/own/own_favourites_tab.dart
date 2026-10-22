import 'package:flutter/widgets.dart';

/// 收藏 (116): 我创建的收藏夹 with its count, collapsing, its rows opening the folder.
class OwnFavouritesSliver extends StatelessWidget {
  const OwnFavouritesSliver({super.key, required this.mid});

  final int mid;

  @override
  Widget build(BuildContext context) => const SliverToBoxAdapter();
}
