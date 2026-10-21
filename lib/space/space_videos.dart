import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import 'space_api.dart';

/// 投稿's list as slivers in the space's scroll view (63, 69, 70, 74).
class SpaceVideosSliver extends StatefulWidget {
  const SpaceVideosSliver({super.key, required this.profile, required this.api});

  final SpaceProfile profile;
  final SpaceApi api;

  @override
  State<SpaceVideosSliver> createState() => _SpaceVideosSliverState();
}

class _SpaceVideosSliverState extends State<SpaceVideosSliver> {
  @override
  Widget build(BuildContext context) => const SliverToBoxAdapter(child: SizedBox.shrink());
}
