import 'package:flutter/widgets.dart';

import '../video/story/story_feed.dart';

/// A neighbour page's controls in 竖屏, drawn still from its [entry] while the page under the finger moves: all but the
/// top bar, which stays where it is.
class VerticalChromePreview extends StatelessWidget {
  const VerticalChromePreview({super.key, required this.entry});

  final StoryEntry entry;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
