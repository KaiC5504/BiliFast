import 'package:flutter/widgets.dart';

import 'comment_callbacks.dart';
import 'comments_model.dart';

/// 评论 (10-12): 热门评论 / 最新评论 with ≡ 按热度 / 按时间, the pinned comment, the list paging as it nears the end,
/// its footer, and the 哎呦，不错哦，发条评论吧 bar fixed at the bottom. Asks [model] for its first page when it first
/// shows. Its list scrolls with the page's primary scroll controller and starts `PlayerReserve` below its top.
class CommentsTab extends StatefulWidget {
  const CommentsTab({super.key, required this.model, required this.callbacks});

  final CommentsModel model;
  final CommentCallbacks callbacks;

  @override
  State<CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends State<CommentsTab> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// 评论 before the video's aid is known.
class CommentsSlot extends StatelessWidget {
  const CommentsSlot({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
