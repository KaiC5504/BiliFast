import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../page_details.dart' show PageTab;
import 'story_sheet.dart';

/// 竖屏's 简介/评论 sheet, placed over the whole page and drawn from [controller]'s position: the grabber, the tab
/// row with 评论's count and the ⌃⌄ / ✕ button, then [intro] or [comments].
class StorySheetView extends StatelessWidget {
  const StorySheetView({
    super.key,
    required this.controller,
    required this.intro,
    required this.comments,
    required this.replies,
  });

  final StorySheetController controller;
  final Widget intro;
  final Widget comments;

  /// 评论's count beside its tab; null until known.
  final ValueListenable<int?> replies;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListenableBuilder(
      listenable: Listenable.merge([controller, controller.position]),
      builder: (context, _) {
        final position = controller.position.value;
        if (position <= 0) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              top: StorySheetController.topFor(position, constraints.maxHeight),
              child: ColoredBox(
                color: BiliColors.card,
                child: Column(
                  children: [
                    const SizedBox(height: StorySheetTheme.headerHeight),
                    Expanded(
                      child: IndexedStack(
                        index: controller.tab == PageTab.intro ? 0 : 1,
                        children: [intro, comments],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
