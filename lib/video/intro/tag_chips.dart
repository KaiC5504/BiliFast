import 'package:bili_core/api.dart' show VideoTag;
import 'package:flutter/widgets.dart';

/// The topic and BGM chips in a sideways row (03); plain tags are the title block's.
class TagChips extends StatelessWidget {
  const TagChips({super.key, required this.tags});

  final List<VideoTag> tags;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
