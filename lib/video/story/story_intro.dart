import 'package:flutter/widgets.dart';

import '../intro/intro_tab.dart' show IntroContent;

/// The 竖屏 sheet's 简介 (265, 269, 271): the title, the stats line, the description as the page's 简介 draws it, then
/// 相关视频 as a two-column grid of at most [StoryIntroTheme.relatedLimit] cards under a heading that stays pinned
/// under the tab row, ending with 已经到底了....
class StoryIntro extends StatelessWidget {
  const StoryIntro({
    super.key,
    required this.content,
    required this.onOpenRelated,
    required this.onSeek,
    required this.onOpenVideo,
  });

  final IntroContent content;

  /// A related card's tap: its index in [IntroContent.related].
  final ValueChanged<int> onOpenRelated;

  /// A timestamp in the description.
  final ValueChanged<double> onSeek;

  /// A video id in the description.
  final ValueChanged<String> onOpenVideo;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
