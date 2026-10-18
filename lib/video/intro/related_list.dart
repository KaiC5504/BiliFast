import 'package:bili_core/api.dart' show VideoCard;
import 'package:flutter/widgets.dart';

/// The related videos under 简介 (03, 18), as a sliver: cover with duration, title, UP and counts, and ⋮ 稍后再看.
class RelatedSliver extends StatelessWidget {
  const RelatedSliver({super.key, required this.cards, required this.onOpen, required this.onWatchLater});

  final List<VideoCard> cards;
  final ValueChanged<VideoCard> onOpen;
  final ValueChanged<VideoCard> onWatchLater;

  @override
  Widget build(BuildContext context) => const SliverToBoxAdapter(child: SizedBox.shrink());
}
