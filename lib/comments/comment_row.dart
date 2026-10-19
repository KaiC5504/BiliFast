import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import 'comment_callbacks.dart';
import 'comments_model.dart';

/// One comment (10, 12, 13): avatar with its pendant and marks, name, LV and the other badges, the fan card, the
/// text, pictures, the meta line (time, place, 回复, 👍 N, 👎, ⋮) and, in the list, the replies preview.
class CommentRow extends StatelessWidget {
  const CommentRow({
    super.key,
    required this.comment,
    required this.model,
    required this.callbacks,
    this.thread,
    this.showsReplies = true,
    this.showsDivider = true,
  });

  final Comment comment;
  final CommentsModel model;
  final CommentCallbacks callbacks;

  /// Inside 评论详情, the thread's root: 回复 on a reply then answers it in the thread.
  final Comment? thread;

  /// The grey box of reply previews and 共N条回复, in the list only.
  final bool showsReplies;

  /// The hairline under the row, indented to the text.
  final bool showsDivider;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
